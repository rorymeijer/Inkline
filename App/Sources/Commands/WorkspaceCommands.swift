import AppKit
import InklineCore
import InklineSyntax

/// Every text command in the Edit menu, in one place, expressed as operations
/// on the active text view. They all go through `InklineTextView`'s
/// `transform…` helpers so that undo, macro recording and plugins see exactly
/// the same edits the user would make by hand.
@MainActor
extension WorkspaceModel {

    // MARK: Text transforms

    func applyToSelection(_ transform: @escaping (String) -> String) {
        guard let textView = activeTextView else { return }
        textView.transformSelectionOrDocument(transform)
    }

    func applyToSelectedLines(_ transform: @escaping (String) -> String) {
        guard let textView = activeTextView else { return }
        textView.transformSelectedLines(transform)
    }

    func uppercaseSelection() { applyToSelection(TextTransforms.uppercased) }
    func lowercaseSelection() { applyToSelection(TextTransforms.lowercased) }
    func titleCaseSelection() { applyToSelection(TextTransforms.titleCased) }
    func sentenceCaseSelection() { applyToSelection(TextTransforms.sentenceCased) }
    func invertCaseSelection() { applyToSelection(TextTransforms.invertedCase) }

    func sortLines(ascending: Bool, numeric: Bool = false, removingDuplicates: Bool = false) {
        applyToSelectedLines { text in
            TextTransforms.sortLines(text, options: .init(ascending: ascending,
                                                          numeric: numeric,
                                                          removesDuplicates: removingDuplicates))
        }
    }

    func reverseLines() { applyToSelectedLines(TextTransforms.reversedLines) }
    func removeDuplicateLines() { applyToSelectedLines { TextTransforms.removeDuplicateLines($0) } }
    func removeEmptyLines() { applyToSelectedLines { TextTransforms.removeEmptyLines($0) } }
    func trimTrailingWhitespace() { applyToSelectedLines(TextTransforms.trimTrailingWhitespace) }
    func joinLines() { applyToSelectedLines { TextTransforms.joinLines($0) } }

    func splitLines(at column: Int) {
        applyToSelectedLines { TextTransforms.splitLines($0, at: column) }
    }

    func convertTabsToSpaces() {
        guard let indentation = activeDocument?.document.indentation else { return }
        applyToSelectedLines { TextTransforms.tabsToSpaces($0, tabWidth: indentation.tabWidth) }
    }

    func convertSpacesToTabs() {
        guard let indentation = activeDocument?.document.indentation else { return }
        applyToSelectedLines { TextTransforms.spacesToTabs($0, tabWidth: indentation.tabWidth) }
    }

    func base64EncodeSelection() { applyToSelection(TextTransforms.base64Encoded) }
    func base64DecodeSelection() {
        applyToSelection { TextTransforms.base64Decoded($0) ?? $0 }
    }
    func urlEncodeSelection() { applyToSelection(TextTransforms.urlEncoded) }
    func urlDecodeSelection() { applyToSelection { TextTransforms.urlDecoded($0) ?? $0 } }
    func htmlEncodeSelection() { applyToSelection(TextTransforms.htmlEncoded) }
    func htmlDecodeSelection() { applyToSelection(TextTransforms.htmlDecoded) }

    func indentSelection() { activeTextView?.indentSelection() }
    func outdentSelection() { activeTextView?.outdentSelection() }

    func duplicateSelection() {
        guard let textView = activeTextView else { return }
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        if selection.length == 0 {
            let lineRange = text.lineRange(for: selection)
            var line = text.substring(with: lineRange)
            if !line.hasSuffix("\n") { line += "\n" }
            insert(line, at: lineRange.location, in: textView)
        } else {
            let selected = text.substring(with: selection)
            insert(selected, at: NSMaxRange(selection), in: textView)
        }
    }

    func deleteCurrentLine() {
        guard let textView = activeTextView else { return }
        let text = textView.string as NSString
        let lineRange = text.lineRange(for: textView.selectedRange())
        guard textView.shouldChangeText(in: lineRange, replacementString: "") else { return }
        textView.textStorage?.replaceCharacters(in: lineRange, with: "")
        textView.didChangeText()
    }

