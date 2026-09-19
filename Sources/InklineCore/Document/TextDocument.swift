import Foundation

/// One open file (or unsaved buffer). Owns the text, everything the status bar
/// shows and the per-document state that has to survive a restart.
///
/// No AppKit, no Combine: the app layer wraps this in an `ObservableObject`, the
/// tests drive it directly.
public final class TextDocument {

    public enum ChangeKind: Equatable, Sendable {
        case text(TextChange)
        case metadata          // encoding, line ending, language, indentation
        case dirtyState
        case fileURL
    }

    public let id: UUID
    public let buffer: TextBuffer

    public private(set) var fileURL: URL?
    public private(set) var isDirty = false
    /// Modification date of the file when we last read or wrote it; used to
    /// detect that another program changed it underneath us.
    public private(set) var savedModificationDate: Date?

    public var encoding: TextEncoding { didSet { if encoding != oldValue { markMetadataChanged() } } }
    public var lineEnding: LineEnding { didSet { if lineEnding != oldValue { markMetadataChanged() } } }
    public var languageIdentifier: String? { didSet { if languageIdentifier != oldValue { markMetadataChanged() } } }
    public var indentation: IndentationSettings { didSet { if indentation != oldValue { markMetadataChanged() } } }

    public var bookmarks = BookmarkSet()
    public var folding = FoldingState()
    /// Untitled documents get a stable number so the tab reads "Naamloos 3".
    public let untitledNumber: Int?
    public var hasMixedLineEndings = false
    public var isReadOnly = false
    public var byteCountOnDisk: Int?

    private var observers: [Int: (TextDocument, ChangeKind) -> Void] = [:]
    private var nextObserverID = 0
    private var bufferToken: TextBuffer.ObserverToken?

    // MARK: Creation

    public init(id: UUID = UUID(),
                text: String = "",
                fileURL: URL? = nil,
                encoding: TextEncoding = .utf8,
                lineEnding: LineEnding = .lf,
                languageIdentifier: String? = nil,
                indentation: IndentationSettings = .default,
                untitledNumber: Int? = nil) {
        self.id = id
        self.buffer = TextBuffer(text: text)
        self.fileURL = fileURL
        self.encoding = encoding
        self.lineEnding = lineEnding
        self.languageIdentifier = languageIdentifier
        self.indentation = indentation
        self.untitledNumber = untitledNumber

        bufferToken = buffer.addObserver { [weak self] change in
            guard let self else { return }
            self.bookmarks.adjust(for: change, startLine: self.buffer.lineNumber(at: change.editedRange.lowerBound))
            if !self.isDirty {
                self.isDirty = true
                self.notify(.dirtyState)
            }
            self.notify(.text(change))
        }
    }

    public static func open(contentsOf url: URL,
                            forcedEncoding: TextEncoding? = nil,
                            indentation: IndentationSettings = .default) throws -> TextDocument {
        let loaded = try FileLoader.load(contentsOf: url, forcedEncoding: forcedEncoding)
        let document = TextDocument(text: loaded.text,
                                    fileURL: url,
                                    encoding: loaded.encoding,
                                    lineEnding: loaded.lineEnding,
                                    indentation: indentation)
        document.isDirty = false
        document.savedModificationDate = loaded.modificationDate
        document.hasMixedLineEndings = loaded.hasMixedLineEndings
        document.byteCountOnDisk = loaded.byteCount
        return document
    }

    // MARK: Observation

    @discardableResult
    public func addObserver(_ handler: @escaping (TextDocument, ChangeKind) -> Void) -> Int {
        nextObserverID += 1
        observers[nextObserverID] = handler
        return nextObserverID
    }

    public func removeObserver(_ token: Int) {
        observers.removeValue(forKey: token)
    }

    private func notify(_ kind: ChangeKind) {
        for handler in observers.values { handler(self, kind) }
    }

    private func markMetadataChanged() {
        notify(.metadata)
    }

    // MARK: Naming

