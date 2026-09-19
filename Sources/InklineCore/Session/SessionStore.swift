import Foundation

/// Reads and writes sessions. Two kinds live side by side:
///
/// * the *autosave* session, rewritten as tabs change so a crash or a restart
///   restores the workspace;
/// * *named* sessions the user saves and loads from the File menu.
///
/// Unsaved buffers are copied into a scratch directory; without that, "restore
/// my tabs" silently loses work, which is the one thing a text editor may not
/// do.
public final class SessionStore {

    public enum StoreError: LocalizedError, Equatable {
        case invalidName

        public var errorDescription: String? {
            switch self {
            case .invalidName: return "Een sessienaam mag niet leeg zijn."
            }
        }
    }

    public let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
        try? fileManager.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: namedDirectory, withIntermediateDirectories: true)
    }

    public var autosaveURL: URL { directory.appendingPathComponent("Autosave.inklinesession") }
    public var scratchDirectory: URL { directory.appendingPathComponent("Scratch", isDirectory: true) }
    public var namedDirectory: URL { directory.appendingPathComponent("Sessions", isDirectory: true) }

    // MARK: Autosave

    public func saveAutosave(_ state: SessionState) throws {
        try write(state, to: autosaveURL)
    }

    public func loadAutosave() -> SessionState? {
        read(from: autosaveURL)
    }

    // MARK: Named sessions

    public func url(forSessionNamed name: String) -> URL {
        namedDirectory.appendingPathComponent(sanitized(name)).appendingPathExtension("inklinesession")
    }

    public func save(_ state: SessionState, named name: String) throws {
        guard !sanitized(name).isEmpty else { throw StoreError.invalidName }
        var copy = state
        copy.name = name
        copy.savedAt = Date()
        try write(copy, to: url(forSessionNamed: name))
    }

    public func load(named name: String) -> SessionState? {
        read(from: url(forSessionNamed: name))
    }

    public func delete(named name: String) throws {
        try fileManager.removeItem(at: url(forSessionNamed: name))
    }

    public func availableSessionNames() -> [String] {
        let contents = (try? fileManager.contentsOfDirectory(at: namedDirectory,
                                                             includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.pathExtension == "inklinesession" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    // MARK: Scratch copies of unsaved documents

    @discardableResult
    public func writeScratch(_ text: String, fileName: String? = nil) throws -> String {
        let name = fileName ?? UUID().uuidString + ".txt"
        let url = scratchDirectory.appendingPathComponent(name)
        try fileManager.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: [.atomic])
        return name
    }

    public func readScratch(_ fileName: String) -> String? {
        let url = scratchDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func removeScratch(_ fileName: String) {
        try? fileManager.removeItem(at: scratchDirectory.appendingPathComponent(fileName))
    }

    /// Deletes scratch files that no stored session references any more.
    public func pruneScratchFiles(keeping states: [SessionState]) {
        let referenced = Set(states.flatMap { state in
            state.panes.flatMap { $0.documents.compactMap(\.scratchFileName) }
        })
        let contents = (try? fileManager.contentsOfDirectory(at: scratchDirectory,
                                                             includingPropertiesForKeys: nil)) ?? []
        for url in contents where !referenced.contains(url.lastPathComponent) {
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: Plumbing

    private func write(_ state: SessionState, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    private func read(from url: URL) -> SessionState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionState.self, from: data)
    }

    private func sanitized(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:\u{0}")
        return name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