    func moveLines(up: Bool) {
        guard let textView = activeTextView, let document = activeDocument else { return }
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let lineRange = text.lineRange(for: selection)
        let firstLine = document.lineNumber(at: lineRange.location)
        let lastLine = document.lineNumber(at: max(lineRange.location, NSMaxRange(lineRange) - 1))

        if up {
            guard firstLine > 0 else { return }
            let previous = document.lineIndex.lineRange(firstLine - 1)
            let combined = NSRange(location: previous.lowerBound,
                                   length: NSMaxRange(lineRange) - previous.lowerBound)
            let block = text.substring(with: lineRange)
            let previousText = text.substring(with: NSRange(location: previous.lowerBound,
                                                            length: previous.count))
            let replacement = normalizedBlock(block) + previousText
            replace(combined, with: replacement, in: textView)
            textView.setSelectedRange(NSRange(location: previous.lowerBound, length: lineRange.length))
        } else {
            guard lastLine + 1 < document.lineIndex.lineCount else { return }
            let next = document.lineIndex.lineRange(lastLine + 1)
            let combined = NSRange(location: lineRange.location,
                                   length: next.upperBound - lineRange.location)
            let block = text.substring(with: lineRange)
            let nextText = text.substring(with: NSRange(location: next.lowerBound, length: next.count))
            let replacement = normalizedBlock(nextText) + block
            replace(combined, with: replacement, in: textView)
            textView.setSelectedRange(NSRange(location: lineRange.location + (normalizedBlock(nextText) as NSString).length,
                                              length: lineRange.length))
        }
    }

    private func normalizedBlock(_ block: String) -> String {
        block.hasSuffix("\n") ? block : block + "\n"
    }

    func toggleLineComment() {
        guard let document = activeDocument,
              let token = document.language.comments.line else { return }
        applyToSelectedLines { text in
            let lines = TextTransforms.splitIntoLines(text)
            let allCommented = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix(token) }
            let transformed = lines.map { line -> String in
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
                if allCommented {
                    guard let range = line.range(of: token) else { return line }
                    var result = line
                    result.removeSubrange(range)
                    // Also drop the single space we added when commenting.
                    let insertionIndex = range.lowerBound
                    if insertionIndex < result.endIndex, result[insertionIndex] == " " {
                        result.remove(at: insertionIndex)
                    }
                    return result
                }
                let indent = IndentationEngine.leadingWhitespace(of: line)
                return indent + token + " " + line.dropFirst(indent.count)
            }
            return transformed.joined(separator: "\n") + (text.hasSuffix("\n") ? "\n" : "")
        }
    }

    func toggleBlockComment() {
        guard let document = activeDocument,
              let start = document.language.comments.blockStart,
              let end = document.language.comments.blockEnd else { return }
        applyToSelection { text in
            if text.hasPrefix(start) && text.hasSuffix(end) {
                return String(text.dropFirst(start.count).dropLast(end.count))
            }
            return start + text + end
        }
    }

    private func insert(_ text: String, at location: Int, in textView: InklineTextView) {
        let range = NSRange(location: location, length: 0)
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: text)
        textView.didChangeText()
    }

    private func replace(_ range: NSRange, with text: String, in textView: InklineTextView) {
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: text)
        textView.didChangeText()
    }

    // MARK: Column editor

    func insertColumnText(_ text: String) {
        applyColumnInsertion(.text(text))
    }

    func insertColumnNumbers(start: Int, increment: Int, format: ColumnEditor.NumberFormat, minimumDigits: Int) {
        applyColumnInsertion(.numbers(start: start, increment: increment,
                                      format: format, minimumDigits: minimumDigits))
    }

    private func applyColumnInsertion(_ insertion: ColumnEditor.Insertion) {
        guard let textView = activeTextView, let document = activeDocument else { return }
        let table = document.lineIndex
        let selection = textView.selectedRange()
        let firstLine = document.lineNumber(at: selection.location)
        let lastLine = document.lineNumber(at: NSMaxRange(selection))
        let startColumn = selection.location - table.lineContentRange(firstLine).lowerBound
        let endColumn = NSMaxRange(selection) - table.lineContentRange(lastLine).lowerBound

        let block = ColumnEditor.Block(firstLine: firstLine,
                                       lastLine: lastLine,
                                       startColumn: startColumn,
                                       endColumn: firstLine == lastLine ? endColumn : startColumn)
        let edits = ColumnEditor.edits(for: insertion, block: block, in: table)
        document.applyExternalEdits(edits)
    }

    // MARK: Macros

    func startMacroRecording() {
        environment.macroRecorder.start()
    }

    func stopMacroRecording() {
        guard let macro = environment.macroRecorder.stop() else { return }
        environment.macroStore.add(macro)
        NotificationCenter.default.post(name: .inklineMacrosChanged, object: nil)
    }

    func playLastMacro(repeatMode: MacroRepeatMode = .once) {
        guard let macro = environment.macroStore.macros.last else { return }
        playMacro(macro, repeatMode: repeatMode)
    }

    func playMacro(_ macro: Macro, repeatMode: MacroRepeatMode = .once) {
        guard let textView = activeTextView else { return }
        let target = TextViewMacroTarget(textView: textView, workspace: self)
        textView.undoManager?.beginUndoGrouping()
        do {
            try MacroPlayer.play(macro, on: target, repeatMode: repeatMode)
        } catch {
            alert = WorkspaceAlert(title: NSLocalizedString("Macro afspelen mislukt", comment: "Foutmelding"),
                                   message: error.localizedDescription)
        }
        textView.undoManager?.endUndoGrouping()
    }

    // MARK: Compare

    func compareActiveDocumentWithFile() {
        guard let document = activeDocument else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = NSLocalizedString("Kies het bestand om mee te vergelijken",
                                          comment: "Bericht in het open-venster")
        guard panel.runModal() == .OK, let url = panel.url,
              let other = try? FileLoader.load(contentsOf: url) else { return }

        let model = DiffModel()
        model.compare(leftTitle: document.displayName, leftText: document.text,
                      rightTitle: url.lastPathComponent, rightText: other.text)
        DiffWindowController.show(model: model, environment: environment)
    }
}

