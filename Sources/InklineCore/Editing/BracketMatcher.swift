import Foundation

/// Bracket matching for the editor's highlight and for "ga naar bijbehorend
/// haakje". Ranges that the highlighter reports as string or comment are
/// skipped, so a `}` inside a string literal never steals the match.
public enum BracketMatcher {

    public struct Pair: Equatable, Sendable {
        public let open: UInt16
        public let close: UInt16

        public init(open: Character, close: Character) {
            self.open = Array(String(open).utf16)[0]
            self.close = Array(String(close).utf16)[0]
        }
    }

    public static let defaultPairs: [Pair] = [
        Pair(open: "(", close: ")"),
        Pair(open: "[", close: "]"),
        Pair(open: "{", close: "}")
    ]

    public struct Match: Equatable, Sendable {
        public let origin: Int
        public let counterpart: Int
    }

    /// Finds the bracket that matches the one at (or just before) `offset`.
    /// `ignoredRanges` must be sorted by lower bound.
    public static func match(at offset: Int,
                             in table: PieceTable,
                             pairs: [Pair] = defaultPairs,
                             ignoredRanges: [Range<Int>] = [],
                             searchLimit: Int = 2_000_000) -> Match? {
        guard table.count > 0 else { return nil }

        for candidate in [offset, offset - 1] where candidate >= 0 && candidate < table.count {
            if isIgnored(candidate, ignoredRanges) { continue }
            let unit = table.codeUnit(at: candidate)
            if let pair = pairs.first(where: { $0.open == unit }) {
                if let counterpart = scanForward(from: candidate, pair: pair, in: table,
                                                 ignoredRanges: ignoredRanges, searchLimit: searchLimit) {
                    return Match(origin: candidate, counterpart: counterpart)
                }
                return nil
            }
            if let pair = pairs.first(where: { $0.close == unit }) {
                if let counterpart = scanBackward(from: candidate, pair: pair, in: table,
                                                 ignoredRanges: ignoredRanges, searchLimit: searchLimit) {
                    return Match(origin: candidate, counterpart: counterpart)
                }
                return nil
            }
        }
        return nil
    }

    /// The innermost pair enclosing `offset` — used by "selecteer blok" and by
    /// folding when the language has no grammar.
    public static func enclosingPair(at offset: Int,
                                     in table: PieceTable,
                                     pairs: [Pair] = defaultPairs,
                                     ignoredRanges: [Range<Int>] = []) -> Range<Int>? {
        var depth = 0
        var index = offset - 1
        var opening: (Int, Pair)?
        while index >= 0 {
            if !isIgnored(index, ignoredRanges) {
                let unit = table.codeUnit(at: index)
                if pairs.contains(where: { $0.close == unit }) {
                    depth += 1
                } else if let pair = pairs.first(where: { $0.open == unit }) {
                    if depth == 0 { opening = (index, pair); break }
                    depth -= 1
                }
            }
            index -= 1
        }
        guard let (openIndex, pair) = opening,
              let closeIndex = scanForward(from: openIndex, pair: pair, in: table, ignoredRanges: ignoredRanges,
                                           searchLimit: 2_000_000) else { return nil }
        return openIndex..<(closeIndex + 1)
    }

    private static func scanForward(from index: Int,
                                    pair: Pair,
                                    in table: PieceTable,
                                    ignoredRanges: [Range<Int>],
                                    searchLimit: Int) -> Int? {
        var depth = 0
        var cursor = index
        let end = min(table.count, index + searchLimit)
        while cursor < end {
            if !isIgnored(cursor, ignoredRanges) {
                let unit = table.codeUnit(at: cursor)
                if unit == pair.open {
                    depth += 1
                } else if unit == pair.close {
                    depth -= 1
                    if depth == 0 { return cursor }
                }
            }
            cursor += 1
        }
        return nil
    }

    private static func scanBackward(from index: Int,
                                     pair: Pair,
                                     in table: PieceTable,
                                     ignoredRanges: [Range<Int>],
                                     searchLimit: Int) -> Int? {
        var depth = 0
        var cursor = index
        let end = max(0, index - searchLimit)
        while cursor >= end {
            if !isIgnored(cursor, ignoredRanges) {
                let unit = table.codeUnit(at: cursor)
                if unit == pair.close {
                    depth += 1
                } else if unit == pair.open {
                    depth -= 1
                    if depth == 0 { return cursor }
                }
            }
            cursor -= 1
        }
        return nil
    }

    private static func isIgnored(_ offset: Int, _ ranges: [Range<Int>]) -> Bool {
        guard !ranges.isEmpty else { return false }
        var lo = 0
        var hi = ranges.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if ranges[mid].contains(offset) { return true }
            if ranges[mid].upperBound <= offset { lo = mid + 1 } else { hi = mid - 1 }
        }
        return false
    }
}
