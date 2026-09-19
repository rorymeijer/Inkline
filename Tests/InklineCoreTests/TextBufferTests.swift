import XCTest
@testable import InklineCore

final class TextBufferTests: XCTestCase {

    func testReplaceNotifiesObservers() {
        let buffer = TextBuffer(text: "hallo")
        var changes = [TextChange]()
        buffer.addObserver { changes.append($0) }

        buffer.replace(5..<5, with: " wereld")

        XCTAssertEqual(buffer.text, "hallo wereld")
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.insertedText, " wereld")
        XCTAssertEqual(changes.first?.delta, 7)
    }

    func testUndoRedoRoundTrip() {
        let buffer = TextBuffer(text: "een")
        buffer.coalescing = .disabled

        buffer.replace(3..<3, with: " twee")
        buffer.replace(8..<8, with: " drie")
        XCTAssertEqual(buffer.text, "een twee drie")

        buffer.undo()
        XCTAssertEqual(buffer.text, "een twee")
        buffer.undo()
        XCTAssertEqual(buffer.text, "een")
        XCTAssertFalse(buffer.canUndo)

        buffer.redo()
        XCTAssertEqual(buffer.text, "een twee")
        buffer.redo()
        XCTAssertEqual(buffer.text, "een twee drie")
        XCTAssertFalse(buffer.canRedo)
    }

    func testUndoGroupIsOneStep() {
        let buffer = TextBuffer(text: "")
        buffer.coalescing = .disabled

        buffer.beginUndoGroup()
        buffer.replace(0..<0, with: "a")
        buffer.replace(1..<1, with: "b")
        buffer.replace(2..<2, with: "c")
        buffer.endUndoGroup()
        XCTAssertEqual(buffer.text, "abc")

        buffer.undo()
        XCTAssertEqual(buffer.text, "")
    }

    func testTypingCoalescesIntoOneUndoStep() {
        let buffer = TextBuffer(text: "")
        for character in "hallo" {
            buffer.replace(buffer.length..<buffer.length, with: String(character))
        }
        XCTAssertEqual(buffer.text, "hallo")
        buffer.undo()
        XCTAssertEqual(buffer.text, "", "aaneengesloten typen hoort één undo-stap te zijn")
    }

    func testApplyBatchAdjustsOffsets() {
        let buffer = TextBuffer(text: "aa bb cc")
        let edits = [
            TextEdit(range: 0..<2, replacement: "XXXX"),
            TextEdit(range: 3..<5, replacement: "Y"),
            TextEdit(range: 6..<8, replacement: "ZZZ")
        ]
        buffer.applyBatch(edits)
        XCTAssertEqual(buffer.text, "XXXX Y ZZZ")

        buffer.undo()
        XCTAssertEqual(buffer.text, "aa bb cc", "een batch is één undo-stap")
    }

    func testLineHelpers() {
        let buffer = TextBuffer(text: "een\ntwee\ndrie")
        XCTAssertEqual(buffer.lineCount, 3)
        XCTAssertEqual(buffer.line(1), "twee")
        XCTAssertEqual(buffer.lineSpan(covering: 5..<10), 4..<13)
    }

    func testResetClearsUndoStack() {
        let buffer = TextBuffer(text: "oud")
        buffer.replace(0..<3, with: "nieuw")
        buffer.reset(to: "vers")
        XCTAssertEqual(buffer.text, "vers")
        XCTAssertFalse(buffer.canUndo)
    }
}
