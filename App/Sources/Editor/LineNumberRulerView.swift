import AppKit
import InklineCore

/// The gutter: line numbers, bookmark dots and fold arrows.
///
/// Drawn by hand rather than with a stack of views, because a 3-million-line
/// document must not cost three million views. Only the visible glyph range is
/// ever touched.
final class LineNumberRulerView: NSRulerView {

    weak var textView: NSTextView?
    var style: ThemeStyle { didSet { needsDisplay = true } }

    /// Line numbers (zero-based) that carry a bookmark.
    var bookmarkedLines: Set<Int> = [] { didSet { needsDisplay = true } }
    /// Lines that start a foldable region, and which of them are collapsed.
    var foldableLines: Set<Int> = [] { didSet { needsDisplay = true } }
    var collapsedLines: Set<Int> = [] { didSet { needsDisplay = true } }
    var showsFoldingRibbon = true { didSet { needsDisplay = true } }

    var onToggleFold: ((Int) -> Void)?
    var onToggleBookmark: ((Int) -> Void)?
    /// Supplied by the editor document, which keeps a piece-table line index;
    /// without it the gutter would have to scan the text for every line it
    /// draws, which is O(n) per line and unusable on large files.
    var lineNumberProvider: ((Int) -> Int)?

    private let horizontalPadding: CGFloat = 6
    private let foldRibbonWidth: CGFloat = 14

    init(textView: NSTextView, style: ThemeStyle) {
        self.textView = textView
        self.style = style
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 48
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) wordt niet gebruikt")
    }

    // MARK: Layout

    /// Grows the gutter with the line count so five-digit line numbers fit.
    func updateThickness(forLineCount lineCount: Int) {
        let digits = max(2, String(max(1, lineCount)).count)
        let sample = String(repeating: "8", count: digits)
        let width = sample.size(withAttributes: [.font: numberFont]).width
        let total = width + horizontalPadding * 2 + (showsFoldingRibbon ? foldRibbonWidth : 0)
        if abs(total - ruleThickness) > 0.5 {
            ruleThickness = ceil(total)
        }
    }

    private var numberFont: NSFont {
        NSFont(descriptor: style.font.fontDescriptor, size: max(9, style.font.pointSize - 1)) ?? style.font
    }

    // MARK: Drawing

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        style.gutterBackgroundColor.setFill()
        rect.fill()

        let text = textView.string as NSString
        let visibleRect = textView.enclosingScrollView?.contentView.bounds ?? .zero
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let insetY = textView.textContainerInset.height
        let selectedRange = textView.selectedRange()
        let caretLine = text.length > 0 ? lineNumber(at: min(selectedRange.location, text.length), in: text) : 0

        var lineIndex = lineNumber(at: characterRange.location, in: text)
        var characterIndex = characterRange.location

        while characterIndex <= NSMaxRange(characterRange) && characterIndex <= text.length {
            let lineRange = text.lineRange(for: NSRange(location: min(characterIndex, max(0, text.length - 1)),
                                                        length: 0))
            let fragmentRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: lineRange.location, length: 0),
                                                          in: container)
            let y = fragmentRect.minY + insetY - visibleRect.minY

            drawNumber(lineIndex + 1,
                       at: y,
                       height: fragmentRect.height,
                       isCurrent: lineIndex == caretLine)
            if bookmarkedLines.contains(lineIndex) {
                drawBookmark(at: y, height: fragmentRect.height)
            }
            if showsFoldingRibbon, foldableLines.contains(lineIndex) {
                drawFoldArrow(at: y, height: fragmentRect.height, collapsed: collapsedLines.contains(lineIndex))
            }

            lineIndex += 1
            let next = NSMaxRange(lineRange)
            if next <= characterIndex { break }
            characterIndex = next
            if characterIndex >= text.length { break }
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
        guard let line = lineNumber(atPoint: point, in: textView) else { return }

        let inFoldRibbon = point.x > ruleThickness - foldRibbonWidth
        if inFoldRibbon, showsFoldingRibbon, foldableLines.contains(line) {
            onToggleFold?(line)
        } else {
            onToggleBookmark?(line)
        }
    }

    private func lineNumber(atPoint point: NSPoint, in textView: NSTextView) -> Int? {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return nil }
        let visibleRect = textView.enclosingScrollView?.contentView.bounds ?? .zero
        let textPoint = NSPoint(x: 0, y: point.y + visibleRect.minY - textView.textContainerInset.height)
        let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: container)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return lineNumber(at: characterIndex, in: textView.string as NSString)
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
