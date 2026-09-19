import Foundation

/// Everything the Find bar can ask for, in one value type so it can be stored
/// in preferences, replayed by a macro and sent to Find in Files unchanged.
public struct SearchQuery: Equatable, Codable, Sendable {
    public var pattern: String
    public var isRegularExpression: Bool
    public var isCaseSensitive: Bool
    public var matchesWholeWords: Bool
    public var wrapsAround: Bool
    /// Interpret `\n`, `\t`, `\r`, `\0` and `\\` in the pattern and the
    /// replacement, the way Notepad++'s "Extended" search mode does.
    public var usesEscapeSequences: Bool

    public init(pattern: String = "",
                isRegularExpression: Bool = false,
                isCaseSensitive: Bool = false,
                matchesWholeWords: Bool = false,
                wrapsAround: Bool = true,
                usesEscapeSequences: Bool = false) {
        self.pattern = pattern
        self.isRegularExpression = isRegularExpression
        self.isCaseSensitive = isCaseSensitive
        self.matchesWholeWords = matchesWholeWords
        self.wrapsAround = wrapsAround
        self.usesEscapeSequences = usesEscapeSequences
    }

    public var isEmpty: Bool { pattern.isEmpty }
}

public struct SearchMatch: Equatable, Sendable {
    public let range: Range<Int>
    /// Capture group ranges for regular expression searches; index 0 is the
    /// whole match. `nil` entries are groups that did not participate.
    public let captureGroups: [Range<Int>?]

    public init(range: Range<Int>, captureGroups: [Range<Int>?] = []) {
        self.range = range
        self.captureGroups = captureGroups
    }
}

public enum SearchError: LocalizedError, Equatable {
    case invalidPattern(String)
    case emptyPattern

    public var errorDescription: String? {
        switch self {
        case let .invalidPattern(message): return "Ongeldige zoekexpressie: \(message)"
        case .emptyPattern: return "Geef een zoekterm op."
        }
    }
}

public enum SearchDirection: String, Codable, Sendable {
    case forward
    case backward
}
