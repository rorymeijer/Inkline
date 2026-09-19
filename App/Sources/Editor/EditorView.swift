import AppKit
import SwiftUI
import InklineCore
import InklineSyntax

/// Wraps the AppKit editing stack (`NSScrollView` → `NSTextView` → the shared
/// `InklineTextStorage`) for SwiftUI.
///
/// Every pane builds its own layout manager and text container around the
/// document's *shared* text storage, which is how the same file can be open in
/// two panes and stay in sync for free — TextKit does the work.
struct EditorView: NSViewRepresentable {

    @ObservedObject var document: EditorDocument
    @ObservedObject var workspace: WorkspaceModel
    let environment: AppEnvironment
    let paneID: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, workspace: workspace, environment: environment, paneID: paneID)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true      // the reason 100 MB files open instantly
        document.textStorage.addLayoutManager(layoutManager)

        let container = NSTextContainer(containerSize: NSSize(width: .greatestFiniteMagnitude,
                                                              height: .greatestFiniteMagnitude))
        container.widthTracksTextView = environment.settings.wrapsLines
        layoutManager.addTextContainer(container)

        let textView = InklineTextView(frame: .zero, textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = !environment.settings.wrapsLines
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.style = environment.style
        textView.settings = environment.settings
        textView.language = document.language
        textView.indentation = document.document.indentation
        textView.setLineIndexProvider { [weak document] offset in
            document?.lineNumber(at: offset) ?? 0
        }
        textView.onSelectionChange = { [weak coordinator = context.coordinator] in
            coordinator?.selectionDidChange()
        }
        textView.onRecordMacroAction = { action in
            environment.macroRecorder.record(action)
        }
        textView.onWordCompletionRequested = { [weak document] prefix in
            document?.completions(for: prefix) ?? []
        }
        layoutManager.delegate = context.coordinator

        scrollView.documentView = textView

        let ruler = LineNumberRulerView(textView: textView, style: environment.style)
        ruler.lineNumberProvider = { [weak document] offset in document?.lineNumber(at: offset) ?? 0 }
        ruler.onToggleBookmark = { [weak document] line in document?.toggleBookmark(atLine: line) }
        ruler.onToggleFold = { [weak document] line in document?.toggleFold(atLine: line) }
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = environment.settings.showsLineNumbers

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.scrollView = scrollView
        context.coordinator.observeScrolling()
        document.textView = textView

        // Restore the caret and scroll position from the session.
        let selection = document.selection.clamped(to: document.length)
        textView.setSelectedRange(NSRange(location: selection.range.lowerBound, length: selection.range.count))
        DispatchQueue.main.async {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: document.scrollOffset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            document.textStorage.applyHighlighting(in: textView.visibleCharacterRange())
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? InklineTextView else { return }
        textView.style = environment.style
        textView.settings = environment.settings
        textView.language = document.language
        textView.indentation = document.document.indentation
        document.textStorage.style = environment.style
        document.textStorage.wrapsLines = environment.settings.wrapsLines

        if let ruler = scrollView.verticalRulerView as? LineNumberRulerView {
            ruler.style = environment.style
            ruler.bookmarkedLines = Set(document.document.bookmarks.sorted)
            ruler.foldableLines = Set(document.foldingState.regions.map(\.startLine))
            ruler.collapsedLines = document.foldingState.collapsedStartLines
            ruler.showsFoldingRibbon = environment.settings.showsFoldingRibbon
            ruler.updateThickness(forLineCount: document.lineIndex.lineCount)
        }
        scrollView.rulersVisible = environment.settings.showsLineNumbers
        applyFolding(to: textView, coordinator: context.coordinator)

        if workspace.activePane.id == paneID,
           workspace.activePane.activeDocumentID == document.id,
           scrollView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                scrollView.window?.makeFirstResponder(textView)
                workspace.activeTextView = textView
            }
        }
    }

    /// Folding hides the glyphs of collapsed ranges: the layout manager asks
    /// the delegate to generate glyphs, and the delegate marks everything
    /// inside a collapsed region as `.null`. TextKit then lays the document out
    /// as if those lines were not there, without touching the text itself.
    private func applyFolding(to textView: InklineTextView, coordinator: Coordinator) {
        let table = document.lineIndex
        guard table.count == document.length else { return }

        var ranges = [NSRange]()
        for range in document.foldingState.hiddenLines {
            guard range.lowerBound < table.lineCount else { continue }
            let start = table.lineRange(range.lowerBound).lowerBound
            let endLine = min(range.upperBound, table.lineCount - 1)
            let end = table.lineRange(endLine).upperBound
            guard end > start else { continue }
            ranges.append(NSRange(location: start, length: end - start))
        }
        coordinator.setHiddenRanges(ranges, in: textView)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {

        let document: EditorDocument
        let workspace: WorkspaceModel
        let environment: AppEnvironment
        let paneID: UUID

        weak var textView: InklineTextView?
        weak var ruler: LineNumberRulerView?
        weak var scrollView: NSScrollView?

        /// Character ranges hidden by code folding.
        private(set) var hiddenRanges: [NSRange] = []

        init(document: EditorDocument, workspace: WorkspaceModel, environment: AppEnvironment, paneID: UUID) {
            self.document = document
            self.workspace = workspace
            self.environment = environment
            self.paneID = paneID
        }

        func observeScrolling() {
            guard let scrollView else { return }
            workspace.register(scrollView: scrollView, for: paneID)
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(boundsDidChange),
                                                   name: NSView.boundsDidChangeNotification,
                                                   object: scrollView.contentView)
        }

        @objc private func boundsDidChange() {
            guard let scrollView, let textView else { return }
            document.scrollOffset = Double(scrollView.contentView.bounds.origin.y)
            document.textStorage.applyHighlighting(in: textView.visibleCharacterRange())
            ruler?.needsDisplay = true

            if workspace.synchronizedScrolling {
                workspace.synchronizeScroll(from: paneID, to: scrollView.contentView.bounds.origin)
            }
        }

        func selectionDidChange() {
            guard let textView else { return }
            let range = textView.selectedRange()
            document.selection = TextSelection(anchor: range.location, head: NSMaxRange(range))
            document.selectedRangeCount = max(1, textView.selectedRanges.count + textView.additionalCarets.count)
            document.selectedCharacterCount = textView.selectedRanges
                .compactMap { ($0 as? NSRange)?.length }
                .reduce(0, +)
            ruler?.needsDisplay = true
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            document.textStorage.applyHighlighting(in: textView.visibleCharacterRange())
            ruler?.updateThickness(forLineCount: document.lineIndex.lineCount)
            ruler?.needsDisplay = true
            workspace.scheduleAutosave()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            selectionDidChange()
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            !document.document.isReadOnly
        }

        func textDidBeginEditing(_ notification: Notification) {
            workspace.activeTextView = textView
            workspace.activePaneID = paneID
        }

        // MARK: Folding

        func setHiddenRanges(_ ranges: [NSRange], in textView: InklineTextView) {
            let sorted = ranges.sorted { $0.location < $1.location }
            guard sorted != hiddenRanges else { return }
            hiddenRanges = sorted
            guard let layoutManager = textView.layoutManager else { return }
            let length = (textView.string as NSString).length
            layoutManager.invalidateGlyphs(forCharacterRange: NSRange(location: 0, length: length),
                                           changeInLength: 0,
                                           actualCharacterRange: nil)
            layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: length),
                                           actualCharacterRange: nil)
        }

        private func isHidden(_ characterIndex: Int) -> Bool {
            for range in hiddenRanges {
                if characterIndex < range.location { return false }        // sorted: no later range can match
                if NSLocationInRange(characterIndex, range) { return true }
            }
            return false
        }

        // MARK: NSLayoutManagerDelegate

        func layoutManager(_ layoutManager: NSLayoutManager,
                           shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                           properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                           characterIndexes charIndexes: UnsafePointer<Int>,
                           font aFont: NSFont,
                           forGlyphRange glyphRange: NSRange) -> Int {
            guard !hiddenRanges.isEmpty else { return 0 }

            var generatedGlyphs = [CGGlyph]()
            var properties = [NSLayoutManager.GlyphProperty]()
            var indexes = [Int]()
            generatedGlyphs.reserveCapacity(glyphRange.length)
            properties.reserveCapacity(glyphRange.length)
            indexes.reserveCapacity(glyphRange.length)

            for offset in 0..<glyphRange.length {
                generatedGlyphs.append(glyphs[offset])
                indexes.append(charIndexes[offset])
                properties.append(isHidden(charIndexes[offset]) ? .null : props[offset])
            }

            layoutManager.setGlyphs(&generatedGlyphs,
                                    properties: &properties,
                                    characterIndexes: &indexes,
                                    font: aFont,
                                    forGlyphRange: glyphRange)
            return glyphRange.length
        }
    }
}

extension NSTextView {
    /// The character range currently on screen, padded a little so scrolling
    /// does not reveal unhighlighted text.
    func visibleCharacterRange(padding: Int = 2_000) -> NSRange {
        guard let layoutManager, let container = textContainer,
              let scrollView = enclosingScrollView else {
            return NSRange(location: 0, length: min((string as NSString).length, 10_000))
        }
        let visibleRect = scrollView.contentView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let length = (string as NSString).length
        let location = max(0, characterRange.location - padding)
        let upper = min(length, NSMaxRange(characterRange) + padding)
        return NSRange(location: location, length: max(0, upper - location))
    }
}