    public var displayName: String {
        if let fileURL { return fileURL.lastPathComponent }
        if let untitledNumber { return "Naamloos \(untitledNumber)" }
        return "Naamloos"
    }

    public var directoryDescription: String? {
        fileURL?.deletingLastPathComponent().path
    }

    public var isUntitled: Bool { fileURL == nil }

    // MARK: Saving

    public func save(to url: URL? = nil, options: SaveOptions = .default) throws {
        guard let target = url ?? fileURL else { throw DocumentError.noDestination }
        try FileLoader.write(buffer.text,
                             to: target,
                             encoding: encoding,
                             lineEnding: lineEnding,
                             options: options)
        if options.trimTrailingWhitespace || options.ensureTrailingNewline {
            // Keep the buffer in step with what actually landed on disk.
            let reloaded = try FileLoader.load(contentsOf: target, forcedEncoding: encoding)
            if reloaded.text != buffer.text {
                let selections = buffer.selections
                buffer.replace(0..<buffer.length, with: reloaded.text)
                buffer.selections = selections.map { $0.clamped(to: buffer.length) }
            }
        }
        if fileURL != target {
            fileURL = target
            notify(.fileURL)
        }
        savedModificationDate = FileLoader.modificationDate(of: target)
        byteCountOnDisk = FileLoader.byteCount(of: target)
        isDirty = false
        notify(.dirtyState)
    }

    public func reloadFromDisk(forcedEncoding: TextEncoding? = nil) throws {
        guard let fileURL else { throw DocumentError.noDestination }
        let loaded = try FileLoader.load(contentsOf: fileURL, forcedEncoding: forcedEncoding)
        buffer.reset(to: loaded.text)
        encoding = loaded.encoding
        lineEnding = loaded.lineEnding
        hasMixedLineEndings = loaded.hasMixedLineEndings
        savedModificationDate = loaded.modificationDate
        byteCountOnDisk = loaded.byteCount
        isDirty = false
        notify(.dirtyState)
    }

    /// True when the file on disk changed after we last read or wrote it.
    public var hasExternalChanges: Bool {
        guard let fileURL, let savedModificationDate else { return false }
        guard let current = FileLoader.modificationDate(of: fileURL) else { return false }
        return current > savedModificationDate
    }

    /// Re-encodes the text in a different encoding (the "Converteren naar…"
    /// menu). The bytes only change on the next save, which matches the
    /// expectation that converting is undoable by not saving.
    public func convert(to newEncoding: TextEncoding) {
        encoding = newEncoding
        isDirty = true
        notify(.dirtyState)
    }

    public func convert(to newLineEnding: LineEnding) {
        lineEnding = newLineEnding
        hasMixedLineEndings = false
        isDirty = true
        notify(.dirtyState)
    }

    public func markDirty() {
        guard !isDirty else { return }
        isDirty = true
        notify(.dirtyState)
    }

    // MARK: Statistics for the status bar

    public struct Statistics: Equatable, Sendable {
        public let characters: Int
        public let lines: Int
        public let selectedCharacters: Int
        public let selectedLines: Int
        public let selectionCount: Int
    }

    public func statistics() -> Statistics {
        let selections = buffer.selections
        let selected = selections.reduce(0) { $0 + $1.length }
        let selectedLines = selections.reduce(0) { total, selection in
            guard !selection.isCaret else { return total }
            let first = buffer.lineNumber(at: selection.range.lowerBound)
            let last = buffer.lineNumber(at: selection.range.upperBound)
            return total + (last - first + 1)
        }
        return Statistics(characters: buffer.length,
                          lines: buffer.lineCount,
                          selectedCharacters: selected,
                          selectedLines: selectedLines,
                          selectionCount: selections.count)
    }
}

public enum DocumentError: LocalizedError, Equatable {
    case noDestination
    case fileChangedOnDisk

    public var errorDescription: String? {
        switch self {
        case .noDestination: return "Dit document heeft nog geen locatie op schijf."
        case .fileChangedOnDisk: return "Het bestand is buiten Inkline gewijzigd."
        }
    }
}
