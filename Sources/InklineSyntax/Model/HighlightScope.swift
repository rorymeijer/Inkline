import Foundation

/// The vocabulary shared by grammars, themes and the renderer.
///
/// Tree-sitter highlight queries use names like `@keyword.control` and
/// `@function.method`; those are mapped onto this fixed set by taking the
/// longest matching prefix, so a new grammar never needs new code to be
/// coloured — it just needs its query captures to start with a known word.
public enum HighlightScope: String, CaseIterable, Codable, Sendable {
    case plain
    case comment
    case documentationComment
    case keyword
    case controlKeyword
    case storage              // type/class/func introducers
    case type
    case constant
    case number
    case string
    case escapeSequence
    case regularExpression
    case character
    case function
    case method
    case parameter
    case property
    case variable
    case `operator`
    case punctuation
    case attribute
    case tag
    case tagAttribute
    case heading
    case emphasis
    case strong
    case link
    case listMarker
    case preprocessor
    case label
    case namespace
    case error

    /// Maps a tree-sitter capture name (`keyword.control`, `function.builtin`,
    /// `variable.parameter`, …) onto a scope, longest prefix wins.
    public static func fromCaptureName(_ name: String) -> HighlightScope? {
        let normalized = name.hasPrefix("@") ? String(name.dropFirst()) : name
        if let direct = captureAliases[normalized] { return direct }

        var components = normalized.split(separator: ".").map(String.init)
        while components.count > 1 {
            components.removeLast()
            let prefix = components.joined(separator: ".")
            if let match = captureAliases[prefix] { return match }
        }
        return nil
    }

    private static let captureAliases: [String: HighlightScope] = [
        "comment": .comment,
        "comment.documentation": .documentationComment,
        "keyword": .keyword,
        "keyword.control": .controlKeyword,
        "keyword.conditional": .controlKeyword,
        "keyword.repeat": .controlKeyword,
        "keyword.return": .controlKeyword,
        "keyword.function": .storage,
        "keyword.type": .storage,
        "keyword.storage": .storage,
        "keyword.directive": .preprocessor,
        "conditional": .controlKeyword,
        "repeat": .controlKeyword,
        "include": .preprocessor,
        "preproc": .preprocessor,
        "storageclass": .storage,
        "type": .type,
        "type.builtin": .type,
        "constructor": .type,
        "constant": .constant,
        "constant.builtin": .constant,
        "boolean": .constant,
        "number": .number,
        "float": .number,
        "string": .string,
        "string.escape": .escapeSequence,
        "string.special": .escapeSequence,
        "escape": .escapeSequence,
        "character": .character,
        "regex": .regularExpression,
        "function": .function,
        "function.builtin": .function,
        "function.method": .method,
        "method": .method,
        "parameter": .parameter,
        "variable.parameter": .parameter,
        "property": .property,
        "field": .property,
        "variable": .variable,
        "variable.builtin": .variable,
        "operator": .operator,
        "punctuation": .punctuation,
        "punctuation.bracket": .punctuation,
        "punctuation.delimiter": .punctuation,
        "punctuation.special": .punctuation,
        "attribute": .attribute,
        "annotation": .attribute,
        "tag": .tag,
        "tag.attribute": .tagAttribute,
        "text.title": .heading,
        "markup.heading": .heading,
        "text.emphasis": .emphasis,
        "markup.italic": .emphasis,
        "text.strong": .strong,
        "markup.bold": .strong,
        "text.uri": .link,
        "markup.link": .link,
        "text.literal": .string,
        "markup.list": .listMarker,
        "label": .label,
        "namespace": .namespace,
        "module": .namespace,
        "error": .error
    ]

    /// Scopes that the bracket matcher and the auto-indenter must ignore.
    public var isCommentOrString: Bool {
        switch self {
        case .comment, .documentationComment, .string, .character, .regularExpression, .escapeSequence:
            return true
        default:
            return false
        }
    }
}

/// A highlighted span, in UTF-16 document offsets.
public struct HighlightToken: Equatable, Sendable {
    public let range: Range<Int>
    public let scope: HighlightScope

    public init(range: Range<Int>, scope: HighlightScope) {
        self.range = range
        self.scope = scope
    }
}
