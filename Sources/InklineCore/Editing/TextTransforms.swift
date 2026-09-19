import Foundation

/// The line- and selection-level transformations from the Edit menu. All of
/// them are pure `String -> String` functions: that keeps them trivially
/// testable, macro-recordable and callable from plugins.
public enum TextTransforms {

    // MARK: Case

    public static func uppercased(_ text: String) -> String { text.uppercased() }
    public static func lowercased(_ text: String) -> String { text.lowercased() }

    /// Capitalises the first letter of every word.
    public static func titleCased(_ text: String) -> String {
        var result = ""
        var atWordStart = true
        for character in text {
            if character.isLetter || character.isNumber {
                result.append(atWordStart ? Character(character.uppercased()) : Character(character.lowercased()))
                atWordStart = false
            } else {
                result.append(character)
                atWordStart = true
            }
        }
        return result
    }

    /// Capitalises the first letter of every sentence.
    public static func sentenceCased(_ text: String) -> String {
        var result = ""
        var atSentenceStart = true
        for character in text {
            if character.isLetter {
                result.append(atSentenceStart ? Character(character.uppercased()) : Character(character.lowercased()))
                atSentenceStart = false
            } else {
                result.append(character)
                if character == "." || character == "!" || character == "?" || character == "\n" {
                    atSentenceStart = true
                }
            }
        }
        return result
    }

    public static func invertedCase(_ text: String) -> String {
        String(text.map { character in
            if character.isUppercase { return Character(character.lowercased()) }
            if character.isLowercase { return Character(character.uppercased()) }
            return character
        })
    }

    // MARK: Lines

    public struct SortOptions: Equatable, Sendable {
        public var ascending: Bool
        public var caseSensitive: Bool
        /// Compare embedded numbers numerically ("item9" before "item10").
        public var numeric: Bool
        public var removesDuplicates: Bool
        public var ignoresLeadingWhitespace: Bool

        public init(ascending: Bool = true,
                    caseSensitive: Bool = false,
                    numeric: Bool = false,
                    removesDuplicates: Bool = false,
                    ignoresLeadingWhitespace: Bool = false) {
            self.ascending = ascending
            self.caseSensitive = caseSensitive
            self.numeric = numeric
            self.removesDuplicates = removesDuplicates
            self.ignoresLeadingWhitespace = ignoresLeadingWhitespace
        }

        public static let `default` = SortOptions()
    }

    public static func sortLines(_ text: String, options: SortOptions = .default) -> String {
        let hadTrailingNewline = text.hasSuffix("\n")
        var lines = splitIntoLines(text)

        func key(_ line: String) -> String {
            var value = line
            if options.ignoresLeadingWhitespace {
                value = String(value.drop(while: { $0 == " " || $0 == "\t" }))
            }
            return options.caseSensitive ? value : value.lowercased()
        }

        lines.sort { lhs, rhs in
            let left = key(lhs)
            let right = key(rhs)
            let comparison: ComparisonResult
            if options.numeric {
                comparison = left.compare(right, options: [.numeric])
            } else {
                comparison = left.compare(right)
            }
            if comparison == .orderedSame { return false }
            return options.ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }

        if options.removesDuplicates {
            lines = removeAdjacentDuplicates(lines, caseSensitive: options.caseSensitive)
        }
        return join(lines, trailingNewline: hadTrailingNewline)
    }

    public static func reversedLines(_ text: String) -> String {
        let hadTrailingNewline = text.hasSuffix("\n")
        return join(splitIntoLines(text).reversed(), trailingNewline: hadTrailingNewline)
    }

    /// Removes duplicate lines. `adjacentOnly` mirrors `uniq`; the default
    /// removes every later occurrence, which is what the Edit menu promises.
    public static func removeDuplicateLines(_ text: String,
                                            adjacentOnly: Bool = false,
                                            caseSensitive: Bool = true) -> String {
        let hadTrailingNewline = text.hasSuffix("\n")
        let lines = splitIntoLines(text)
        let result: [String]
        if adjacentOnly {
            result = removeAdjacentDuplicates(lines, caseSensitive: caseSensitive)
        } else {
            var seen = Set<String>()
            result = lines.filter { line in
                seen.insert(caseSensitive ? line : line.lowercased()).inserted
            }
        }
        return join(result, trailingNewline: hadTrailingNewline)
    }

    public static func removeEmptyLines(_ text: String, blankCountsAsEmpty: Bool = true) -> String {
        let hadTrailingNewline = text.hasSuffix("\n")
        let lines = splitIntoLines(text).filter { line in
            blankCountsAsEmpty ? !line.trimmingCharacters(in: .whitespaces).isEmpty : !line.isEmpty
        }
        return join(lines, trailingNewline: hadTrailingNewline)
    }

    public static func joinLines(_ text: String, separator: String = " ") -> String {
        splitIntoLines(text)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }

