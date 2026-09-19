import Foundation

/// An sRGB colour, stored as components so the model stays free of AppKit.
/// Parsed from `#RRGGBB`, `#RRGGBBAA` or `#RGB`.
public struct ThemeColor: Codable, Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        if value.count == 6 {
            red = Double((number >> 16) & 0xFF) / 255
            green = Double((number >> 8) & 0xFF) / 255
            blue = Double(number & 0xFF) / 255
            alpha = 1
        } else {
            red = Double((number >> 24) & 0xFF) / 255
            green = Double((number >> 16) & 0xFF) / 255
            blue = Double((number >> 8) & 0xFF) / 255
            alpha = Double(number & 0xFF) / 255
        }
    }

    public var hexString: String {
        let components = [red, green, blue].map { Int(($0 * 255).rounded()) }
        let body = components.map { String(format: "%02X", $0) }.joined()
        return alpha >= 1 ? "#\(body)" : "#\(body)\(String(format: "%02X", Int((alpha * 255).rounded())))"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hex = try container.decode(String.self)
        guard let color = ThemeColor(hex: hex) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ongeldige kleur: \(hex)")
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }

    public func withAlpha(_ newAlpha: Double) -> ThemeColor {
        ThemeColor(red: red, green: green, blue: blue, alpha: newAlpha)
    }

    public static let black = ThemeColor(red: 0, green: 0, blue: 0)
    public static let white = ThemeColor(red: 1, green: 1, blue: 1)
}

public struct ScopeStyle: Codable, Equatable, Sendable {
    public var color: ThemeColor?
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool

    public init(color: ThemeColor? = nil, bold: Bool = false, italic: Bool = false, underline: Bool = false) {
        self.color = color
        self.bold = bold
        self.italic = italic
        self.underline = underline
    }

    public init(from decoder: Decoder) throws {
        // Accept both `"keyword": "#C678DD"` and the full object form.
        if let single = try? decoder.singleValueContainer(), let hex = try? single.decode(String.self) {
            color = ThemeColor(hex: hex)
            bold = false
            italic = false
            underline = false
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(ThemeColor.self, forKey: .color)
        bold = try container.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try container.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        underline = try container.decodeIfPresent(Bool.self, forKey: .underline) ?? false
    }
}

/// Colours for everything that is not syntax: chrome, gutter, selection,
/// search highlights, diff rows.
public struct EditorColors: Codable, Equatable, Sendable {
    public var background: ThemeColor
    public var foreground: ThemeColor
    public var caret: ThemeColor
    public var selection: ThemeColor
    public var inactiveSelection: ThemeColor
    public var currentLine: ThemeColor
    public var gutterBackground: ThemeColor
    public var lineNumber: ThemeColor
    public var activeLineNumber: ThemeColor
    public var indentGuide: ThemeColor
    public var invisibles: ThemeColor
    public var findHighlight: ThemeColor
    public var currentFindHighlight: ThemeColor
    public var bracketMatch: ThemeColor
    public var pageGuide: ThemeColor
    public var diffInserted: ThemeColor
    public var diffDeleted: ThemeColor
    public var bookmark: ThemeColor

    public init(background: ThemeColor,
                foreground: ThemeColor,
                caret: ThemeColor,
                selection: ThemeColor,
                inactiveSelection: ThemeColor,
                currentLine: ThemeColor,
                gutterBackground: ThemeColor,
                lineNumber: ThemeColor,
                activeLineNumber: ThemeColor,
                indentGuide: ThemeColor,
                invisibles: ThemeColor,
                findHighlight: ThemeColor,
                currentFindHighlight: ThemeColor,
                bracketMatch: ThemeColor,
                pageGuide: ThemeColor,
                diffInserted: ThemeColor,
                diffDeleted: ThemeColor,
                bookmark: ThemeColor) {
        self.background = background
        self.foreground = foreground
        self.caret = caret
        self.selection = selection
        self.inactiveSelection = inactiveSelection
        self.currentLine = currentLine
        self.gutterBackground = gutterBackground
        self.lineNumber = lineNumber
        self.activeLineNumber = activeLineNumber
        self.indentGuide = indentGuide
        self.invisibles = invisibles
        self.findHighlight = findHighlight
        self.currentFindHighlight = currentFindHighlight
        self.bracketMatch = bracketMatch
        self.pageGuide = pageGuide
        self.diffInserted = diffInserted
        self.diffDeleted = diffDeleted
        self.bookmark = bookmark
    }
}

public struct Theme: Codable, Equatable, Identifiable, Sendable {

    public enum Appearance: String, Codable, Sendable {
        case light
        case dark
    }

    public var identifier: String
    public var name: String
    public var appearance: Appearance
    public var colors: EditorColors
    public var scopes: [String: ScopeStyle]

    public var id: String { identifier }

    public init(identifier: String,
                name: String,
                appearance: Appearance,
                colors: EditorColors,
                scopes: [String: ScopeStyle]) {
        self.identifier = identifier
        self.name = name
        self.appearance = appearance
        self.colors = colors
        self.scopes = scopes
    }

    public func style(for scope: HighlightScope) -> ScopeStyle? {
        if let exact = scopes[scope.rawValue] { return exact }
        // Fall back along the obvious family lines so a minimal theme that only
        // defines `keyword` still colours `controlKeyword`.
        switch scope {
        case .controlKeyword, .storage: return scopes[HighlightScope.keyword.rawValue]
        case .documentationComment: return scopes[HighlightScope.comment.rawValue]
        case .method: return scopes[HighlightScope.function.rawValue]
        case .character, .escapeSequence, .regularExpression: return scopes[HighlightScope.string.rawValue]
        case .property, .parameter: return scopes[HighlightScope.variable.rawValue]
        case .tagAttribute: return scopes[HighlightScope.attribute.rawValue]
        default: return nil
        }
    }

    public func color(for scope: HighlightScope) -> ThemeColor {
        style(for: scope)?.color ?? colors.foreground
    }
}
