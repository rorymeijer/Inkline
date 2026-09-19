import AppKit
import InklineCore
import InklineSyntax

/// The editing surface.
///
/// `NSTextView` already gives us Retina text, VoiceOver, the system services
/// menu, dictation, emoji input and — crucially — Option-drag rectangular
/// selection. What it does not give us is multiple carets, auto-indent that
/// knows the language, indent guides or macro recording, so those live here.
final class InklineTextView: NSTextView {

    // MARK: Configuration

    var style: ThemeStyle = ThemeStyle(theme: .builtInLight, fontName: "SF Mono", fontSize: 13) {
        didSet { applyStyle() }
    }

    var settings: EditorSettings = .default {
        didSet { applySettings() }
    }

    var language: LanguageDefinition = .plainText
    var indentation: IndentationSettings = .default {
        didSet { indentEngine = IndentationEngine(settings: indentation, rules: language.indentationRules) }
    }

    /// Ranges the find bar wants highlighted, plus the one the caret is on.
    var findHighlightRanges: [NSRange] = [] { didSet { needsDisplay = true } }
    var currentFindRange: NSRange? { didSet { needsDisplay = true } }

    /// Extra carets for multi-cursor editing (the primary caret stays in
    /// `selectedRange`).
    private(set) var additionalCarets: [Int] = []

    /// OVR in the status bar: typing replaces the character under the caret.
    var isOverwriteMode = false

    /// Called for every user action that a macro should remember.
    var onRecordMacroAction: ((MacroAction) -> Void)?
    var onSelectionChange: (() -> Void)?
    var onWordCompletionRequested: ((String) -> [String])?

    private var indentEngine = IndentationEngine(settings: .default, rules: .curlyBraces)
    private var bracketMatchRanges: [NSRange] = []

    /// How much text around the caret the bracket matcher looks at. Matching
    /// across a whole 100 MB document on every caret move would be absurd; a
    /// window of this size covers any realistic block.
    private static let bracketMatchWindow = 20_000

