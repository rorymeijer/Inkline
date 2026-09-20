import Foundation

/// Themes are data too: JSON files in the bundle and in
/// `~/Library/Application Support/Inkline/Themes`.
public final class ThemeRegistry {

    public private(set) var themes: [Theme] = []
    public var onChange: (() -> Void)?

    private var byIdentifier: [String: Theme] = [:]

    public init(themes: [Theme] = []) {
        register(contentsOf: themes)
    }

    @discardableResult
    public func loadThemes(in directory: URL) -> [LanguageLoadIssue] {
        var issues = [LanguageLoadIssue]()
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                 includingPropertiesForKeys: nil)) ?? []
        var loaded = [Theme]()
        for url in urls where url.pathExtension.lowercased() == "json" {
            do {
                loaded.append(try JSONDecoder().decode(Theme.self, from: try Data(contentsOf: url)))
            } catch {
                issues.append(LanguageLoadIssue(url: url, message: error.localizedDescription))
            }
        }
        register(contentsOf: loaded)
        return issues
    }

    public func register(contentsOf newThemes: [Theme]) {
        for theme in newThemes { byIdentifier[theme.identifier] = theme }
        themes = byIdentifier.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        onChange?()
    }

    public func theme(withIdentifier identifier: String) -> Theme? {
        byIdentifier[identifier]
    }

    public func themes(for appearance: Theme.Appearance) -> [Theme] {
        themes.filter { $0.appearance == appearance }
    }

    /// Never fails: falls back to the built-in theme for the appearance so the
    /// editor always has colours, even with an empty Themes directory.
    public func theme(withIdentifier identifier: String, appearance: Theme.Appearance) -> Theme {
        theme(withIdentifier: identifier)
            ?? themes(for: appearance).first
            ?? (appearance == .dark ? Theme.builtInDark : Theme.builtInLight)
    }

    /// `nil` betekent de eigen modulebundel; `.module` is internal en mag
    /// daarom geen default argument van een publieke functie zijn.
    public static func standard(bundle: Bundle? = nil, userDirectory: URL? = nil) -> ThemeRegistry {
        let registry = ThemeRegistry(themes: [.builtInLight, .builtInDark])
        let bundle = bundle ?? .module
        if let directory = bundle.url(forResource: "Themes", withExtension: nil) {
            registry.loadThemes(in: directory)
        }
        if let userDirectory {
            registry.loadThemes(in: userDirectory)
        }
        return registry
    }
}

extension Theme {
    /// Compiled-in fallbacks. They are identical to the bundled JSON files, but
    /// having them in code means a corrupted resource directory degrades to
    /// "looks right" instead of "unreadable".
    public static let builtInLight = Theme(
        identifier: "inkline-light",
        name: "Inkline Licht",
        appearance: .light,
        colors: EditorColors(background: ThemeColor(hex: "#FFFFFF")!,
                             foreground: ThemeColor(hex: "#1D1D1F")!,
                             caret: ThemeColor(hex: "#1D1D1F")!,
                             selection: ThemeColor(hex: "#B3D7FF")!,
                             inactiveSelection: ThemeColor(hex: "#DCDCDC")!,
                             currentLine: ThemeColor(hex: "#F2F5FA")!,
                             gutterBackground: ThemeColor(hex: "#FAFAFA")!,
                             lineNumber: ThemeColor(hex: "#A0A0A5")!,
                             activeLineNumber: ThemeColor(hex: "#1D1D1F")!,
                             indentGuide: ThemeColor(hex: "#E4E4E8")!,
                             invisibles: ThemeColor(hex: "#C8C8CC")!,
                             findHighlight: ThemeColor(hex: "#FFE9A8")!,
                             currentFindHighlight: ThemeColor(hex: "#FFC64D")!,
                             bracketMatch: ThemeColor(hex: "#D5E8FF")!,
                             pageGuide: ThemeColor(hex: "#EDEDF0")!,
                             diffInserted: ThemeColor(hex: "#E4F7E7")!,
                             diffDeleted: ThemeColor(hex: "#FCE8E8")!,
                             bookmark: ThemeColor(hex: "#3E7BFA")!),
        scopes: [
            "comment": ScopeStyle(color: ThemeColor(hex: "#6E7781"), italic: true),
            "documentationComment": ScopeStyle(color: ThemeColor(hex: "#4B7A5E"), italic: true),
            "keyword": ScopeStyle(color: ThemeColor(hex: "#9B2393"), bold: false),
            "controlKeyword": ScopeStyle(color: ThemeColor(hex: "#9B2393")),
            "storage": ScopeStyle(color: ThemeColor(hex: "#9B2393")),
            "type": ScopeStyle(color: ThemeColor(hex: "#0F6FC5")),
            "constant": ScopeStyle(color: ThemeColor(hex: "#1C6B48")),
            "number": ScopeStyle(color: ThemeColor(hex: "#1C6B48")),
            "string": ScopeStyle(color: ThemeColor(hex: "#C41A16")),
            "escapeSequence": ScopeStyle(color: ThemeColor(hex: "#8B3A2F")),
            "regularExpression": ScopeStyle(color: ThemeColor(hex: "#B33E1E")),
            "function": ScopeStyle(color: ThemeColor(hex: "#3E4CAB")),
            "property": ScopeStyle(color: ThemeColor(hex: "#326D74")),
            "variable": ScopeStyle(color: ThemeColor(hex: "#1D1D1F")),
            "operator": ScopeStyle(color: ThemeColor(hex: "#4A4A50")),
            "punctuation": ScopeStyle(color: ThemeColor(hex: "#6E6E73")),
            "attribute": ScopeStyle(color: ThemeColor(hex: "#805B1F")),
            "tag": ScopeStyle(color: ThemeColor(hex: "#9B2393")),
            "tagAttribute": ScopeStyle(color: ThemeColor(hex: "#805B1F")),
            "heading": ScopeStyle(color: ThemeColor(hex: "#0F6FC5"), bold: true),
            "emphasis": ScopeStyle(color: nil, italic: true),
            "strong": ScopeStyle(color: nil, bold: true),
            "link": ScopeStyle(color: ThemeColor(hex: "#0B63C5"), underline: true),
            "listMarker": ScopeStyle(color: ThemeColor(hex: "#9B2393")),
            "preprocessor": ScopeStyle(color: ThemeColor(hex: "#78492A")),
            "error": ScopeStyle(color: ThemeColor(hex: "#D01919"), underline: true)
        ])

