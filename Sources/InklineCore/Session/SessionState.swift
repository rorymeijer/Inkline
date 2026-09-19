import Foundation

/// Everything needed to put a tab back exactly where it was.
public struct SessionDocumentState: Codable, Equatable, Sendable {
    public var fileBookmark: Data?        // security-scoped bookmark, when available
    public var filePath: String?
    /// File name of the scratch copy that holds the text of an unsaved
    /// document, relative to the session directory.
    public var scratchFileName: String?
    public var displayName: String
    public var selections: [TextSelection]
    public var scrollOffset: Double
    public var encoding: TextEncoding
    public var lineEnding: LineEnding
    public var languageIdentifier: String?
    public var indentation: IndentationSettings
    public var bookmarkedLines: [Int]
    public var isPinned: Bool

    public init(fileBookmark: Data? = nil,
                filePath: String? = nil,
                scratchFileName: String? = nil,
                displayName: String = "Naamloos",
                selections: [TextSelection] = [TextSelection(caret: 0)],
                scrollOffset: Double = 0,
                encoding: TextEncoding = .utf8,
                lineEnding: LineEnding = .lf,
                languageIdentifier: String? = nil,
                indentation: IndentationSettings = .default,
                bookmarkedLines: [Int] = [],
                isPinned: Bool = false) {
        self.fileBookmark = fileBookmark
        self.filePath = filePath
        self.scratchFileName = scratchFileName
        self.displayName = displayName
        self.selections = selections
        self.scrollOffset = scrollOffset
        self.encoding = encoding
        self.lineEnding = lineEnding
        self.languageIdentifier = languageIdentifier
        self.indentation = indentation
        self.bookmarkedLines = bookmarkedLines
        self.isPinned = isPinned
    }

    public var url: URL? {
        filePath.map { URL(fileURLWithPath: $0) }
    }
}

public enum SplitOrientation: String, Codable, CaseIterable, Sendable {
    case none
    case horizontal      // panes side by side
    case vertical        // panes above each other
}

public struct SessionPaneState: Codable, Equatable, Sendable {
    public var documents: [SessionDocumentState]
    public var activeIndex: Int

    public init(documents: [SessionDocumentState] = [], activeIndex: Int = 0) {
        self.documents = documents
        self.activeIndex = activeIndex
    }
}

/// A named session: a set of tabs, the split layout and the folders shown in
/// the file explorer.
public struct SessionState: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var panes: [SessionPaneState]
    public var activePaneIndex: Int
    public var splitOrientation: SplitOrientation
    public var synchronizedScrolling: Bool
    public var explorerRoots: [String]
    public var savedAt: Date

    public init(id: UUID = UUID(),
                name: String = "Automatisch",
                panes: [SessionPaneState] = [SessionPaneState()],
                activePaneIndex: Int = 0,
                splitOrientation: SplitOrientation = .none,
                synchronizedScrolling: Bool = false,
                explorerRoots: [String] = [],
                savedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.panes = panes
        self.activePaneIndex = activePaneIndex
        self.splitOrientation = splitOrientation
        self.synchronizedScrolling = synchronizedScrolling
        self.explorerRoots = explorerRoots
        self.savedAt = savedAt
    }

    public var documentCount: Int { panes.reduce(0) { $0 + $1.documents.count } }
}