/// Replays a macro against the live text view.
@MainActor
final class TextViewMacroTarget: MacroExecutionTarget {

    private let textView: InklineTextView
    private unowned let workspace: WorkspaceModel

    init(textView: InklineTextView, workspace: WorkspaceModel) {
        self.textView = textView
        self.workspace = workspace
    }

    var caretOffset: Int { textView.selectedRange().location }
    var documentLength: Int { (textView.string as NSString).length }

    func perform(_ action: MacroAction) throws {
        switch action {
        case let .insertText(text):
            textView.insertText(text, replacementRange: textView.selectedRange())
        case .newline:
            textView.insertNewline(nil)
        case .tab:
            textView.insertTab(nil)
        case .deleteBackward:
            textView.deleteBackward(nil)
        case .deleteForward:
            textView.deleteForward(nil)
        case .deleteWordBackward:
            textView.deleteWordBackward(nil)
        case .deleteWordForward:
            textView.deleteWordForward(nil)
        case .deleteLine:
            workspace.deleteCurrentLine()
        case let .move(movement, extending):
            perform(movement: movement, extending: extending)
        case .selectAll:
            textView.selectAll(nil)
        case .selectLine:
            let range = (textView.string as NSString).lineRange(for: textView.selectedRange())
            textView.setSelectedRange(range)
        case .indent:
            textView.indentSelection()
        case .outdent:
            textView.outdentSelection()
        case let .find(query, direction):
            workspace.find.query = query
            guard workspace.find.findNext(direction: direction) else {
                throw MacroPlaybackError.noMatch
            }
        case let .replaceSelection(text):
            textView.insertText(text, replacementRange: textView.selectedRange())
        case let .replaceAll(query, replacement):
            workspace.find.query = query
            workspace.find.replacement = replacement
            workspace.find.replaceAllInActiveDocument()
        case let .goToLine(line):
            workspace.goToLine(line)
        case let .command(identifier):
            let context = CommandContext(document: workspace.activeDocument?.document)
            guard try workspace.environment.commandRegistry.perform(CommandIdentifier(identifier),
                                                                    context: context) else {
                throw MacroPlaybackError.unsupportedAction(identifier)
            }
        }
    }

    private func perform(movement: MacroAction.Movement, extending: Bool) {
        switch (movement, extending) {
        case (.left, false): textView.moveLeft(nil)
        case (.left, true): textView.moveLeftAndModifySelection(nil)
        case (.right, false): textView.moveRight(nil)
        case (.right, true): textView.moveRightAndModifySelection(nil)
        case (.up, false): textView.moveUp(nil)
        case (.up, true): textView.moveUpAndModifySelection(nil)
        case (.down, false): textView.moveDown(nil)
        case (.down, true): textView.moveDownAndModifySelection(nil)
        case (.wordLeft, false): textView.moveWordLeft(nil)
        case (.wordLeft, true): textView.moveWordLeftAndModifySelection(nil)
        case (.wordRight, false): textView.moveWordRight(nil)
        case (.wordRight, true): textView.moveWordRightAndModifySelection(nil)
        case (.lineStart, false): textView.moveToBeginningOfLine(nil)
        case (.lineStart, true): textView.moveToBeginningOfLineAndModifySelection(nil)
        case (.lineEnd, false): textView.moveToEndOfLine(nil)
        case (.lineEnd, true): textView.moveToEndOfLineAndModifySelection(nil)
        case (.documentStart, false): textView.moveToBeginningOfDocument(nil)
        case (.documentStart, true): textView.moveToBeginningOfDocumentAndModifySelection(nil)
        case (.documentEnd, false): textView.moveToEndOfDocument(nil)
        case (.documentEnd, true): textView.moveToEndOfDocumentAndModifySelection(nil)
        case (.pageUp, _): textView.pageUp(nil)
        case (.pageDown, _): textView.pageDown(nil)
        }
    }
}
