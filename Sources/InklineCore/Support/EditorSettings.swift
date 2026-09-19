import Foundation

/// User preferences that affect the editor core and the views alike. One
/// Codable value so it round-trips through `UserDefaults` as a single JSON blob
/// and can be exported.
public struct EditorSettings: Codable, Equatable, Sendable {

    // Typography
    public var fontName: String
    public var fontSize: Double
    public var lineHeightMultiple: Double

    // Layout
    public var showsLineNumbers: Bool
    public var showsIndentGuides: Bool
    public var highlightsCurrentLine: Bool
    public var showsInvisibleCharacters: Bool
    public var wrapsLines: Bool
    public var showsPageGuide: Bool
    public var pageGuideColumn: Int
    public var showsFoldingRibbon: Bool

    // Editing
    public var indentation: IndentationSettings
    public var autoIndents: Bool
    public var autoClosesBrackets: Bool
    public var autoClosesQuotes: Bool
    public var highlightsMatchingBracket: Bool
    public var highlightsSelectionOccurrences: Bool

    // Completion
    public var completionEnabled: Bool
    public var completionMinimumPrefixLength: Int
    public var completionIncludesKeywords: Bool

    // Saving
    public var saveOptions: SaveOptions
    public var defaultEncoding: TextEncoding
    public var defaultLineEnding: LineEnding
    public var createsBackupOnSave: Bool

    // Session
    public var restoresSessionOnLaunch: Bool
    public var reopensLastFolder: Bool
    public var maximumRecentFiles: Int

    // Themes
    public var lightThemeIdentifier: String
    public var darkThemeIdentifier: String
    public var followsSystemAppearance: Bool

    // Updates (Sparkle)
    public var checksForUpdatesAutomatically: Bool
    public var downloadsUpdatesAutomatically: Bool

