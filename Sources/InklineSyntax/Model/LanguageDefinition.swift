import Foundation
import InklineCore

/// A language, entirely as data. Dropping a JSON file into
/// `~/Library/Application Support/Inkline/Languages/` adds a language to the
/// running app — no recompile, no code. See `docs/Talen-toevoegen.md`.
public struct LanguageDefinition: Codable, Equatable, Identifiable, Sendable {

    public struct CommentStyle: Codable, Equatable, Sendable {
        public var line: String?
        public var blockStart: String?
        public var blockEnd: String?

        public init(line: String? = nil, blockStart: String? = nil, blockEnd: String? = nil) {
            self.line = line
            self.blockStart = blockStart
            self.blockEnd = blockEnd
        }
    }

    public struct BracketPair: Codable, Equatable, Sendable {
        public var open: String
        public var close: String

        public init(open: String, close: String) {
            self.open = open
            self.close = close
        }
    }

    /// One rule of the regular-expression highlighter. Rules are tried in
    /// order and the first match on a position wins, so comments and strings
    /// must come before keywords.
    public struct PatternRule: Codable, Equatable, Sendable {
        public var scope: HighlightScope
        public var pattern: String
        /// Capture group to colour; 0 (the default) colours the whole match.
        public var captureGroup: Int
        public var caseInsensitive: Bool
        /// True for rules that may span lines (block comments, heredocs); these
        /// force the incremental highlighter to re-scan from a safe point.
        public var multiline: Bool

        public init(scope: HighlightScope,
                    pattern: String,
                    captureGroup: Int = 0,
                    caseInsensitive: Bool = false,
                    multiline: Bool = false) {
            self.scope = scope
            self.pattern = pattern
            self.captureGroup = captureGroup
            self.caseInsensitive = caseInsensitive
            self.multiline = multiline
        }
    }

    /// A rule that feeds the Functielijst panel.
    public struct SymbolRule: Codable, Equatable, Sendable {
        public var kind: SymbolKind
        public var pattern: String
        public var nameGroup: Int
        public var containerGroup: Int?

        public init(kind: SymbolKind, pattern: String, nameGroup: Int = 1, containerGroup: Int? = nil) {
            self.kind = kind
            self.pattern = pattern
            self.nameGroup = nameGroup
            self.containerGroup = containerGroup
        }
    }

    /// Where the tree-sitter grammar for this language lives. Grammars are
    /// dynamic libraries loaded at runtime, which is what keeps "add a
    /// language" a data change.
    public struct TreeSitterConfiguration: Codable, Equatable, Sendable {
        /// Symbol name suffix: the loader looks up `tree_sitter_<grammar>`.
        public var grammar: String
        /// File name of the dynamic library inside the Grammars directory,
        /// e.g. `libtree-sitter-swift.dylib`.
        public var library: String
        /// Highlight query file, relative to the Grammars directory.
        public var highlightsQuery: String?
        public var injectionsQuery: String?
        public var localsQuery: String?

        public init(grammar: String,
                    library: String,
                    highlightsQuery: String? = nil,
                    injectionsQuery: String? = nil,
                    localsQuery: String? = nil) {
            self.grammar = grammar
            self.library = library
            self.highlightsQuery = highlightsQuery
            self.injectionsQuery = injectionsQuery
            self.localsQuery = localsQuery
        }
    }

    public var identifier: String
    public var name: String
    public var fileExtensions: [String]
    public var fileNames: [String]
    /// Regular expression matched against the first line (shebangs, XML
    /// declarations, modelines).
    public var firstLinePattern: String?
    public var comments: CommentStyle
    public var brackets: [BracketPair]
    public var autoClosePairs: [BracketPair]
    public var indentation: IndentationSettings
    public var indentationRules: IndentationRules
    public var folding: FoldingStrategy
    public var keywords: [String]
    public var patterns: [PatternRule]
    public var symbols: [SymbolRule]
    public var treeSitter: TreeSitterConfiguration?
    /// Higher wins when two languages claim the same extension.
    public var priority: Int

    public var id: String { identifier }

