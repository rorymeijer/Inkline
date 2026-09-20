import AppKit
import InklineCore
import InklineSyntax

/// Bridges the data-driven `Theme` to the AppKit types the views need.
/// Everything here is derived, cached and cheap to rebuild when the theme, the
/// font or the system appearance changes.
struct ThemeStyle: Equatable {

    let theme: Theme
    let font: NSFont
    let boldFont: NSFont
    let italicFont: NSFont
    let lineHeightMultiple: CGFloat

    private var attributesByScope: [HighlightScope: [NSAttributedString.Key: Any]]

    static func == (lhs: ThemeStyle, rhs: ThemeStyle) -> Bool {
        lhs.theme == rhs.theme
            && lhs.font == rhs.font
            && lhs.lineHeightMultiple == rhs.lineHeightMultiple
    }

    init(theme: Theme, fontName: String, fontSize: CGFloat, lineHeightMultiple: CGFloat = 1.2) {
        self.theme = theme
        let base = NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        font = base
        let manager = NSFontManager.shared
        boldFont = manager.convert(base, toHaveTrait: .boldFontMask)
        italicFont = manager.convert(base, toHaveTrait: .italicFontMask)
        self.lineHeightMultiple = lineHeightMultiple

        var table = [HighlightScope: [NSAttributedString.Key: Any]]()
        for scope in HighlightScope.allCases {
            var attributes: [NSAttributedString.Key: Any] = [:]
            let style = theme.style(for: scope)
            attributes[.foregroundColor] = (style?.color).map(ThemeStyle.color) ?? ThemeStyle.color(theme.colors.foreground)
            if style?.bold == true && style?.italic == true {
                attributes[.font] = manager.convert(manager.convert(base, toHaveTrait: .boldFontMask),
                                                    toHaveTrait: .italicFontMask)
            } else if style?.bold == true {
                attributes[.font] = boldFont
            } else if style?.italic == true {
                attributes[.font] = italicFont
            }
            if style?.underline == true {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            table[scope] = attributes
        }
        attributesByScope = table
    }

    static func color(_ color: ThemeColor) -> NSColor {
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    var backgroundColor: NSColor { Self.color(theme.colors.background) }
    var foregroundColor: NSColor { Self.color(theme.colors.foreground) }
    var caretColor: NSColor { Self.color(theme.colors.caret) }
    var selectionColor: NSColor { Self.color(theme.colors.selection) }
    var currentLineColor: NSColor { Self.color(theme.colors.currentLine) }
    var gutterBackgroundColor: NSColor { Self.color(theme.colors.gutterBackground) }
    var lineNumberColor: NSColor { Self.color(theme.colors.lineNumber) }
    var activeLineNumberColor: NSColor { Self.color(theme.colors.activeLineNumber) }
    var indentGuideColor: NSColor { Self.color(theme.colors.indentGuide) }
    var invisiblesColor: NSColor { Self.color(theme.colors.invisibles) }
    var findHighlightColor: NSColor { Self.color(theme.colors.findHighlight) }
    var currentFindHighlightColor: NSColor { Self.color(theme.colors.currentFindHighlight) }
    var bracketMatchColor: NSColor { Self.color(theme.colors.bracketMatch) }
    var pageGuideColor: NSColor { Self.color(theme.colors.pageGuide) }
    var bookmarkColor: NSColor { Self.color(theme.colors.bookmark) }
    var diffInsertedColor: NSColor { Self.color(theme.colors.diffInserted) }
    var diffDeletedColor: NSColor { Self.color(theme.colors.diffDeleted) }

    var isDark: Bool { theme.appearance == .dark }

    func attributes(for scope: HighlightScope) -> [NSAttributedString.Key: Any] {
        attributesByScope[scope] ?? [.foregroundColor: foregroundColor]
    }

    /// Attributes for text that carries no highlight token.
    var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: font,
         .foregroundColor: foregroundColor,
         .paragraphStyle: paragraphStyle(indentWidth: 4, tabWidth: 4, wraps: false)]
    }

    /// One tab stop per `tabWidth` characters, so tabs line up exactly the way
    /// the status bar promises.
    func paragraphStyle(indentWidth: Int, tabWidth: Int, wraps: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        style.lineBreakMode = wraps ? .byWordWrapping : .byClipping
        let advance = " ".size(withAttributes: [.font: font]).width * CGFloat(tabWidth)
        style.defaultTabInterval = advance
        style.tabStops = []
        return style
    }

    var appearance: NSAppearance? {
        NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}
