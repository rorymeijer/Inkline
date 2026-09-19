import Foundation
import InklineCore

/// What the editor needs from a highlighter, whatever is behind it: the
/// regular-expression fallback in this module, or tree-sitter in
/// `InklineTreeSitter`.
///
/// Implementations must be cheap for the *visible* range: the editor asks for
/// the range it is about to draw, never for the whole document.
public protocol SyntaxHighlighter: AnyObject {
    var language: LanguageDefinition { get }

    /// Tokens covering `range`. Implementations may return tokens that extend
    /// beyond it (a block comment that starts earlier); the caller clips.
    func tokens(in range: Range<Int>, text: String) -> [HighlightToken]

    /// Called after every edit so incremental implementations can reuse their
    /// parse tree instead of starting over.
    func didChange(_ change: TextChange, newText: String)

    /// Drop all cached state — language switched, theme reloaded, file
    /// reverted.
    func invalidate()

    /// Ranges the bracket matcher and auto-indenter must ignore because they
    /// are inside a string or a comment.
    func commentAndStringRanges(in range: Range<Int>, text: String) -> [Range<Int>]
}

extension SyntaxHighlighter {
    public func commentAndStringRanges(in range: Range<Int>, text: String) -> [Range<Int>] {
        tokens(in: range, text: text)
            .filter { $0.scope.isCommentOrString }
            .map(\.range)
            .sorted { $0.lowerBound < $1.lowerBound }
    }
}

/// A highlighter for documents without a language: no tokens, no work.
public final class NullHighlighter: SyntaxHighlighter {
    public let language: LanguageDefinition

    public init(language: LanguageDefinition = .plainText) {
        self.language = language
    }

    public func tokens(in range: Range<Int>, text: String) -> [HighlightToken] { [] }
    public func didChange(_ change: TextChange, newText: String) {}
    public func invalidate() {}
}
