import XCTest
@testable import InklineCore

/// A macro target backed by a plain `TextBuffer`: exactly what the editor does,
/// minus the views. This is what makes the macro system testable at all.
private final class BufferMacroTarget: MacroExecutionTarget {
    let buffer: TextBuffer
    var caret: Int = 0
    var lastSearchFailed = false

    init(_ text: String) {
        buffer = TextBuffer(text: text)
    }

    var caretOffset: Int { caret }
    var documentLength: Int { buffer.length }
    var text: String { buffer.text }

    func perform(_ action: MacroAction) throws {
        switch action {
        case let .insertText(value):
            buffer.replace(caret..<caret, with: value)
            caret += value.utf16.count
        case .newline:
            try perform(.insertText("\n"))
        case .tab:
            try perform(.insertText("\t"))
        case .deleteBackward:
            guard caret > 0 else { return }
            buffer.replace((caret - 1)..<caret, with: "")
            caret -= 1
        case .deleteForward:
            guard caret < buffer.length else { return }
            buffer.replace(caret..<(caret + 1), with: "")
        case .deleteLine:
            let line = buffer.lineNumber(at: caret)
            let range = buffer.lineRange(line)
            buffer.replace(range, with: "")
            caret = min(range.lowerBound, buffer.length)
        case let .move(movement, _):
            switch movement {
            case .right: caret = min(caret + 1, buffer.length)
            case .left: caret = max(caret - 1, 0)
            case .documentStart: caret = 0
            case .documentEnd: caret = buffer.length
            case .lineStart: caret = buffer.offsetOfLineStart(buffer.lineNumber(at: caret))
            case .lineEnd: caret = buffer.lineContentRange(buffer.lineNumber(at: caret)).upperBound
            default: break
            }
        case let .find(query, direction):
            guard let match = try SearchEngine.firstMatch(of: query,
                                                          in: buffer.text,
                                                          from: caret,
                                                          direction: direction) else {
                lastSearchFailed = true
                throw MacroPlaybackError.noMatch
            }
            caret = match.range.upperBound
        case let .replaceSelection(value):
            try perform(.insertText(value))
        case let .goToLine(line):
            caret = buffer.offsetOfLineStart(min(line, buffer.lineCount - 1))
        default:
            throw MacroPlaybackError.unsupportedAction(action.displayDescription)
        }
    }
}

final class MacroTests: XCTestCase {

    func testRecorderCollectsActions() {
        let recorder = MacroRecorder()
        recorder.start()
        recorder.record(.insertText("h"))
        recorder.record(.insertText("i"))
        recorder.record(.newline)
        let macro = recorder.stop(name: "Groet")

        XCTAssertEqual(macro?.name, "Groet")
        XCTAssertEqual(macro?.actions.count, 2, "opeenvolgend typen wordt samengevoegd")
        XCTAssertEqual(macro?.actions.first, .insertText("hi"))
    }

    func testRecorderIgnoresActionsWhenPaused() {
        let recorder = MacroRecorder()
        recorder.start()
        recorder.pause()
        recorder.record(.newline)
        recorder.resume()
        recorder.record(.tab)
        XCTAssertEqual(recorder.stop()?.actions, [.tab])
    }

    func testEmptyRecordingReturnsNil() {
        let recorder = MacroRecorder()
        recorder.start()
        XCTAssertNil(recorder.stop())
    }

    func testPlaybackAppliesActions() throws {
        let target = BufferMacroTarget("")
        let macro = Macro(name: "Regel", actions: [.insertText("hallo"), .newline])
        try MacroPlayer.play(macro, on: target)
        XCTAssertEqual(target.text, "hallo\n")
    }

    func testPlaybackRepeatsFixedNumberOfTimes() throws {
        let target = BufferMacroTarget("")
        let macro = Macro(name: "Streep", actions: [.insertText("-")])
        let iterations = try MacroPlayer.play(macro, on: target, repeatMode: .times(5))
        XCTAssertEqual(iterations, 5)
        XCTAssertEqual(target.text, "-----")
    }

    func testPlaybackUntilEndOfDocumentStopsAtEnd() throws {
        let target = BufferMacroTarget("een\ntwee\ndrie\nvier\n")
        // Find the next newline and put a marker in front of it.
        let query = SearchQuery(pattern: "\n", wrapsAround: false)
        let macro = Macro(name: "Markeer", actions: [.find(query: query, direction: .forward),
                                                     .insertText("#")])
        let iterations = try MacroPlayer.play(macro, on: target, repeatMode: .untilEndOfDocument)

        XCTAssertEqual(iterations, 4, "één keer per regeleinde, daarna is het bestand op")
        XCTAssertEqual(target.text, "een\n#twee\n#drie\n#vier\n#")
    }

    func testPlaybackStopsWhenSearchFails() throws {
        let target = BufferMacroTarget("een twee")
        let macro = Macro(name: "Zoek", actions: [.find(query: SearchQuery(pattern: "zzz", wrapsAround: false),
                                                        direction: .forward)])
        let iterations = try MacroPlayer.play(macro, on: target, repeatMode: .untilEndOfDocument)
        XCTAssertEqual(iterations, 0)
        XCTAssertTrue(target.lastSearchFailed)
    }

    func testUnsupportedActionThrows() {
        let target = BufferMacroTarget("")
        let macro = Macro(name: "Onbekend", actions: [.command("nl.rorymeijer.inkline.onbekend")])
        XCTAssertThrowsError(try MacroPlayer.play(macro, on: target))
    }

    func testMacroCodableRoundTrip() throws {
        let macro = Macro(name: "Test",
                          actions: [.insertText("x"),
                                    .move(.wordRight, extendingSelection: true),
                                    .find(query: SearchQuery(pattern: "a", isRegularExpression: true),
                                          direction: .backward),
                                    .replaceAll(query: SearchQuery(pattern: "b"), replacement: "c"),
                                    .goToLine(12)],
                          keyEquivalent: "1",
                          modifierDescription: "cmd,ctrl")
        let data = try JSONEncoder().encode(macro)
        let decoded = try JSONDecoder().decode(Macro.self, from: data)
        XCTAssertEqual(decoded.actions, macro.actions)
        XCTAssertEqual(decoded.keyEquivalent, "1")
    }

    func testMacroStorePersists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("inkline-macros-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MacroStore(applicationSupportDirectory: directory)
        store.add(Macro(name: "Een", actions: [.tab]))
        try store.save()

        let reloaded = MacroStore(applicationSupportDirectory: directory)
        XCTAssertEqual(reloaded.macros.count, 1)
        XCTAssertEqual(reloaded.macro(named: "Een")?.actions, [.tab])
    }
}
