import Foundation
import InklineCore
import InklineSyntax

#if canImport(SwiftTreeSitter)
import SwiftTreeSitter
#endif

/// Highlighting backed by a real parse tree.
///
/// Inkline treats tree-sitter as an *upgrade*, never a requirement: when the
/// grammar for a language is missing — or when this build was made without the
/// SwiftTreeSitter package — `TreeSitterHighlighterFactory` hands back the
/// regular-expression `PatternHighlighter` instead and everything keeps
/// working. That is why the editor has no `if treeSitterAvailable` anywhere.
public enum TreeSitterHighlighterFactory {

    /// Returns a tree-sitter highlighter when possible, otherwise the pattern
    /// highlighter. Never throws: a broken grammar degrades, it does not stop
    /// the user from editing.
    public static func makeHighlighter(for language: LanguageDefinition,
                                       loader: TreeSitterGrammarLoader?) -> SyntaxHighlighter {
        guard let loader, let configuration = language.treeSitter else {
            return PatternHighlighter(language: language)
        }
        do {
            return try makeTreeSitterHighlighter(language: language,
                                                 configuration: configuration,
                                                 loader: loader)
        } catch {
            return PatternHighlighter(language: language)
        }
    }

    static func makeTreeSitterHighlighter(language: LanguageDefinition,
                                          configuration: LanguageDefinition.TreeSitterConfiguration,
                                          loader: TreeSitterGrammarLoader) throws -> SyntaxHighlighter {
        #if canImport(SwiftTreeSitter)
        return try TreeSitterHighlighter(language: language, configuration: configuration, loader: loader)
        #else
        throw TreeSitterGrammarLoader.LoaderError.unavailable
        #endif
    }
}

#if canImport(SwiftTreeSitter)

/// Incremental tree-sitter highlighter.
///
/// Keeps the parse tree between edits and feeds tree-sitter the same `InputEdit`
/// the buffer applied, so typing re-parses only the affected subtree instead of
/// the whole document.
public final class TreeSitterHighlighter: SyntaxHighlighter {

    public let language: LanguageDefinition

    private let parser = Parser()
    private let tsLanguage: Language
    private let query: Query?
    private var tree: Tree?
    private var parsedText: String = ""
    private let lock = NSLock()

    init(language: LanguageDefinition,
         configuration: LanguageDefinition.TreeSitterConfiguration,
         loader: TreeSitterGrammarLoader) throws {
        self.language = language

        let pointer = try loader.languagePointer(for: configuration)
        tsLanguage = Language(language: pointer)
        try parser.setLanguage(tsLanguage)

        if let queryText = try? loader.queryText(for: configuration) {
            query = try? Query(language: tsLanguage, data: Data(queryText.utf8))
        } else {
            query = nil
        }
    }

    // MARK: SyntaxHighlighter

    public func tokens(in range: Range<Int>, text: String) -> [HighlightToken] {
        lock.lock()
        defer { lock.unlock() }

        guard let query else { return [] }
        ensureTree(for: text)
        guard let tree, let root = tree.rootNode else { return [] }

        let cursor = query.execute(node: root, in: tree)
        cursor.setRange(NSRange(location: range.lowerBound, length: range.count))

        var tokens = [HighlightToken]()
        while let match = cursor.next() {
            for capture in match.captures {
                guard let scope = HighlightScope.fromCaptureName(capture.name ?? "") else { continue }
                let nsRange = capture.range
                guard nsRange.length > 0 else { continue }
                tokens.append(HighlightToken(range: nsRange.location..<(nsRange.location + nsRange.length),
                                             scope: scope))
            }
        }
        return resolveOverlaps(tokens)
    }

    /// Documents above this size skip incremental re-parsing and are parsed
    /// afresh on the next request; computing the edit points for a 100 MB file
    /// on every keystroke costs more than it saves.
    public static let incrementalParseLimit = 4 * 1024 * 1024

    public func didChange(_ change: TextChange, newText: String) {
        lock.lock()
        defer { lock.unlock() }

        let nsText = newText as NSString
        guard let currentTree = tree, nsText.length <= Self.incrementalParseLimit else {
            tree = nil                      // full re-parse on the next request
            parsedText = ""
            return
        }

        // tree-sitter wants byte offsets and row/column points. The text is
        // parsed as UTF-16, so a byte offset is twice the UTF-16 offset, and a
        // column is twice the UTF-16 column.
        let startOffset = change.editedRange.lowerBound
        let start = point(at: startOffset, in: nsText)
        let oldEnd = advance(start, by: change.removedText)
        let newEnd = advance(start, by: change.insertedText)

        let edit = InputEdit(startByte: UInt32(startOffset * 2),
                             oldEndByte: UInt32(change.editedRange.upperBound * 2),
                             newEndByte: UInt32((startOffset + change.insertedText.utf16.count) * 2),
                             startPoint: start,
                             oldEndPoint: oldEnd,
                             newEndPoint: newEnd)
        currentTree.edit(edit)
        tree = parser.parse(tree: currentTree, string: newText)
        parsedText = newText
    }

    /// Row/column (column in bytes) of a UTF-16 offset.
    private func point(at offset: Int, in text: NSString) -> Point {
        var row: UInt32 = 0
        var lineStart = 0
        var index = 0
        while index < offset {
            if text.character(at: index) == 0x000A {
                row += 1
                lineStart = index + 1
            }
            index += 1
        }
        return Point(row: row, column: UInt32((offset - lineStart) * 2))
    }

    /// The point reached after inserting or removing `text` at `start`.
    private func advance(_ start: Point, by text: String) -> Point {
        var row = start.row
        var column = start.column
        for unit in text.utf16 {
            if unit == 0x000A {
                row += 1
                column = 0
            } else {
                column += 2
            }
        }
        return Point(row: row, column: column)
    }

    public func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        tree = nil
        parsedText = ""
    }

    // MARK: Internals

    private func ensureTree(for text: String) {
        guard tree == nil || parsedText != text else { return }
        tree = parser.parse(text)
        parsedText = text
    }

    /// Later captures in a tree-sitter query win over earlier ones for the same
    /// range; after sorting we keep the first token at each position and drop
    /// anything it covers, which matches how other editors render these queries.
    private func resolveOverlaps(_ tokens: [HighlightToken]) -> [HighlightToken] {
        let sorted = tokens.sorted { lhs, rhs in
            if lhs.range.lowerBound != rhs.range.lowerBound {
                return lhs.range.lowerBound < rhs.range.lowerBound
            }
            return lhs.range.count < rhs.range.count      // prefer the most specific capture
        }
        var result = [HighlightToken]()
        var cursor = Int.min
        for token in sorted where token.range.lowerBound >= cursor {
            result.append(token)
            cursor = token.range.upperBound
        }
        return result
    }
}

#endif