    public static let builtInDark = Theme(
        identifier: "inkline-dark",
        name: "Inkline Donker",
        appearance: .dark,
        colors: EditorColors(background: ThemeColor(hex: "#1E1F22")!,
                             foreground: ThemeColor(hex: "#E8E8ED")!,
                             caret: ThemeColor(hex: "#FFFFFF")!,
                             selection: ThemeColor(hex: "#2F5C8F")!,
                             inactiveSelection: ThemeColor(hex: "#3A3A40")!,
                             currentLine: ThemeColor(hex: "#26282C")!,
                             gutterBackground: ThemeColor(hex: "#1A1B1E")!,
                             lineNumber: ThemeColor(hex: "#5E6068")!,
                             activeLineNumber: ThemeColor(hex: "#E8E8ED")!,
                             indentGuide: ThemeColor(hex: "#33353A")!,
                             invisibles: ThemeColor(hex: "#44464C")!,
                             findHighlight: ThemeColor(hex: "#6B5A1F")!,
                             currentFindHighlight: ThemeColor(hex: "#A6851F")!,
                             bracketMatch: ThemeColor(hex: "#3A4D66")!,
                             pageGuide: ThemeColor(hex: "#2A2C31")!,
                             diffInserted: ThemeColor(hex: "#1E3225")!,
                             diffDeleted: ThemeColor(hex: "#3A2224")!,
                             bookmark: ThemeColor(hex: "#6699FF")!),
        scopes: [
            "comment": ScopeStyle(color: ThemeColor(hex: "#7F848E"), italic: true),
            "documentationComment": ScopeStyle(color: ThemeColor(hex: "#8FA88F"), italic: true),
            "keyword": ScopeStyle(color: ThemeColor(hex: "#C678DD")),
            "controlKeyword": ScopeStyle(color: ThemeColor(hex: "#C678DD")),
            "storage": ScopeStyle(color: ThemeColor(hex: "#C678DD")),
            "type": ScopeStyle(color: ThemeColor(hex: "#E5C07B")),
            "constant": ScopeStyle(color: ThemeColor(hex: "#D19A66")),
            "number": ScopeStyle(color: ThemeColor(hex: "#D19A66")),
            "string": ScopeStyle(color: ThemeColor(hex: "#98C379")),
            "escapeSequence": ScopeStyle(color: ThemeColor(hex: "#56B6C2")),
            "regularExpression": ScopeStyle(color: ThemeColor(hex: "#56B6C2")),
            "function": ScopeStyle(color: ThemeColor(hex: "#61AFEF")),
            "property": ScopeStyle(color: ThemeColor(hex: "#E06C75")),
            "variable": ScopeStyle(color: ThemeColor(hex: "#E8E8ED")),
            "operator": ScopeStyle(color: ThemeColor(hex: "#ABB2BF")),
            "punctuation": ScopeStyle(color: ThemeColor(hex: "#9196A1")),
            "attribute": ScopeStyle(color: ThemeColor(hex: "#E5C07B")),
            "tag": ScopeStyle(color: ThemeColor(hex: "#E06C75")),
            "tagAttribute": ScopeStyle(color: ThemeColor(hex: "#D19A66")),
            "heading": ScopeStyle(color: ThemeColor(hex: "#61AFEF"), bold: true),
            "emphasis": ScopeStyle(color: nil, italic: true),
            "strong": ScopeStyle(color: nil, bold: true),
            "link": ScopeStyle(color: ThemeColor(hex: "#61AFEF"), underline: true),
            "listMarker": ScopeStyle(color: ThemeColor(hex: "#C678DD")),
            "preprocessor": ScopeStyle(color: ThemeColor(hex: "#C18A56")),
            "error": ScopeStyle(color: ThemeColor(hex: "#E06C75"), underline: true)
        ])
}
