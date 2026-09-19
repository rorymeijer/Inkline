import XCTest
@testable import InklineCore

final class TextDocumentTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("inkline-doc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testUntitledDocument() {
        let document = TextDocument(untitledNumber: 2)
        XCTAssertTrue(document.isUntitled)
        XCTAssertEqual(document.displayName, "Naamloos 2")
        XCTAssertFalse(document.isDirty)
    }

    func testEditingMarksDirty() {
        let document = TextDocument(text: "een")
        var dirtyNotifications = 0
        document.addObserver { _, kind in
            if kind == .dirtyState { dirtyNotifications += 1 }
        }
        document.buffer.replace(3..<3, with: " twee")
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(dirtyNotifications, 1, "slechts één melding voor de overgang naar gewijzigd")
    }

    func testSaveAndReload() throws {
        let url = directory.appendingPathComponent("test.txt")
        let document = TextDocument(text: "eerste\n", fileURL: url)
        try document.save()
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "eerste\n")

        try FileLoader.write("van buiten gewijzigd\n", to: url, encoding: .utf8, lineEnding: .lf)
        try document.reloadFromDisk()
        XCTAssertEqual(document.buffer.text, "van buiten gewijzigd\n")
        XCTAssertFalse(document.isDirty)
    }

    func testSaveAsSetsFileURL() throws {
        let document = TextDocument(text: "inhoud", untitledNumber: 1)
        let url = directory.appendingPathComponent("nieuw.txt")
        try document.save(to: url)
        XCTAssertEqual(document.fileURL, url)
        XCTAssertEqual(document.displayName, "nieuw.txt")
    }

    func testSaveWithTrimOption() throws {
        let url = directory.appendingPathComponent("trim.txt")
        let document = TextDocument(text: "een   \ntwee  ", fileURL: url)
        try document.save(options: SaveOptions(trimTrailingWhitespace: true, ensureTrailingNewline: true))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "een\ntwee\n")
        XCTAssertEqual(document.buffer.text, "een\ntwee\n", "de buffer volgt wat er op schijf staat")
    }

    func testOpenDetectsEncodingAndLineEnding() throws {
        let url = directory.appendingPathComponent("crlf.txt")
        try Data("een\r\ntwee\r\n".utf8).write(to: url)
        let document = try TextDocument.open(contentsOf: url)
        XCTAssertEqual(document.lineEnding, .crlf)
        XCTAssertEqual(document.buffer.text, "een\ntwee\n")
        XCTAssertFalse(document.isDirty)
    }

    func testStatistics() {
        let document = TextDocument(text: "een\ntwee\ndrie")
        document.buffer.selections = [TextSelection(anchor: 0, head: 5)]
        let statistics = document.statistics()
        XCTAssertEqual(statistics.characters, 13)
        XCTAssertEqual(statistics.lines, 3)
        XCTAssertEqual(statistics.selectedCharacters, 5)
        XCTAssertEqual(statistics.selectedLines, 2)
    }

    func testBookmarksFollowEdits() {
        let document = TextDocument(text: "een\ntwee\ndrie\n")
        document.bookmarks.add(2)
        document.buffer.replace(0..<0, with: "nul\n")
        XCTAssertEqual(document.bookmarks.sorted, [3], "de bladwijzer schuift mee met zijn regel")
    }

    func testExternalChangeDetection() throws {
        let url = directory.appendingPathComponent("extern.txt")
        try Data("een".utf8).write(to: url)
        let document = try TextDocument.open(contentsOf: url)
        XCTAssertFalse(document.hasExternalChanges)

        Thread.sleep(forTimeInterval: 1.1)      // file dates have one-second resolution
        try Data("twee".utf8).write(to: url)
        XCTAssertTrue(document.hasExternalChanges)
    }
}

final class SessionStoreTests: XCTestCase {

    private var directory: URL!
    private var store: SessionStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("inkline-session-\(UUID().uuidString)")
        store = SessionStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeState(name: String) -> SessionState {
        let document = SessionDocumentState(filePath: "/tmp/een.txt",
                                            displayName: "een.txt",
                                            selections: [TextSelection(anchor: 4, head: 9)],
                                            scrollOffset: 120,
                                            encoding: .utf8BOM,
                                            lineEnding: .crlf,
                                            languageIdentifier: "swift",
                                            bookmarkedLines: [3, 7])
        return SessionState(name: name,
                            panes: [SessionPaneState(documents: [document], activeIndex: 0)],
                            splitOrientation: .horizontal,
                            explorerRoots: ["/tmp"])
    }

    func testAutosaveRoundTrip() throws {
        try store.saveAutosave(makeState(name: "Automatisch"))
        let loaded = try XCTUnwrap(store.loadAutosave())
        XCTAssertEqual(loaded.panes.first?.documents.first?.displayName, "een.txt")
        XCTAssertEqual(loaded.panes.first?.documents.first?.selections.first?.head, 9)
        XCTAssertEqual(loaded.panes.first?.documents.first?.encoding, .utf8BOM)
        XCTAssertEqual(loaded.splitOrientation, .horizontal)
        XCTAssertEqual(loaded.explorerRoots, ["/tmp"])
    }

