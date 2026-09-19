import Foundation

/// All searching in Inkline funnels through here: the Find bar, Find in Files,
/// "replace in all open tabs", macros and plugins. One implementation means one
/// set of semantics — and one set of tests.
public enum SearchEngine {

    // MARK: Compiling

    /// Builds the regular expression that implements `query`. Literal searches
    /// are escaped rather than special-cased, so whole-word and wrap-around
    /// behave identically in every mode.
    public static func regularExpression(for query: SearchQuery) throws -> NSRegularExpression {
        guard !query.pattern.isEmpty else { throw SearchError.emptyPattern }

        var pattern: String
        if query.isRegularExpression {
            pattern = query.pattern      // regex syntax already has \n, \t, …
        } else {
            let raw = query.usesEscapeSequences ? expandEscapeSequences(query.pattern) : query.pattern
            pattern = NSRegularExpression.escapedPattern(for: raw)
        }

        if query.matchesWholeWords {
            // Lookarounds rather than \b: they also do the right thing when the
            // pattern starts or ends with punctuation.
            pattern = "(?<![\\p{L}\\p{N}_])(?:\(pattern))(?![\\p{L}\\p{N}_])"
        }

        var options: NSRegularExpression.Options = []
        if !query.isCaseSensitive { options.insert(.caseInsensitive) }
        if query.isRegularExpression {
            options.insert(.dotMatchesLineSeparators)
            options.insert(.anchorsMatchLines)
        }

        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw SearchError.invalidPattern(error.localizedDescription)
        }
    }

    // MARK: Searching

    public static func matches(of query: SearchQuery,
                               in text: String,
                               range: Range<Int>? = nil,
                               limit: Int? = nil) throws -> [SearchMatch] {
        let regex = try regularExpression(for: query)
        return matches(of: regex, in: text, range: range, limit: limit)
    }

    public static func matches(of regex: NSRegularExpression,
                               in text: String,
                               range: Range<Int>? = nil,
                               limit: Int? = nil) -> [SearchMatch] {
        let nsText = text as NSString
        let searchRange = nsRange(range, in: nsText)
        var result = [SearchMatch]()
        regex.enumerateMatches(in: text, options: [], range: searchRange) { match, _, stop in
            guard let match else { return }
            result.append(searchMatch(from: match))
            if let limit, result.count >= limit { stop.pointee = true }
        }
        return result
    }

    /// The Find bar's "volgende"/"vorige": finds the next match from `offset`,
    /// wrapping around when the query asks for it.
    public static func firstMatch(of query: SearchQuery,
                                  in text: String,
                                  from offset: Int,
                                  direction: SearchDirection = .forward) throws -> SearchMatch? {
        let regex = try regularExpression(for: query)
        let nsText = text as NSString
        let length = nsText.length
        let start = min(max(offset, 0), length)

        switch direction {
        case .forward:
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: start, length: length - start)) {
                return searchMatch(from: match)
            }
            guard query.wrapsAround, start > 0 else { return nil }
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: start)) {
                return searchMatch(from: match)
            }
            return nil

        case .backward:
            let before = matches(of: regex, in: text, range: 0..<start)
            if let last = before.last { return last }
            guard query.wrapsAround, start < length else { return nil }
            return matches(of: regex, in: text, range: start..<length).last
        }
    }

    public static func count(of query: SearchQuery, in text: String) throws -> Int {
        try matches(of: query, in: text).count
    }

    // MARK: Replacing

    /// The replacement for a single match, with `$1`-style group references
    /// resolved for regular expression searches.
    public static func replacement(for match: SearchMatch,
                                   query: SearchQuery,
                                   template: String,
                                   in text: String) throws -> String {
        let expanded = query.usesEscapeSequences ? expandEscapeSequences(template) : template
        guard query.isRegularExpression else { return expanded }

        let regex = try regularExpression(for: query)
        let nsText = text as NSString
        let range = NSRange(location: match.range.lowerBound, length: match.range.count)
        guard let nsMatch = regex.firstMatch(in: text, options: [.anchored], range: range) else {
            return expanded
        }
        return regex.replacementString(for: nsMatch, in: text, offset: 0, template: expanded)
    }

    public struct ReplaceAllResult: Equatable, Sendable {
        public let text: String
        public let edits: [TextEdit]
        public var count: Int { edits.count }
    }

    /// Computes every replacement as a list of `TextEdit`s in original
    /// coordinates, so callers can apply them as one undoable group (and so
    /// "replace all" in 40 open tabs stays a pure function until the very end).
    public static func replaceAll(query: SearchQuery,
                                  in text: String,
                                  with template: String,
                                  range: Range<Int>? = nil) throws -> ReplaceAllResult {
        let regex = try regularExpression(for: query)
        let expanded = query.usesEscapeSequences ? expandEscapeSequences(template) : template
        let nsText = text as NSString
        let searchRange = nsRange(range, in: nsText)

        var edits = [TextEdit]()
        var output = nsText.substring(to: searchRange.location)
        var cursor = searchRange.location

        regex.enumerateMatches(in: text, options: [], range: searchRange) { match, _, _ in
            guard let match else { return }
            let replacement = query.isRegularExpression
                ? regex.replacementString(for: match, in: text, offset: 0, template: expanded)
                : expanded
            output += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += replacement
            cursor = match.range.location + match.range.length
            edits.append(TextEdit(range: match.range.location..<cursor, replacement: replacement))
        }
        output += nsText.substring(from: cursor)
        return ReplaceAllResult(text: output, edits: edits)
    }

    // MARK: Helpers

    /// Turns `\n`, `\t`, `\r`, `\0`, `\\` and `\x41`/`A` into the
    /// characters they denote.
    public static func expandEscapeSequences(_ input: String) -> String {
        var result = ""
        var iterator = input.makeIterator()
        var pending = [Character]()

        func next() -> Character? {
            if !pending.isEmpty { return pending.removeFirst() }
            return iterator.next()
        }

        while let character = next() {
            guard character == "\\" else {
                result.append(character)
                continue
            }
            guard let escape = next() else {
                result.append("\\")
                break
            }
            switch escape {
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            case "0": result.append("\0")
            case "\\": result.append("\\")
            case "x", "u":
                let digits = escape == "x" ? 2 : 4
                var hex = ""
                var consumed = [Character]()
                for _ in 0..<digits {
                    guard let digit = next() else { break }
                    consumed.append(digit)
                    guard digit.isHexDigit else { break }
                    hex.append(digit)
                }
                if hex.count == digits, let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) {
                    result.append(Character(scalar))
                } else {
                    result.append("\\")
                    result.append(escape)
                    pending.append(contentsOf: consumed)
                }
            default:
                result.append("\\")
                result.append(escape)
            }
        }
        return result
    }

    private static func nsRange(_ range: Range<Int>?, in text: NSString) -> NSRange {
        guard let range else { return NSRange(location: 0, length: text.length) }
        let lower = min(max(range.lowerBound, 0), text.length)
        let upper = min(max(range.upperBound, lower), text.length)
        return NSRange(location: lower, length: upper - lower)
    }

    private static func searchMatch(from match: NSTextCheckingResult) -> SearchMatch {
        var groups = [Range<Int>?]()
        groups.reserveCapacity(match.numberOfRanges)
        for index in 0..<match.numberOfRanges {
            let range = match.range(at: index)
            groups.append(range.location == NSNotFound ? nil : range.location..<(range.location + range.length))
        }
        return SearchMatch(range: match.range.location..<(match.range.location + match.range.length),
                           captureGroups: groups)
    }
}