    public init(fontName: String = "SF Mono",
                fontSize: Double = 13,
                lineHeightMultiple: Double = 1.2,
                showsLineNumbers: Bool = true,
                showsIndentGuides: Bool = true,
                highlightsCurrentLine: Bool = true,
                showsInvisibleCharacters: Bool = false,
                wrapsLines: Bool = false,
                showsPageGuide: Bool = false,
                pageGuideColumn: Int = 100,
                showsFoldingRibbon: Bool = true,
                indentation: IndentationSettings = .default,
                autoIndents: Bool = true,
                autoClosesBrackets: Bool = true,
                autoClosesQuotes: Bool = true,
                highlightsMatchingBracket: Bool = true,
                highlightsSelectionOccurrences: Bool = true,
                completionEnabled: Bool = true,
                completionMinimumPrefixLength: Int = 2,
                completionIncludesKeywords: Bool = true,
                saveOptions: SaveOptions = .default,
                defaultEncoding: TextEncoding = .utf8,
                defaultLineEnding: LineEnding = .lf,
                createsBackupOnSave: Bool = false,
                restoresSessionOnLaunch: Bool = true,
                reopensLastFolder: Bool = true,
                maximumRecentFiles: Int = 20,
                lightThemeIdentifier: String = "inkline-light",
                darkThemeIdentifier: String = "inkline-dark",
                followsSystemAppearance: Bool = true,
                checksForUpdatesAutomatically: Bool = true,
                downloadsUpdatesAutomatically: Bool = false) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.lineHeightMultiple = lineHeightMultiple
        self.showsLineNumbers = showsLineNumbers
        self.showsIndentGuides = showsIndentGuides
        self.highlightsCurrentLine = highlightsCurrentLine
        self.showsInvisibleCharacters = showsInvisibleCharacters
        self.wrapsLines = wrapsLines
        self.showsPageGuide = showsPageGuide
        self.pageGuideColumn = pageGuideColumn
        self.showsFoldingRibbon = showsFoldingRibbon
        self.indentation = indentation
        self.autoIndents = autoIndents
        self.autoClosesBrackets = autoClosesBrackets
        self.autoClosesQuotes = autoClosesQuotes
        self.highlightsMatchingBracket = highlightsMatchingBracket
        self.highlightsSelectionOccurrences = highlightsSelectionOccurrences
        self.completionEnabled = completionEnabled
        self.completionMinimumPrefixLength = completionMinimumPrefixLength
        self.completionIncludesKeywords = completionIncludesKeywords
        self.saveOptions = saveOptions
        self.defaultEncoding = defaultEncoding
        self.defaultLineEnding = defaultLineEnding
        self.createsBackupOnSave = createsBackupOnSave
        self.restoresSessionOnLaunch = restoresSessionOnLaunch
        self.reopensLastFolder = reopensLastFolder
        self.maximumRecentFiles = maximumRecentFiles
        self.lightThemeIdentifier = lightThemeIdentifier
        self.darkThemeIdentifier = darkThemeIdentifier
        self.followsSystemAppearance = followsSystemAppearance
        self.checksForUpdatesAutomatically = checksForUpdatesAutomatically
        self.downloadsUpdatesAutomatically = downloadsUpdatesAutomatically
    }

    public static let `default` = EditorSettings()

    /// Decoding tolerates missing keys so a settings file written by an older
    /// build keeps working after an update.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = EditorSettings.default
        func value<T: Decodable>(_ key: CodingKeys, _ defaultValue: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? defaultValue
        }
        fontName = value(.fontName, fallback.fontName)
        fontSize = value(.fontSize, fallback.fontSize)
        lineHeightMultiple = value(.lineHeightMultiple, fallback.lineHeightMultiple)
        showsLineNumbers = value(.showsLineNumbers, fallback.showsLineNumbers)
        showsIndentGuides = value(.showsIndentGuides, fallback.showsIndentGuides)
        highlightsCurrentLine = value(.highlightsCurrentLine, fallback.highlightsCurrentLine)
        showsInvisibleCharacters = value(.showsInvisibleCharacters, fallback.showsInvisibleCharacters)
        wrapsLines = value(.wrapsLines, fallback.wrapsLines)
        showsPageGuide = value(.showsPageGuide, fallback.showsPageGuide)
        pageGuideColumn = value(.pageGuideColumn, fallback.pageGuideColumn)
        showsFoldingRibbon = value(.showsFoldingRibbon, fallback.showsFoldingRibbon)
        indentation = value(.indentation, fallback.indentation)
        autoIndents = value(.autoIndents, fallback.autoIndents)
        autoClosesBrackets = value(.autoClosesBrackets, fallback.autoClosesBrackets)
        autoClosesQuotes = value(.autoClosesQuotes, fallback.autoClosesQuotes)
        highlightsMatchingBracket = value(.highlightsMatchingBracket, fallback.highlightsMatchingBracket)
        highlightsSelectionOccurrences = value(.highlightsSelectionOccurrences, fallback.highlightsSelectionOccurrences)
        completionEnabled = value(.completionEnabled, fallback.completionEnabled)
        completionMinimumPrefixLength = value(.completionMinimumPrefixLength, fallback.completionMinimumPrefixLength)
        completionIncludesKeywords = value(.completionIncludesKeywords, fallback.completionIncludesKeywords)
        saveOptions = value(.saveOptions, fallback.saveOptions)
        defaultEncoding = value(.defaultEncoding, fallback.defaultEncoding)
        defaultLineEnding = value(.defaultLineEnding, fallback.defaultLineEnding)
        createsBackupOnSave = value(.createsBackupOnSave, fallback.createsBackupOnSave)
        restoresSessionOnLaunch = value(.restoresSessionOnLaunch, fallback.restoresSessionOnLaunch)
        reopensLastFolder = value(.reopensLastFolder, fallback.reopensLastFolder)
        maximumRecentFiles = value(.maximumRecentFiles, fallback.maximumRecentFiles)
        lightThemeIdentifier = value(.lightThemeIdentifier, fallback.lightThemeIdentifier)
        darkThemeIdentifier = value(.darkThemeIdentifier, fallback.darkThemeIdentifier)
        followsSystemAppearance = value(.followsSystemAppearance, fallback.followsSystemAppearance)
        checksForUpdatesAutomatically = value(.checksForUpdatesAutomatically, fallback.checksForUpdatesAutomatically)
        downloadsUpdatesAutomatically = value(.downloadsUpdatesAutomatically, fallback.downloadsUpdatesAutomatically)
    }
}