    func testNamedSessions() throws {
        try store.save(makeState(name: "Werk"), named: "Werk")
        try store.save(makeState(name: "Privé"), named: "Privé")
        XCTAssertEqual(store.availableSessionNames().sorted(), ["Privé", "Werk"])

        XCTAssertEqual(store.load(named: "Werk")?.name, "Werk")
        try store.delete(named: "Werk")
        XCTAssertEqual(store.availableSessionNames(), ["Privé"])
    }

    func testEmptyNameIsRejected() {
        XCTAssertThrowsError(try store.save(makeState(name: ""), named: "  ")) { error in
            XCTAssertEqual(error as? SessionStore.StoreError, .invalidName)
        }
    }

    func testScratchFilesKeepUnsavedWork() throws {
        let fileName = try store.writeScratch("nog niet opgeslagen")
        XCTAssertEqual(store.readScratch(fileName), "nog niet opgeslagen")

        var state = makeState(name: "Automatisch")
        state.panes[0].documents.append(SessionDocumentState(scratchFileName: fileName,
                                                             displayName: "Naamloos 1"))
        try store.saveAutosave(state)

        let unusedName = try store.writeScratch("wees")
        store.pruneScratchFiles(keeping: [state])
        XCTAssertEqual(store.readScratch(fileName), "nog niet opgeslagen")
        XCTAssertNil(store.readScratch(unusedName), "niet-gerefereerde kladbestanden worden opgeruimd")
    }

    func testMissingSessionReturnsNil() {
        XCTAssertNil(store.load(named: "bestaat-niet"))
        XCTAssertNil(store.loadAutosave())
    }
}

final class FindInFilesTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("inkline-find-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(".git"),
                                                withIntermediateDirectories: true)
        try Data("een kat\ntwee kat\n".utf8).write(to: directory.appendingPathComponent("a.txt"))
        try Data("geen dier\n".utf8).write(to: directory.appendingPathComponent("b.txt"))
        try Data("kat in submap\n".utf8).write(to: directory.appendingPathComponent("sub/c.swift"))
        try Data("kat in git\n".utf8).write(to: directory.appendingPathComponent(".git/d.txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testFindsMatchesAcrossDirectories() {
        let request = FindInFilesRequest(roots: [directory], query: SearchQuery(pattern: "kat"))
        var hits = [FileSearchHit]()
        let summary = FindInFilesSearch(request: request).run { hits.append(contentsOf: $0) }

        XCTAssertEqual(summary.hits, 3)
        XCTAssertEqual(summary.matchedFiles, 2)
        XCTAssertFalse(hits.contains { $0.url.path.contains(".git") }, "verborgen mappen worden overgeslagen")

        let second = hits.first { $0.url.lastPathComponent == "a.txt" && $0.line == 1 }
        XCTAssertEqual(second?.lineText, "twee kat")
        XCTAssertEqual(second?.rangeInLine, 5..<8)
    }

    func testIncludePatternFiltersFiles() {
        let request = FindInFilesRequest(roots: [directory],
                                         query: SearchQuery(pattern: "kat"),
                                         includePatterns: ["*.swift"])
        var hits = [FileSearchHit]()
        _ = FindInFilesSearch(request: request).run { hits.append(contentsOf: $0) }
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.url.lastPathComponent, "c.swift")
    }

    func testExcludePatternSkipsFiles() {
        let request = FindInFilesRequest(roots: [directory],
                                         query: SearchQuery(pattern: "kat"),
                                         excludePatterns: ["a.*"])
        var hits = [FileSearchHit]()
        _ = FindInFilesSearch(request: request).run { hits.append(contentsOf: $0) }
        XCTAssertEqual(hits.count, 1)
    }

    func testCancellationStopsTheSearch() {
        let request = FindInFilesRequest(roots: [directory], query: SearchQuery(pattern: "kat"))
        let search = FindInFilesSearch(request: request)
        search.cancel()
        let summary = search.run { _ in }
        XCTAssertTrue(summary.wasCancelled || summary.hits == 0)
    }
}

final class GlobPatternTests: XCTestCase {

    func testStarMatches() {
        XCTAssertTrue(GlobPattern.matches("*.swift", "Editor.swift"))
        XCTAssertFalse(GlobPattern.matches("*.swift", "Editor.js"))
        XCTAssertTrue(GlobPattern.matches("*", "wat dan ook"))
        XCTAssertTrue(GlobPattern.matches("test*.json", "test-data.json"))
    }

    func testQuestionMarkAndSets() {
        XCTAssertTrue(GlobPattern.matches("a?c", "abc"))
        XCTAssertFalse(GlobPattern.matches("a?c", "ac"))
        XCTAssertTrue(GlobPattern.matches("file[0-9].txt", "file7.txt"))
        XCTAssertFalse(GlobPattern.matches("file[0-9].txt", "filex.txt"))
        XCTAssertTrue(GlobPattern.matches("file[!0-9].txt", "filex.txt"))
    }

    func testExactMatch() {
        XCTAssertTrue(GlobPattern.matches("Dockerfile", "Dockerfile"))
        XCTAssertFalse(GlobPattern.matches("Dockerfile", "Dockerfile.dev"))
    }
}