    public init(identifier: String,
                name: String,
                fileExtensions: [String] = [],
                fileNames: [String] = [],
                firstLinePattern: String? = nil,
                comments: CommentStyle = CommentStyle(),
                brackets: [BracketPair] = [BracketPair(open: "(", close: ")"),
                                           BracketPair(open: "[", close: "]"),
                                           BracketPair(open: "{", close: "}")],
                autoClosePairs: [BracketPair] = [],
                indentation: IndentationSettings = .default,
                indentationRules: IndentationRules = .curlyBraces,
                folding: FoldingStrategy = .brackets,
                keywords: [String] = [],
                patterns: [PatternRule] = [],
                symbols: [SymbolRule] = [],
                treeSitter: TreeSitterConfiguration? = nil,
                priority: Int = 0) {
        self.identifier = identifier
        self.name = name
        self.fileExtensions = fileExtensions
        self.fileNames = fileNames
        self.firstLinePattern = firstLinePattern
        self.comments = comments
        self.brackets = brackets
        self.autoClosePairs = autoClosePairs
        self.indentation = indentation
        self.indentationRules = indentationRules
        self.folding = folding
        self.keywords = keywords
        self.patterns = patterns
        self.symbols = symbols
        self.treeSitter = treeSitter
        self.priority = priority
    }

    /// Plain text: no rules at all. Every document has a language, which
    /// removes a pile of optionals from the editor.
    public static let plainText = LanguageDefinition(identifier: "plaintext",
                                                     name: "Platte tekst",
                                                     fileExtensions: ["txt", "text", "log"],
                                                     indentationRules: .none,
                                                     folding: FoldingStrategy.none)

    public var bracketPairs: [BracketMatcher.Pair] {
        brackets.compactMap { pair in
            guard let open = pair.open.first, let close = pair.close.first else { return nil }
            return BracketMatcher.Pair(open: open, close: close)
        }
    }

    /// Decoding fills in sensible defaults for every optional key, so a
    /// hand-written language file can be four lines long.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(String.self, forKey: .identifier)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? identifier
        fileExtensions = try container.decodeIfPresent([String].self, forKey: .fileExtensions) ?? []
        fileNames = try container.decodeIfPresent([String].self, forKey: .fileNames) ?? []
        firstLinePattern = try container.decodeIfPresent(String.self, forKey: .firstLinePattern)
        comments = try container.decodeIfPresent(CommentStyle.self, forKey: .comments) ?? CommentStyle()
        brackets = try container.decodeIfPresent([BracketPair].self, forKey: .brackets)
            ?? [BracketPair(open: "(", close: ")"),
                BracketPair(open: "[", close: "]"),
                BracketPair(open: "{", close: "}")]
        autoClosePairs = try container.decodeIfPresent([BracketPair].self, forKey: .autoClosePairs) ?? brackets
        indentation = try container.decodeIfPresent(IndentationSettings.self, forKey: .indentation) ?? .default
        indentationRules = try container.decodeIfPresent(IndentationRules.self, forKey: .indentationRules) ?? .curlyBraces
        folding = try container.decodeIfPresent(FoldingStrategy.self, forKey: .folding) ?? .brackets
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        patterns = try container.decodeIfPresent([PatternRule].self, forKey: .patterns) ?? []
        symbols = try container.decodeIfPresent([SymbolRule].self, forKey: .symbols) ?? []
        treeSitter = try container.decodeIfPresent(TreeSitterConfiguration.self, forKey: .treeSitter)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
    }
}

extension LanguageDefinition.PatternRule {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try container.decode(HighlightScope.self, forKey: .scope)
        pattern = try container.decode(String.self, forKey: .pattern)
        captureGroup = try container.decodeIfPresent(Int.self, forKey: .captureGroup) ?? 0
        caseInsensitive = try container.decodeIfPresent(Bool.self, forKey: .caseInsensitive) ?? false
        multiline = try container.decodeIfPresent(Bool.self, forKey: .multiline) ?? false
    }
}

extension LanguageDefinition.SymbolRule {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(SymbolKind.self, forKey: .kind) ?? .function
        pattern = try container.decode(String.self, forKey: .pattern)
        nameGroup = try container.decodeIfPresent(Int.self, forKey: .nameGroup) ?? 1
        containerGroup = try container.decodeIfPresent(Int.self, forKey: .containerGroup)
    }
}
