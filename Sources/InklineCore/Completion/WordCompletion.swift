import Foundation

public struct CompletionCandidate: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case word
        case keyword
        case symbol
        case path
    }

    public var id: String { "\(kind.rawValue):\(text)" }
    public let text: String
    public let kind: Kind
    public let detail: String?
    /// Higher sorts first.
    public let score: Int

    public init(text: String, kind: Kind, detail: String? = nil, score: Int = 0) {
        self.text = text
        self.kind = kind
        self.detail = detail
        self.score = score
    }
}

/// Word completion over the current document. An index of the words in the
/// buffer, rebuilt in the background after edits settle, is enough for the
/// "complete a word I already typed somewhere" case that carries most of the
/// day-to-day value; language keywords and grammar symbols are merged in by the
/// caller.
public final class WordIndex {

    private var counts: [String: Int] = [:]
    private let minimumLength: Int

    public init(minimumLength: Int = 3) {
        self.minimumLength = minimumLength
    }

    public var wordCount: Int { counts.count }

    public func rebuild(from text: String) {
        counts = Self.words(in: text, minimumLength: minimumLength)
    }

    public func candidates(prefix: String, limit: Int = 50) -> [CompletionCandidate] {
        guard !prefix.isEmpty else { return [] }
        let lowered = prefix.lowercased()
        return counts
            .filter { $0.key.count > prefix.count && $0.key.lowercased().hasPrefix(lowered) }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(limit)
            .map { CompletionCandidate(text: $0.key, kind: .word, detail: nil, score: $0.value) }
    }

    /// The partial word immediately before `offset`, and its range.
    public static func partialWord(in text: String, before offset: Int) -> (word: String, range: Range<Int>)? {
        let units = Array(text.utf16)
        guard offset > 0, offset <= units.count else { return nil }
        var start = offset
        while start > 0, isWordUnit(units[start - 1]) { start -= 1 }
        guard start < offset else { return nil }
        let slice = Array(units[start..<offset])
        let word = String(utf16CodeUnits: slice, count: slice.count)
        return (word, start..<offset)
    }

    static func words(in text: String, minimumLength: Int) -> [String: Int] {
        var counts = [String: Int]()
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if isWordScalar(scalar) {
                current.append(scalar)
            } else if !current.isEmpty {
                let word = String(current)
                if word.count >= minimumLength { counts[word, default: 0] += 1 }
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty {
            let word = String(current)
            if word.count >= minimumLength { counts[word, default: 0] += 1 }
        }
        return counts
    }

    static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
    }

    static func isWordUnit(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return isWordScalar(scalar)
    }
}

/// Merges the candidate sources the editor has (document words, language
/// keywords, grammar symbols) into one ranked list.
public enum CompletionRanker {
    public static func merge(_ groups: [[CompletionCandidate]],
                             prefix: String,
                             limit: Int = 30) -> [CompletionCandidate] {
        var seen = Set<String>()
        var result = [CompletionCandidate]()
        for candidate in groups.flatMap({ $0 }).sorted(by: { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.text.count != rhs.text.count { return lhs.text.count < rhs.text.count }
            return lhs.text < rhs.text
        }) {
            guard candidate.text != prefix, seen.insert(candidate.text).inserted else { continue }
            result.append(candidate)
            if result.count >= limit { break }
        }
        return result
    }
}
