import Foundation

/// How a document indents. Comes from the language definition, can be
/// overridden per document from the status bar.
public struct IndentationSettings: Equatable, Codable, Sendable {
    public var usesTabs: Bool
    public var indentWidth: Int
    public var tabWidth: Int

    public init(usesTabs: Bool = false, indentWidth: Int = 4, tabWidth: Int = 4) {
        self.usesTabs = usesTabs
        self.indentWidth = max(1, indentWidth)
        self.tabWidth = max(1, tabWidth)
    }

    public static let `default` = IndentationSettings()

    /// One level of indentation as literal text.
    public var unit: String {
        usesTabs ? "\t" : String(repeating: " ", count: indentWidth)
    }

    public func indentation(forLevel level: Int) -> String {
        String(repeating: unit, count: max(0, level))
    }

    /// Visual width of a leading whitespace run, honouring tab stops.
    public func visualWidth(of whitespace: some StringProtocol) -> Int {
        var width = 0
        for character in whitespace {
            width += character == "\t" ? tabWidth - (width % tabWidth) : 1
        }
        return width
    }
}

/// Data-driven indentation rules; every language definition carries a set.
public struct IndentationRules: Equatable, Codable, Sendable {
    /// Regular expression: a line matching this increases the indent of the
    /// next line.
    public var increaseAfterPattern: String?
    /// Regular expression: a line matching this is itself outdented.
    public var decreaseOnPattern: String?
    /// Characters that, when typed as the first non-blank character of a line,
    /// re-indent that line (closing brackets, `end`, …).
    public var reindentTriggers: [String]

    public init(increaseAfterPattern: String? = #"[\{\[\(]\s*$"#,
                decreaseOnPattern: String? = #"^\s*[\}\]\)]"#,
                reindentTriggers: [String] = ["}", "]", ")"]) {
        self.increaseAfterPattern = increaseAfterPattern
        self.decreaseOnPattern = decreaseOnPattern
        self.reindentTriggers = reindentTriggers
    }

    public static let curlyBraces = IndentationRules()
    public static let none = IndentationRules(increaseAfterPattern: nil,
                                              decreaseOnPattern: nil,
                                              reindentTriggers: [])
}

/// Computes the indentation for a newly inserted line and for re-indent
/// triggers. Kept string-based (rather than grammar-based) on purpose: it has
/// to answer instantly on every Return keystroke, including in files whose
/// grammar has not finished parsing yet.
public struct IndentationEngine {

    private let settings: IndentationSettings
    private let rules: IndentationRules
    private let increaseRegex: NSRegularExpression?
    private let decreaseRegex: NSRegularExpression?

    public init(settings: IndentationSettings, rules: IndentationRules = .curlyBraces) {
        self.settings = settings
        self.rules = rules
        self.increaseRegex = rules.increaseAfterPattern.flatMap { try? NSRegularExpression(pattern: $0) }
        self.decreaseRegex = rules.decreaseOnPattern.flatMap { try? NSRegularExpression(pattern: $0) }
    }

    /// Leading whitespace of `line`.
    public static func leadingWhitespace(of line: String) -> String {
        String(line.prefix(while: { $0 == " " || $0 == "\t" }))
    }

    /// The text to insert after a newline typed at the end of `previousLine`.
    public func indentation(after previousLine: String) -> String {
        let existing = Self.leadingWhitespace(of: previousLine)
        guard matches(increaseRegex, previousLine) else { return existing }
        return existing + settings.unit
    }

    /// What a line should look like after typing a re-indent trigger: returns
    /// the replacement for the line's leading whitespace, or `nil` when it is
    /// already right.
    public func reindentation(for line: String, previousLine: String?) -> String? {
        guard matches(decreaseRegex, line) else { return nil }
        let previous = previousLine ?? ""
        var target = Self.leadingWhitespace(of: previous)
        if !matches(increaseRegex, previous), !target.isEmpty {
            target = removeOneLevel(from: target)
        }
        let current = Self.leadingWhitespace(of: line)
        return current == target ? nil : target
    }

    /// Whether the caret sits between a matching bracket pair, which is when
    /// Return should open a blank indented line and push the closing bracket
    /// down one more.
    public func shouldExpandBracketPair(before: Character?, after: Character?) -> Bool {
        guard let before, let after else { return false }
        switch (before, after) {
        case ("{", "}"), ("[", "]"), ("(", ")"): return true
        default: return false
        }
    }

    private func removeOneLevel(from whitespace: String) -> String {
        if settings.usesTabs, whitespace.hasSuffix("\t") { return String(whitespace.dropLast()) }
        let width = settings.visualWidth(of: whitespace)
        let target = max(0, width - settings.indentWidth)
        return settings.usesTabs
            ? String(repeating: "\t", count: target / settings.tabWidth)
                + String(repeating: " ", count: target % settings.tabWidth)
            : String(repeating: " ", count: target)
    }

    private func matches(_ regex: NSRegularExpression?, _ line: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(location: 0, length: (line as NSString).length)
        return regex.firstMatch(in: line, options: [], range: range) != nil
    }
}