    // MARK: Setup

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonSetup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonSetup()
    }

    private func commonSetup() {
        isRichText = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isIncrementalSearchingEnabled = true
        allowsUndo = true
        usesFindBar = false                 // Inkline has its own find bar
        smartInsertDeleteEnabled = false
        isAutomaticLinkDetectionEnabled = false
        textContainerInset = NSSize(width: 4, height: 6)
        setAccessibilityLabel(NSLocalizedString("Teksteditor", comment: "VoiceOver-label van het tekstveld"))
        applyStyle()
    }

    private func applyStyle() {
        font = style.font
        textColor = style.foregroundColor
        backgroundColor = style.backgroundColor
        insertionPointColor = style.caretColor
        selectedTextAttributes = [.backgroundColor: style.selectionColor]
        appearance = style.appearance
        needsDisplay = true
    }

    private func applySettings() {
        isEditable = true
        let wraps = settings.wrapsLines
        if let container = textContainer, let scrollView = enclosingScrollView {
            container.widthTracksTextView = wraps
            container.containerSize = NSSize(width: wraps ? scrollView.contentSize.width : .greatestFiniteMagnitude,
                                             height: .greatestFiniteMagnitude)
            isHorizontallyResizable = !wraps
            maxSize = NSSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            if wraps { frame.size.width = scrollView.contentSize.width }
        }
        needsDisplay = true
    }

    // MARK: Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        if settings.highlightsCurrentLine { drawCurrentLineHighlight() }
        drawFindHighlights()
        drawBracketMatches()
        if settings.showsIndentGuides { drawIndentGuides(in: rect) }
        if settings.showsPageGuide { drawPageGuide(in: rect) }
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
        guard !additionalCarets.isEmpty, let layoutManager, let container = textContainer else { return }
        for caret in additionalCarets {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: caret, length: 0),
                                                      actualCharacterRange: nil)
            var caretRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            caretRect.origin.x += textContainerInset.width
            caretRect.origin.y += textContainerInset.height
            caretRect.size.width = 1
            if flag { color.setFill() } else { backgroundColor.setFill() }
            caretRect.fill()
        }
    }

    private func drawCurrentLineHighlight() {
        guard selectedRanges.count == 1, selectedRange().length == 0, let container = textContainer,
              let layoutManager else { return }
        let text = string as NSString
        guard text.length > 0 else { return }
        let lineRange = text.lineRange(for: NSRange(location: min(selectedRange().location, text.length - 1), length: 0))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        rect.origin.x = 0
        rect.size.width = bounds.width
        rect.origin.y += textContainerInset.height
        style.currentLineColor.setFill()
        rect.fill()
    }

    private func drawFindHighlights() {
        guard !findHighlightRanges.isEmpty, let layoutManager, let container = textContainer else { return }
        for range in findHighlightRanges {
            let isCurrent = range == currentFindRange
            (isCurrent ? style.currentFindHighlightColor : style.findHighlightColor).setFill()
            enumerateRects(for: range, layoutManager: layoutManager, container: container) { rect in
                rect.insetBy(dx: -1, dy: 0).fill()
            }
        }
    }

    private func drawBracketMatches() {
        guard settings.highlightsMatchingBracket, !bracketMatchRanges.isEmpty,
              let layoutManager, let container = textContainer else { return }
        style.bracketMatchColor.setFill()
        for range in bracketMatchRanges {
            enumerateRects(for: range, layoutManager: layoutManager, container: container) { $0.fill() }
        }
    }

    private func enumerateRects(for range: NSRange,
                                layoutManager: NSLayoutManager,
                                container: NSTextContainer,
                                body: (NSRect) -> Void) {
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange,
                                              withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                              in: container) { rect, _ in
            var offsetRect = rect
            offsetRect.origin.x += self.textContainerInset.width
            offsetRect.origin.y += self.textContainerInset.height
            body(offsetRect)
        }
    }

    private func drawIndentGuides(in rect: NSRect) {
        guard let layoutManager, let container = textContainer else { return }
        let text = string as NSString
        guard text.length > 0 else { return }

        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: rect, in: container)
        let visibleCharacters = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        let spaceWidth = " ".size(withAttributes: [.font: style.font]).width
        let step = spaceWidth * CGFloat(indentation.indentWidth)
        guard step > 1 else { return }

        style.indentGuideColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1

        text.enumerateSubstrings(in: visibleCharacters, options: [.byLines]) { line, lineRange, _, _ in
            guard let line, !line.isEmpty else { return }
            let leading = IndentationEngine.leadingWhitespace(of: line)
            let width = self.indentation.visualWidth(of: leading)
            guard width >= self.indentation.indentWidth else { return }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            lineRect.origin.y += self.textContainerInset.height

            var level = self.indentation.indentWidth
            while level <= width {
                let x = self.textContainerInset.width + spaceWidth * CGFloat(level)
                path.move(to: NSPoint(x: x.rounded() + 0.5, y: lineRect.minY))
                path.line(to: NSPoint(x: x.rounded() + 0.5, y: lineRect.maxY))
                level += self.indentation.indentWidth
            }
        }
        path.stroke()
    }

    private func drawPageGuide(in rect: NSRect) {
        let width = " ".size(withAttributes: [.font: style.font]).width * CGFloat(settings.pageGuideColumn)
        let x = textContainerInset.width + width
        style.pageGuideColor.setFill()
        NSRect(x: x, y: rect.minY, width: 1, height: rect.height).fill()
    }

    // MARK: Selection

    override func setSelectedRanges(_ ranges: [NSValue],
                                    affinity: NSSelectionAffinity,
                                    stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        guard !stillSelectingFlag else { return }
        updateBracketMatch()
        onSelectionChange?()
        needsDisplay = true
    }

    private func updateBracketMatch() {
        bracketMatchRanges = []
        defer { needsDisplay = true }
        guard settings.highlightsMatchingBracket, selectedRange().length == 0 else { return }

        let characters = string as NSString
        guard characters.length > 0 else { return }

        // Work on a window around the caret and translate the result back.
        let caret = min(selectedRange().location, characters.length)
        let windowStart = max(0, caret - Self.bracketMatchWindow)
        let windowEnd = min(characters.length, caret + Self.bracketMatchWindow)
        let window = characters.substring(with: NSRange(location: windowStart,
                                                        length: windowEnd - windowStart))

        let table = PieceTable(window)
        guard let match = BracketMatcher.match(at: caret - windowStart,
                                               in: table,
                                               pairs: language.bracketPairs.isEmpty
                                                   ? BracketMatcher.defaultPairs
                                                   : language.bracketPairs) else { return }
        bracketMatchRanges = [NSRange(location: windowStart + match.origin, length: 1),
                              NSRange(location: windowStart + match.counterpart, length: 1)]
    }

    // MARK: Multiple carets

    override func mouseDown(with event: NSEvent) {
        // Cmd-click adds a caret, the way every modern editor does it.
        if event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift) {
            let point = convert(event.locationInWindow, from: nil)
            addCaret(at: characterIndexForInsertion(at: point))
            return
        }
        clearAdditionalCarets()
        super.mouseDown(with: event)
    }

    func addCaret(at offset: Int) {
        let clamped = max(0, min(offset, (string as NSString).length))
        guard clamped != selectedRange().location, !additionalCarets.contains(clamped) else { return }
        additionalCarets.append(clamped)
        additionalCarets.sort()
        needsDisplay = true
    }

    func clearAdditionalCarets() {
        guard !additionalCarets.isEmpty else { return }
        additionalCarets.removeAll()
        needsDisplay = true
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""

        if isOverwriteMode, additionalCarets.isEmpty, selectedRange().length == 0, text != "\n" {
            // Overwrite: swallow the character to the right, unless we are at
            // the end of a line, where OVR behaves like INS everywhere.
            let characters = string as NSString
            let location = selectedRange().location
            if location < characters.length,
               characters.substring(with: NSRange(location: location, length: 1)) != "\n" {
                setSelectedRange(NSRange(location: location, length: 1))
            }
        }

        if !additionalCarets.isEmpty {
            insertAtAllCarets(text)
            onRecordMacroAction?(.insertText(text))
            return
        }

        if settings.autoClosesBrackets || settings.autoClosesQuotes,
           let closing = closingPair(for: text),
           selectedRange().length == 0 {
            super.insertText(text + closing, replacementRange: replacementRange)
            setSelectedRange(NSRange(location: selectedRange().location - (closing as NSString).length, length: 0))
            onRecordMacroAction?(.insertText(text))
            return
        }

        if let skipped = skipOverClosingCharacter(text) {
            setSelectedRange(NSRange(location: skipped, length: 0))
            onRecordMacroAction?(.insertText(text))
            return
        }

        super.insertText(insertString, replacementRange: replacementRange)
        onRecordMacroAction?(.insertText(text))
        reindentCurrentLineIfNeeded(after: text)
    }

    /// Applies one insertion at every caret, back to front so earlier offsets
    /// stay valid, as a single undo group.
    private func insertAtAllCarets(_ text: String) {
        var offsets = additionalCarets
        offsets.append(selectedRange().location)
        offsets.sort()

        undoManager?.beginUndoGrouping()
        for offset in offsets.reversed() {
            let range = NSRange(location: offset, length: 0)
            if shouldChangeText(in: range, replacementString: text) {
                textStorage?.replaceCharacters(in: range, with: text)
                didChangeText()
            }
        }
        undoManager?.endUndoGrouping()

        let inserted = (text as NSString).length
        var updated = [Int]()
        for (index, offset) in offsets.enumerated() {
            updated.append(offset + inserted * (index + 1))
        }
        if let last = updated.last {
            additionalCarets = Array(updated.dropLast())
            setSelectedRange(NSRange(location: last, length: 0))
        }
        needsDisplay = true
    }

    private func closingPair(for text: String) -> String? {
        guard text.count == 1 else { return nil }
        if settings.autoClosesQuotes, text == "\"" || text == "'" || text == "`" {
            return text
        }
        guard settings.autoClosesBrackets else { return nil }
        return language.autoClosePairs.first { $0.open == text }?.close
    }

    /// Typing the closing half of a pair right before it just moves the caret —
    /// but only when Inkline put it there, i.e. when auto-closing is on.
    private func skipOverClosingCharacter(_ text: String) -> Int? {
        guard settings.autoClosesBrackets || settings.autoClosesQuotes else { return nil }
        guard text.count == 1, selectedRange().length == 0 else { return nil }
        let characters = string as NSString
        let location = selectedRange().location
        guard location < characters.length else { return nil }
        let next = characters.substring(with: NSRange(location: location, length: 1))
        guard next == text else { return nil }
        let isPairCloser = language.autoClosePairs.contains { $0.close == text }
            || text == "\"" || text == "'" || text == "`"
        return isPairCloser ? location + 1 : nil
    }

    // MARK: Indentation

    override func insertNewline(_ sender: Any?) {
        guard settings.autoIndents else {
            super.insertNewline(sender)
            onRecordMacroAction?(.newline)
            return
        }

        let text = string as NSString
        let location = selectedRange().location
        let lineRange = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
        let currentLine = text.substring(with: NSRange(location: lineRange.location,
                                                       length: max(0, min(location, text.length) - lineRange.location)))
        let indent = indentEngine.indentation(after: currentLine)

        let before: Character? = location > 0
            ? Character(text.substring(with: NSRange(location: location - 1, length: 1)))
            : nil
        let after: Character? = location < text.length
            ? Character(text.substring(with: NSRange(location: location, length: 1)))
            : nil

        if selectedRange().length == 0, indentEngine.shouldExpandBracketPair(before: before, after: after) {
            // Return between { and } opens a blank indented line and pushes the
            // closing brace down one line.
            let outerIndent = IndentationEngine.leadingWhitespace(of: currentLine)
            let insertion = "\n" + indent + "\n" + outerIndent
            super.insertText(insertion, replacementRange: selectedRange())
            setSelectedRange(NSRange(location: location + 1 + (indent as NSString).length, length: 0))
        } else {
            super.insertText("\n" + indent, replacementRange: selectedRange())
        }
        onRecordMacroAction?(.newline)
    }

    override func insertTab(_ sender: Any?) {
        if selectedRange().length > 0 {
            indentSelection()
        } else if indentation.usesTabs {
            super.insertText("\t", replacementRange: selectedRange())
        } else {
            let column = columnOfCaret()
            let spaces = indentation.indentWidth - (column % indentation.indentWidth)
            super.insertText(String(repeating: " ", count: spaces), replacementRange: selectedRange())
        }
        onRecordMacroAction?(.tab)
    }

    override func insertBacktab(_ sender: Any?) {
        outdentSelection()
        onRecordMacroAction?(.outdent)
    }

    func indentSelection() {
        transformSelectedLines { TextTransforms.indent($0, using: self.indentation.unit) }
        onRecordMacroAction?(.indent)
    }

    func outdentSelection() {
        transformSelectedLines { TextTransforms.outdent($0, indentWidth: self.indentation.indentWidth) }
    }

    /// Replaces the full lines covered by the selection with `transform`'s
    /// result, keeping the selection on the same lines afterwards.
    func transformSelectedLines(_ transform: (String) -> String) {
        let text = string as NSString
        let selection = selectedRange()
        let lineRange = text.lineRange(for: selection)
        let original = text.substring(with: lineRange)
        let replacement = transform(original)
        guard replacement != original else { return }

        if shouldChangeText(in: lineRange, replacementString: replacement) {
            textStorage?.replaceCharacters(in: lineRange, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: (replacement as NSString).length))
        }
    }

    /// Replaces the selection (or the whole document when nothing is selected).
    func transformSelectionOrDocument(_ transform: (String) -> String) {
        let text = string as NSString
        let range = selectedRange().length > 0 ? selectedRange() : NSRange(location: 0, length: text.length)
        let replacement = transform(text.substring(with: range))
        guard replacement != text.substring(with: range) else { return }
        if shouldChangeText(in: range, replacementString: replacement) {
            textStorage?.replaceCharacters(in: range, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: range.location, length: (replacement as NSString).length))
        }
    }

    private func reindentCurrentLineIfNeeded(after typed: String) {
        guard settings.autoIndents,
              language.indentationRules.reindentTriggers.contains(typed) else { return }
        let text = string as NSString
        let location = selectedRange().location
        let lineRange = text.lineRange(for: NSRange(location: min(location, max(0, text.length - 1)), length: 0))
        let line = text.substring(with: lineRange)
        let previousLine: String? = lineRange.location > 0
            ? text.substring(with: text.lineRange(for: NSRange(location: lineRange.location - 1, length: 0)))
            : nil
        guard let newIndent = indentEngine.reindentation(for: line, previousLine: previousLine) else { return }

        let existing = IndentationEngine.leadingWhitespace(of: line)
        let replaceRange = NSRange(location: lineRange.location, length: (existing as NSString).length)
        guard shouldChangeText(in: replaceRange, replacementString: newIndent) else { return }
        textStorage?.replaceCharacters(in: replaceRange, with: newIndent)
        didChangeText()
        let delta = (newIndent as NSString).length - replaceRange.length
        setSelectedRange(NSRange(location: max(0, location + delta), length: 0))
    }

    private func columnOfCaret() -> Int {
        let text = string as NSString
        let location = min(selectedRange().location, text.length)
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        return location - lineRange.location
    }

    // MARK: Deleting

    override func deleteBackward(_ sender: Any?) {
        if !additionalCarets.isEmpty {
            deleteBackwardAtAllCarets()
            onRecordMacroAction?(.deleteBackward)
            return
        }
        // Backspace inside a run of indentation removes one full indent level.
        if !indentation.usesTabs, selectedRange().length == 0 {
            let text = string as NSString
            let location = selectedRange().location
            let lineRange = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
            let prefix = text.substring(with: NSRange(location: lineRange.location, length: location - lineRange.location))
            if !prefix.isEmpty, prefix.allSatisfy({ $0 == " " }) {
                let width = prefix.count
                let remove = width % indentation.indentWidth == 0 ? indentation.indentWidth : width % indentation.indentWidth
                let range = NSRange(location: location - remove, length: remove)
                if shouldChangeText(in: range, replacementString: "") {
                    textStorage?.replaceCharacters(in: range, with: "")
                    didChangeText()
                }
                onRecordMacroAction?(.deleteBackward)
                return
            }
        }
        super.deleteBackward(sender)
        onRecordMacroAction?(.deleteBackward)
    }

    private func deleteBackwardAtAllCarets() {
        var offsets = additionalCarets
        offsets.append(selectedRange().location)
        offsets.sort()

        undoManager?.beginUndoGrouping()
        for offset in offsets.reversed() where offset > 0 {
            let range = NSRange(location: offset - 1, length: 1)
            if shouldChangeText(in: range, replacementString: "") {
                textStorage?.replaceCharacters(in: range, with: "")
                didChangeText()
            }
        }
        undoManager?.endUndoGrouping()

        var updated = [Int]()
        for (index, offset) in offsets.enumerated() where offset > 0 {
            updated.append(offset - 1 - index)
        }
        if let last = updated.last {
            additionalCarets = Array(updated.dropLast())
            setSelectedRange(NSRange(location: max(0, last), length: 0))
        }
        needsDisplay = true
    }

    override func deleteForward(_ sender: Any?) {
        super.deleteForward(sender)
        onRecordMacroAction?(.deleteForward)
    }

    // MARK: Completion

    override var rangeForUserCompletion: NSRange {
        guard settings.completionEnabled else { return NSRange(location: NSNotFound, length: 0) }
        let text = string
        guard let partial = WordIndex.partialWord(in: text, before: selectedRange().location),
              partial.word.count >= settings.completionMinimumPrefixLength else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: partial.range.lowerBound, length: partial.range.count)
    }

    override func completions(forPartialWordRange charRange: NSRange,
                              indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String]? {
        let prefix = (string as NSString).substring(with: charRange)
        let candidates = onWordCompletionRequested?(prefix) ?? []
        index?.pointee = candidates.isEmpty ? -1 : 0
        return candidates.isEmpty ? nil : candidates
    }

    // MARK: Accessibility

    override func accessibilityRole() -> NSAccessibility.Role? { .textArea }

    override func accessibilityHelp() -> String? {
        NSLocalizedString("Bewerk de tekst van het actieve document.",
                          comment: "VoiceOver-hulp voor de teksteditor")
    }
}