    /// Hard-wraps every line at `column`, breaking on the last whitespace at
    /// or before the limit and falling back to a hard break for a word that is
    /// longer than the column itself.
    public static func splitLines(_ text: String, at column: Int) -> String {
        guard column > 0 else { return text }
        let hadTrailingNewline = text.hasSuffix("\n")
        var output = [String]()

        for line in splitIntoLines(text) {
            var remainder = Substring(line)
            while remainder.count > column {
                let limit = remainder.index(remainder.startIndex, offsetBy: column)
                var breakIndex: Substring.Index?
                var probe = limit
                while probe > remainder.startIndex {
                    if remainder[probe].isWhitespace {
                        breakIndex = probe
                        break
                    }
                    probe = remainder.index(before: probe)
                }
                let cut = breakIndex ?? limit          // no space: break mid-word
                output.append(String(remainder[remainder.startIndex..<cut]))
                remainder = remainder[cut...]
                while let first = remainder.first, first == " " || first == "\t" {
                    remainder = remainder.dropFirst()
                }
            }
            output.append(String(remainder))
        }
        return join(output, trailingNewline: hadTrailingNewline)
    }

    public static func trimTrailingWhitespace(_ text: String) -> String {
        let hadTrailingNewline = text.hasSuffix("\n")
        let lines = splitIntoLines(text).map { line -> String in
            var result = Substring(line)
            while let last = result.last, last == " " || last == "\t" { result = result.dropLast() }
            return String(result)
        }
        return join(lines, trailingNewline: hadTrailingNewline)
    }

    public static func trimLeadingWhitespace(_ text: String) -> String {
        let hadTrailingNewline = text.hasSuffix("\n")
        let lines = splitIntoLines(text).map { line in
            String(line.drop(while: { $0 == " " || $0 == "\t" }))
        }
        return join(lines, trailingNewline: hadTrailingNewline)
    }

    // MARK: Indentation

    public static func indent(_ text: String, using unit: String) -> String {
        let hadTrailingNewline = text.hasSuffix("\n")
        let lines = splitIntoLines(text).map { $0.isEmpty ? $0 : unit + $0 }
        return join(lines, trailingNewline: hadTrailingNewline)
    }

    public static func outdent(_ text: String, indentWidth: Int) -> String {
        let hadTrailingNewline = text.hasSuffix("\n")
        let lines = splitIntoLines(text).map { line -> String in
            var result = Substring(line)
            if result.first == "\t" {
                return String(result.dropFirst())
            }
            var removed = 0
            while removed < indentWidth, result.first == " " {
                result = result.dropFirst()
                removed += 1
            }
            return String(result)
        }
        return join(lines, trailingNewline: hadTrailingNewline)
    }

    public static func tabsToSpaces(_ text: String, tabWidth: Int) -> String {
        guard tabWidth > 0 else { return text }
        var result = ""
        var column = 0
        for character in text {
            switch character {
            case "\t":
                let spaces = tabWidth - (column % tabWidth)
                result.append(String(repeating: " ", count: spaces))
                column += spaces
            case "\n":
                result.append(character)
                column = 0
            default:
                result.append(character)
                column += 1
            }
        }
        return result
    }

    /// Converts leading space runs into tabs; trailing alignment spaces are
    /// left alone because turning them into tabs changes how the text lines up.
    public static func spacesToTabs(_ text: String, tabWidth: Int) -> String {
        guard tabWidth > 0 else { return text }
        let hadTrailingNewline = text.hasSuffix("\n")
        let lines = splitIntoLines(text).map { line -> String in
            let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
            let rest = line.dropFirst(leading.count)
            var width = 0
            for character in leading {
                width += character == "\t" ? tabWidth - (width % tabWidth) : 1
            }
            let tabs = width / tabWidth
            let spaces = width % tabWidth
            let converted = String(repeating: "\t", count: tabs) + String(repeating: " ", count: spaces)
            return converted + String(rest)
        }
        return join(lines, trailingNewline: hadTrailingNewline)
    }

    // MARK: Encoding helpers

    public static func base64Encoded(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    public static func base64Decoded(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func urlEncoded(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    public static func urlDecoded(_ text: String) -> String? {
        text.removingPercentEncoding
    }

    public static func htmlEncoded(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    public static func htmlDecoded(_ text: String) -> String {
        var result = text
        let named: [(String, String)] = [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
            ("&apos;", "'"), ("&nbsp;", "\u{00A0}")
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Numeric entities, decimal and hexadecimal.
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") {
            let nsResult = result as NSString
            var output = ""
            var cursor = 0
            regex.enumerateMatches(in: result, range: NSRange(location: 0, length: nsResult.length)) { match, _, _ in
                guard let match else { return }
                let isHex = nsResult.substring(with: match.range(at: 1)) == "x"
                let digits = nsResult.substring(with: match.range(at: 2))
                guard let value = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) else { return }
                output += nsResult.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                output.append(Character(scalar))
                cursor = match.range.location + match.range.length
            }
            output += nsResult.substring(from: cursor)
            result = output
        }
        // `&amp;` last so "&amp;lt;" survives a single round trip.
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Shared helpers

    /// Splits on LF, dropping the terminator. A trailing newline does *not*
    /// produce a final empty element; `join(_:trailingNewline:)` puts it back.
    public static func splitIntoLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    static func join<S: Sequence>(_ lines: S, trailingNewline: Bool) -> String where S.Element == String {
        let joined = lines.joined(separator: "\n")
        if trailingNewline && !joined.isEmpty { return joined + "\n" }
        if trailingNewline && joined.isEmpty { return "\n" }
        return joined
    }

    private static func removeAdjacentDuplicates(_ lines: [String], caseSensitive: Bool) -> [String] {
        var result = [String]()
        var previous: String?
        for line in lines {
            let key = caseSensitive ? line : line.lowercased()
            if key != previous { result.append(line) }
            previous = key
        }
        return result
    }
}
