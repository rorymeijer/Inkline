import AppKit
import InklineCore

/// The gutter: line numbers, bookmark dots and fold arrows.
///
/// Drawn by hand rather than with a stack of views, because a 3-million-line
/// document must not cost three million views. Only the visible glyph range is
/// ever touched.
final class LineNumberRulerView: NSView {

    override var isFlipped: Bool { true }

    weak var scrollView: NSScrollView?
    weak var textView: NSTextView?
    var style: ThemeStyle {
        didSet { if style != oldValue { needsDisplay = true } }
    }
    private(set) var ruleThickness: CGFloat = 48

    /// Line numbers (zero-based) that carry a bookmark.
    var bookmarkedLines: Set<Int> = [] {
        didSet { if bookmarkedLines != oldValue { needsDisplay = true } }
    }
    /// Lines that start a foldable region, and which of them are collapsed.
    var foldableLines: Set<Int> = [] {
        didSet { if foldableLines != oldValue { needsDisplay = true } }
    }
    var collapsedLines: Set<Int> = [] {
        didSet { if collapsedLines != oldValue { needsDisplay = true } }
    }
    var showsFoldingRibbon = true {
        didSet { if showsFoldingRibbon != oldValue { needsDisplay = true } }
    }

    var onToggleFold: ((Int) -> Void)?
    var onToggleBookmark: ((Int) -> Void)?
    /// Supplied by the editor document, which keeps a piece-table line index;
    /// without it the gutter would have to scan the text for every line it
    /// draws, which is O(n) per line and unusable on large files.
    var lineNumberProvider: ((Int) -> Int)?

    private let horizontalPadding: CGFloat = 6
    private let foldRibbonWidth: CGFloat = 14
    private var lineCount = 1

    init(scrollView: NSScrollView, textView: NSTextView, style: ThemeStyle) {
        self.scrollView = scrollView
        self.textView = textView
        self.style = style
        super.init(frame: NSRect(x: 0, y: 0, width: 48, height: 0))
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) wordt niet gebruikt")
    }

    // MARK: Layout

    /// Grows the gutter with the line count so five-digit line numbers fit.
    func updateThickness(forLineCount lineCount: Int) {
        self.lineCount = max(1, lineCount)
        let digits = max(2, String(max(1, lineCount)).count)
        let sample = String(repeating: "8", count: digits)
        let width = sample.size(withAttributes: [.font: numberFont]).width
        let total = width + horizontalPadding * 2 + (showsFoldingRibbon ? foldRibbonWidth : 0)
        if abs(total - ruleThickness) > 0.5 {
            ruleThickness = ceil(total)
            superview?.needsLayout = true
        }
    }

    private var numberFont: NSFont {
        NSFont(descriptor: style.font.fontDescriptor, size: max(9, style.font.pointSize - 1)) ?? style.font
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        style.gutterBackgroundColor.setFill()
        dirtyRect.fill()

        let visibleRect = textView.enclosingScrollView?.contentView.bounds ?? .zero
        let inset = textView.textContainerInset
        let caretLine = lineNumberProvider?(textView.selectedRange().location) ?? 0

        let containerRect = visibleRect.offsetBy(dx: -inset.width, dy: -inset.height)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        var drawnLines = Set<Int>()
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] _, usedRect, _, fragmentGlyphRange, _ in
            guard let self else { return }
            let characterRange = layoutManager.characterRange(forGlyphRange: fragmentGlyphRange,
                                                               actualGlyphRange: nil)
            let lineIndex = self.lineNumberProvider?(characterRange.location) ?? 0
            // A wrapped logical line has multiple visual fragments, but its
            // number belongs beside the first fragment only.
            guard drawnLines.insert(lineIndex).inserted else { return }
            let y = usedRect.minY + inset.height - visibleRect.minY
            drawNumber(lineIndex + 1,
                       at: y,
                       height: usedRect.height,
                       isCurrent: lineIndex == caretLine)
            if bookmarkedLines.contains(lineIndex) {
                drawBookmark(at: y, height: usedRect.height)
            }
            if showsFoldingRibbon, foldableLines.contains(lineIndex) {
                drawFoldArrow(at: y, height: usedRect.height, collapsed: collapsedLines.contains(lineIndex))
            }
        }
    }

    private func drawNumber(_ number: Int, at y: CGFloat, height: CGFloat, isCurrent: Bool) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: isCurrent ? style.activeLineNumberColor : style.lineNumberColor
        ]
        let string = NSAttributedString(string: "\(number)", attributes: attributes)
        let size = string.size()
        let x = ruleThickness - horizontalPadding - size.width - (showsFoldingRibbon ? foldRibbonWidth : 0)
        string.draw(at: NSPoint(x: max(2, x), y: y + (height - size.height) / 2))
    }

    private func drawBookmark(at y: CGFloat, height: CGFloat) {
        let diameter: CGFloat = 6
        let rect = NSRect(x: 4, y: y + (height - diameter) / 2, width: diameter, height: diameter)
        style.bookmarkColor.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    private func drawFoldArrow(at y: CGFloat, height: CGFloat, collapsed: Bool) {
        let size: CGFloat = 8
        let x = ruleThickness - foldRibbonWidth + (foldRibbonWidth - size) / 2
        let rect = NSRect(x: x, y: y + (height - size) / 2, width: size, height: size)
        let path = NSBezierPath()
        if collapsed {
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            path.line(to: NSPoint(x: rect.midX, y: rect.maxY))
        }
        path.close()
        style.lineNumberColor.setFill()
        path.fill()
    }

    // MARK: Interaction

    override func mouseDown(with event: NSEvent) {
        guard let textView else { return super.mouseDown(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        let textPoint = textView.convert(event.locationInWindow, from: nil)
        let characterIndex = textView.characterIndexForInsertion(at: textPoint)
        let line = lineNumberProvider?(characterIndex) ?? 0
        guard line >= 0, line < lineCount else { return }

        let inFoldRibbon = point.x > ruleThickness - foldRibbonWidth
        if inFoldRibbon, showsFoldingRibbon, foldableLines.contains(line) {
            onToggleFold?(line)
        } else {
            onToggleBookmark?(line)
        }
    }

    private func lineNumber(at characterIndex: Int, in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }
        let index = max(0, min(characterIndex, text.length))
        if let provider = lineNumberProvider { return provider(index) }
        // Fallback for the rare case where no provider is wired up yet.
        var line = 0
        text.enumerateSubstrings(in: NSRange(location: 0, length: index),
                                 options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            line += 1
        }
        return line
    }
}
