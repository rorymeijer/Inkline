import Foundation

/// The three line terminators Inkline reads, writes and converts between.
/// Inside the buffer text is always LF; conversion happens on load and save so
/// that every offset calculation in the editor stays simple.
public enum LineEnding: String, CaseIterable, Codable, Sendable {
    case lf
    case crlf
    case cr

    public var string: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        }
    }

    /// Short label for the status bar.
    public var displayName: String {
        switch self {
        case .lf: return "LF"
        case .crlf: return "CRLF"
        case .cr: return "CR"
        }
    }

    /// Longer label for menus, e.g. "Windows (CRLF)".
    public var longDisplayName: String {
        switch self {
        case .lf: return "Unix (LF)"
        case .crlf: return "Windows (CRLF)"
        case .cr: return "Klassiek Mac (CR)"
        }
    }

    public static let platformDefault: LineEnding = .lf

    /// Counts of each terminator in `text`.
    public struct Statistics: Equatable, Sendable {
        public var lf = 0
        public var crlf = 0
        public var cr = 0

        public var total: Int { lf + crlf + cr }
        public var isMixed: Bool {
            [lf, crlf, cr].filter { $0 > 0 }.count > 1
        }

        /// The terminator that occurs most often, or `nil` for a file without
        /// any line break at all.
        public var dominant: LineEnding? {
            guard total > 0 else { return nil }
            if crlf >= lf && crlf >= cr { return .crlf }
            if lf >= cr { return .lf }
            return .cr
        }
    }

    public static func statistics(of text: String) -> Statistics {
        var stats = Statistics()
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar?
        while let scalar = pending ?? iterator.next() {
            pending = nil
            if scalar == "\r" {
                if let next = iterator.next() {
                    if next == "\n" {
                        stats.crlf += 1
                    } else {
                        stats.cr += 1
                        pending = next
                    }
                } else {
                    stats.cr += 1
                }
            } else if scalar == "\n" {
                stats.lf += 1
            }
        }
        return stats
    }

    /// Detects the dominant terminator, falling back to LF.
    public static func detect(in text: String) -> LineEnding {
        statistics(of: text).dominant ?? .lf
    }

    /// Converts every terminator in `text` to LF — the canonical buffer form.
    public static func normalize(_ text: String) -> String {
        // Via unicodeScalars: `text.contains("\r")` ziet een CR niet wanneer
        // die met de LF erna één grafeemcluster ("\r\n") vormt.
        guard text.unicodeScalars.contains("\r") else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "\n")
                   .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Converts LF-only text to this terminator.
    public func applied(to normalizedText: String) -> String {
        switch self {
        case .lf: return normalizedText
        case .crlf: return normalizedText.replacingOccurrences(of: "\n", with: "\r\n")
        case .cr: return normalizedText.replacingOccurrences(of: "\n", with: "\r")
        }
    }
}
