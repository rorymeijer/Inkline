import AppKit
import InklineCore
import InklineSyntax

/// The `NSTextStorage` behind every editor view.
///
/// It keeps an `NSMutableAttributedString` as TextKit expects, and applies
/// syntax highlighting *lazily, per visible range*: `applyHighlighting(in:)` is
/// called by the layout manager's delegate for the range about to be drawn, and
/// tokens that are not cached yet are computed on a background queue by
/// `HighlightCoordinator`.
///
/// Highlighting never blocks typing: an edit only invalidates, it never parses.
final class InklineTextStorage: NSTextStorage {

    private let backing = NSMutableAttributedString()

    /// Set by the editor; used for colours, fonts and tab stops.
    var style: ThemeStyle {
        didSet { applyBaseAttributes() }
    }

    var coordinator: HighlightCoordinator {
        didSet {
            coordinator.onTokensReady = { [weak self] range, tokens in
                self?.applyTokens(tokens, in: range)
            }
            invalidateHighlighting()
        }
    }

    var indentation: IndentationSettings = .default {
        didSet { if indentation != oldValue { applyBaseAttributes() } }
    }

    var wrapsLines = false {
        didSet { if wrapsLines != oldValue { applyBaseAttributes() } }
    }

    /// Called after every edit so the document model can mirror it.
    var onEdit: ((TextChange) -> Void)?

    private var highlightedRanges = IndexSet()
    private var isApplyingHighlighting = false

    init(style: ThemeStyle, coordinator: HighlightCoordinator) {
        self.style = style
        self.coordinator = coordinator
        super.init()
        self.coordinator.onTokensReady = { [weak self] range, tokens in
            self?.applyTokens(tokens, in: range)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) wordt niet gebruikt")
    }

    @available(*, unavailable)
    override init(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        fatalError("niet ondersteund")
    }

    // MARK: NSTextStorage primitives

    override var string: String { backing.string }

    override func attributes(at location: Int,
                             effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        let removed = backing.attributedSubstring(from: range).string
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited([.editedCharacters, .editedAttributes],
               range: range,
               changeInLength: (str as NSString).length - range.length)
        endEditing()

        let change = TextChange(editedRange: range.location..<(range.location + range.length),
                                removedText: removed,
                                insertedText: str)
        invalidateHighlighting(from: range.location)
        onEdit?(change)
        coordinator.handle(change, newText: backing.string)
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: Highlighting

    /// Re-applies font, colour and paragraph style to the whole document. Cheap
    /// enough even for large files because it is one attribute run.
    func applyBaseAttributes() {
        let whole = NSRange(location: 0, length: backing.length)
        var attributes = style.defaultAttributes
        attributes[.paragraphStyle] = style.paragraphStyle(indentWidth: indentation.indentWidth,
                                                           tabWidth: indentation.tabWidth,
                                                           wraps: wrapsLines)
        beginEditing()
        backing.setAttributes(attributes, range: whole)
        edited(.editedAttributes, range: whole, changeInLength: 0)
        endEditing()
        highlightedRanges.removeAll()
    }

    func invalidateHighlighting(from location: Int = 0) {
        if location == 0 {
            highlightedRanges.removeAll()
        } else {
            highlightedRanges.remove(integersIn: location..<Int.max)
        }
    }

    /// Ensures `range` is highlighted, scheduling background work when needed.
    func applyHighlighting(in range: NSRange) {
        guard backing.length > 0 else { return }
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: backing.length))
        guard clamped.length > 0 else { return }

        let swiftRange = clamped.location..<(clamped.location + clamped.length)
        if let cached = coordinator.cachedTokens(in: swiftRange) {
            applyTokens(cached, in: swiftRange)
        } else {
            coordinator.requestTokens(in: swiftRange, text: backing.string)
        }
    }

    private func applyTokens(_ tokens: [HighlightToken], in range: Range<Int>) {
        guard !isApplyingHighlighting else { return }
        isApplyingHighlighting = true
        defer { isApplyingHighlighting = false }

        let length = backing.length
        let lower = min(range.lowerBound, length)
        let upper = min(range.upperBound, length)
        guard lower < upper else { return }
        let nsRange = NSRange(location: lower, length: upper - lower)

        beginEditing()
        // Reset to the default colour first, otherwise stale colours survive an
        // edit that removed the token that produced them.
        backing.addAttribute(.foregroundColor, value: style.foregroundColor, range: nsRange)
        backing.addAttribute(.font, value: style.font, range: nsRange)
        for token in tokens {
            let tokenLower = max(token.range.lowerBound, lower)
            let tokenUpper = min(token.range.upperBound, upper)
            guard tokenLower < tokenUpper else { continue }
            backing.addAttributes(style.attributes(for: token.scope),
                                  range: NSRange(location: tokenLower, length: tokenUpper - tokenLower))
        }
        edited(.editedAttributes, range: nsRange, changeInLength: 0)
        endEditing()

        highlightedRanges.insert(integersIn: lower..<upper)
    }

    // MARK: Convenience

    func setText(_ text: String) {
        replaceCharacters(in: NSRange(location: 0, length: backing.length), with: text)
        applyBaseAttributes()
    }

    var swiftString: String { backing.string }
}
