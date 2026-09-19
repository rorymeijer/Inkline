import AppKit
import Combine
import InklineCore
import InklinePluginAPI
import InklineSyntax
import UniformTypeIdentifiers

/// One pane of the split view: an ordered set of tabs plus the active one.
@MainActor
final class EditorPane: ObservableObject, Identifiable {
    let id = UUID()
    @Published var documentIDs: [UUID] = []
    @Published var activeDocumentID: UUID?

    init(documentIDs: [UUID] = [], activeDocumentID: UUID? = nil) {
        self.documentIDs = documentIDs
        self.activeDocumentID = activeDocumentID ?? documentIDs.first
    }
}

enum SidebarPanel: String, CaseIterable, Identifiable {
    case explorer
    case symbols
    case map
    case searchResults
    case plugins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explorer: return NSLocalizedString("Bestanden", comment: "Zijpaneel: bestandsverkenner")
        case .symbols: return NSLocalizedString("Functielijst", comment: "Zijpaneel: symbolen")
        case .map: return NSLocalizedString("Documentkaart", comment: "Zijpaneel: minikaart")
        case .searchResults: return NSLocalizedString("Zoekresultaten", comment: "Zijpaneel: zoekresultaten")
        case .plugins: return NSLocalizedString("Plugins", comment: "Zijpaneel: pluginpanelen")
        }
    }

    var symbolName: String {
        switch self {
        case .explorer: return "folder"
        case .symbols: return "list.bullet.indent"
        case .map: return "map"
        case .searchResults: return "magnifyingglass"
        case .plugins: return "puzzlepiece.extension"
        }
    }
}

/// The window's model: which documents are open, in which pane, and every
/// document-level action the menus invoke.
@MainActor
final class WorkspaceModel: ObservableObject {

    @Published private(set) var documents: [UUID: EditorDocument] = [:]
    @Published var panes: [EditorPane]
    @Published var activePaneID: UUID
    @Published var splitOrientation: SplitOrientation = .none
    @Published var synchronizedScrolling = false
    @Published var explorerRoots: [URL] = []
    @Published var visibleSidebarPanel: SidebarPanel? = .explorer
    @Published var isSidebarVisible = true
    @Published var alert: WorkspaceAlert?

    let environment: AppEnvironment
    let find: FindModel
    let findInFiles: FindInFilesModel

    /// The text view that currently has focus; menu commands act on it.
    weak var activeTextView: InklineTextView?

    /// Scroll views per pane, used for synchronised scrolling in split view.
    private var paneScrollViews: [UUID: NSScrollView] = [:]
    private var isSynchronizingScroll = false
    private var untitledCounter = 0
    private var autosaveWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(environment: AppEnvironment) {
        self.environment = environment
        let pane = EditorPane()
        panes = [pane]
        activePaneID = pane.id
        find = FindModel()
        findInFiles = FindInFilesModel()

        find.workspaceProvider = { [weak self] in self }
        findInFiles.onOpenHit = { [weak self] hit in
            self?.open(url: hit.url, selecting: hit.range)
        }
        environment.pluginHost.documentProvider = { [weak self] in
            guard let self, let document = self.activeDocument else { return nil }
            return AppPluginDocument(document: document, workspace: self)
        }
        environment.pluginHost.openDocumentsProvider = { [weak self] in
            guard let self else { return [] }
            return self.documents.values.map { AppPluginDocument(document: $0, workspace: self) }
        }
        environment.pluginHost.panelRevealer = { [weak self] _ in
            self?.visibleSidebarPanel = .plugins
            self?.isSidebarVisible = true
        }
    }

    // MARK: Access

    var activePane: EditorPane {
        panes.first { $0.id == activePaneID } ?? panes[0]
    }

    var activeDocument: EditorDocument? {
        guard let id = activePane.activeDocumentID else { return nil }
        return documents[id]
    }

    func document(id: UUID) -> EditorDocument? { documents[id] }

    func documents(in pane: EditorPane) -> [EditorDocument] {
        pane.documentIDs.compactMap { documents[$0] }
    }

    var hasUnsavedChanges: Bool {
        documents.values.contains { $0.isDirty }
    }

    // MARK: Opening

    @discardableResult
    func newDocument() -> EditorDocument {
        untitledCounter += 1
        let document = TextDocument(untitledNumber: untitledCounter,
                                    indentation: environment.settings.indentation)
        return addDocument(document)
    }

    @discardableResult
    private func addDocument(_ document: TextDocument, to pane: EditorPane? = nil) -> EditorDocument {
        let editorDocument = EditorDocument(document: document, environment: environment)
        editorDocument.updateStyle(environment.style)
        editorDocument.updateSettings(environment.settings)
        documents[editorDocument.id] = editorDocument

        let target = pane ?? activePane
        target.documentIDs.append(editorDocument.id)
        target.activeDocumentID = editorDocument.id
        scheduleAutosave()
        return editorDocument
    }

    @discardableResult
    func open(url: URL, selecting range: Range<Int>? = nil, in pane: EditorPane? = nil) -> EditorDocument? {
        let standardized = url.standardizedFileURL

        if let existing = documents.values.first(where: { $0.fileURL?.standardizedFileURL == standardized }) {
            reveal(documentID: existing.id)
            if let range { select(range, in: existing) }
            return existing
        }

        do {
            let document = try TextDocument.open(contentsOf: standardized,
                                                 indentation: environment.settings.indentation)
            let editorDocument = addDocument(document, to: pane)
            environment.settingsStore.noteRecentFile(standardized)
            NSDocumentController.shared.noteNewRecentDocumentURL(standardized)
            if let range { select(range, in: editorDocument) }
            return editorDocument
        } catch {
            alert = WorkspaceAlert(title: NSLocalizedString("Kon het bestand niet openen", comment: "Foutmelding"),
                                   message: error.localizedDescription)
            return nil
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = NSLocalizedString("Kies bestanden of een map om te openen",
                                          comment: "Bericht in het open-venster")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                addExplorerRoot(url)
            } else {
                open(url: url)
            }
        }
    }

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addExplorerRoot(url)
    }

    func addExplorerRoot(_ url: URL) {
        guard !explorerRoots.contains(url) else { return }
        explorerRoots.append(url)
        visibleSidebarPanel = .explorer
        isSidebarVisible = true
        scheduleAutosave()
    }

    func removeExplorerRoot(_ url: URL) {
        explorerRoots.removeAll { $0 == url }
        scheduleAutosave()
    }

    // MARK: Tabs

    func reveal(documentID: UUID) {
        if let pane = panes.first(where: { $0.documentIDs.contains(documentID) }) {
            pane.activeDocumentID = documentID
            activePaneID = pane.id
        } else {
            activePane.documentIDs.append(documentID)
            activePane.activeDocumentID = documentID
        }
    }

    func select(_ range: Range<Int>, in document: EditorDocument) {
        reveal(documentID: document.id)
        DispatchQueue.main.async { [weak self] in
            guard let textView = self?.activeTextView else { return }
            let nsRange = NSRange(location: range.lowerBound, length: range.count)
            textView.setSelectedRange(nsRange)
            textView.scrollRangeToVisible(nsRange)
            textView.showFindIndicator(for: nsRange)
        }
    }

    func closeDocument(id: UUID, force: Bool = false) {
        guard let document = documents[id] else { return }
        if document.isDirty && !force {
            promptToSave(document) { [weak self] shouldClose in
                if shouldClose { self?.closeDocument(id: id, force: true) }
            }
            return
        }
        for pane in panes {
            if let index = pane.documentIDs.firstIndex(of: id) {
                pane.documentIDs.remove(at: index)
                if pane.activeDocumentID == id {
                    pane.activeDocumentID = pane.documentIDs.indices.contains(index)
                        ? pane.documentIDs[index]
                        : pane.documentIDs.last
                }
            }
        }
        documents.removeValue(forKey: id)
        if panes.allSatisfy({ $0.documentIDs.isEmpty }), panes.count > 1 {
            closeEmptyPanes()
        }
        scheduleAutosave()
    }

    func closeActiveDocument() {
        guard let id = activePane.activeDocumentID else { return }
        closeDocument(id: id)
    }

    func closeOtherDocuments() {
        guard let keep = activePane.activeDocumentID else { return }
        for id in activePane.documentIDs where id != keep {
            closeDocument(id: id)
        }
    }

    func closeAllDocuments() {
        closeAllDocuments(force: false)
    }

    func moveTab(in pane: EditorPane, from source: IndexSet, to destination: Int) {
        pane.documentIDs.move(fromOffsets: source, toOffset: destination)
        scheduleAutosave()
    }

    func selectNextTab() {
        let pane = activePane
        guard let current = pane.activeDocumentID,
              let index = pane.documentIDs.firstIndex(of: current),
              !pane.documentIDs.isEmpty else { return }
        pane.activeDocumentID = pane.documentIDs[(index + 1) % pane.documentIDs.count]
    }

    func selectPreviousTab() {
        let pane = activePane
        guard let current = pane.activeDocumentID,
              let index = pane.documentIDs.firstIndex(of: current),
              !pane.documentIDs.isEmpty else { return }
        pane.activeDocumentID = pane.documentIDs[(index - 1 + pane.documentIDs.count) % pane.documentIDs.count]
    }

    // MARK: Split view

    func splitPane(orientation: SplitOrientation) {
        if panes.count == 1 {
            let new = EditorPane()
            if let active = activePane.activeDocumentID {
                new.documentIDs = [active]              // same document, second view
                new.activeDocumentID = active
            }
            panes.append(new)
        }
        splitOrientation = orientation
        scheduleAutosave()
    }

    func closeSplit() {
        guard panes.count > 1 else { return }
        let keep = activePane
        panes = [keep]
        activePaneID = keep.id
        splitOrientation = .none
        scheduleAutosave()
    }

    private func closeEmptyPanes() {
        panes.removeAll { $0.documentIDs.isEmpty }
        if panes.isEmpty {
            let pane = EditorPane()
            panes = [pane]
        }
        if !panes.contains(where: { $0.id == activePaneID }) {
            activePaneID = panes[0].id
        }
        if panes.count == 1 { splitOrientation = .none }
    }

    func moveActiveDocumentToOtherPane() {
        guard panes.count > 1, let id = activePane.activeDocumentID else { return }
        guard let other = panes.first(where: { $0.id != activePaneID }) else { return }
        activePane.documentIDs.removeAll { $0 == id }
        activePane.activeDocumentID = activePane.documentIDs.first
        other.documentIDs.append(id)
        other.activeDocumentID = id
        activePaneID = other.id
    }

    // MARK: Saving

    func save(_ document: EditorDocument? = nil) {
        guard let document = document ?? activeDocument else { return }
        if document.fileURL == nil {
            saveAs(document)
            return
        }
        do {
            try document.save()
            scheduleAutosave()
        } catch {
            alert = WorkspaceAlert(title: NSLocalizedString("Opslaan mislukt", comment: "Foutmelding"),
                                   message: error.localizedDescription)
        }
    }

    func saveAs(_ document: EditorDocument? = nil) {
        guard let document = document ?? activeDocument else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.displayName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try document.save(to: url)
            environment.settingsStore.noteRecentFile(url)
            scheduleAutosave()
        } catch {
            alert = WorkspaceAlert(title: NSLocalizedString("Opslaan mislukt", comment: "Foutmelding"),
                                   message: error.localizedDescription)
        }
    }

    func saveAll() {
        for document in documents.values where document.isDirty {
            save(document)
        }
    }

    func revertActiveDocument() {
        guard let document = activeDocument, document.fileURL != nil else { return }
        do {
            try document.document.reloadFromDisk()
            document.replaceAll(with: document.document.buffer.text)
        } catch {
            alert = WorkspaceAlert(title: NSLocalizedString("Herladen mislukt", comment: "Foutmelding"),
                                   message: error.localizedDescription)
        }
    }

    private func promptToSave(_ document: EditorDocument, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Wil je de wijzigingen in “%@” bewaren?",
                                                             comment: "Vraag bij sluiten van een gewijzigd document"),
                                   document.displayName)
        alert.informativeText = NSLocalizedString("Als je niet bewaart, gaan de wijzigingen verloren.",
                                                  comment: "Toelichting bij de bewaarvraag")
        alert.addButton(withTitle: NSLocalizedString("Bewaren", comment: "Knop"))
        alert.addButton(withTitle: NSLocalizedString("Niet bewaren", comment: "Knop"))
        alert.addButton(withTitle: NSLocalizedString("Annuleer", comment: "Knop"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save(document)
            completion(!document.isDirty)
        case .alertSecondButtonReturn:
            completion(true)
        default:
            completion(false)
        }
    }

    // MARK: Encoding, line endings, language

    func setEncoding(_ encoding: TextEncoding, reinterpret: Bool) {
        guard let document = activeDocument else { return }
        if reinterpret, let url = document.fileURL {
            do {
                let loaded = try FileLoader.load(contentsOf: url, forcedEncoding: encoding)
                document.replaceAll(with: loaded.text)
                document.document.encoding = encoding
            } catch {
                alert = WorkspaceAlert(title: NSLocalizedString("Herinterpreteren mislukt", comment: "Foutmelding"),
                                       message: error.localizedDescription)
            }
        } else {
            document.document.convert(to: encoding)
        }
    }

    func setLineEnding(_ lineEnding: LineEnding) {
        activeDocument?.document.convert(to: lineEnding)
    }

    func setLanguage(_ language: LanguageDefinition) {
        activeDocument?.setLanguage(language)
    }

    func setIndentation(_ indentation: IndentationSettings) {
        activeDocument?.document.indentation = indentation
        activeTextView?.indentation = indentation
    }

    // MARK: Navigation

    func goToLine(_ line: Int) {
        guard let document = activeDocument, let textView = activeTextView else { return }
        let clamped = max(0, min(line, document.lineIndex.lineCount - 1))
        let range = document.lineIndex.lineContentRange(clamped)
        let nsRange = NSRange(location: range.lowerBound, length: 0)
        textView.setSelectedRange(nsRange)
        textView.scrollRangeToVisible(NSRange(location: range.lowerBound, length: range.count))
    }

    func goToMatchingBracket() {
        guard let document = activeDocument, let textView = activeTextView else { return }
        guard let match = BracketMatcher.match(at: textView.selectedRange().location,
                                               in: document.lineIndex,
                                               pairs: document.language.bracketPairs.isEmpty
                                                   ? BracketMatcher.defaultPairs
                                                   : document.language.bracketPairs) else { return }
        textView.setSelectedRange(NSRange(location: match.counterpart, length: 1))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    func toggleBookmarkOnCurrentLine() {
        guard let document = activeDocument, let textView = activeTextView else { return }
        document.toggleBookmark(atLine: document.lineNumber(at: textView.selectedRange().location))
    }

    func goToNextBookmark(forward: Bool = true) {
        guard let document = activeDocument, let textView = activeTextView else { return }
        let current = document.lineNumber(at: textView.selectedRange().location)
        let target = forward
            ? document.document.bookmarks.next(after: current)
            : document.document.bookmarks.previous(before: current)
        guard let target else { return }
        goToLine(target)
    }

    func clearBookmarks() {
        activeDocument?.document.bookmarks.removeAll()
        activeDocument?.objectWillChange.send()
    }

    // MARK: Synchronised scrolling

    func register(scrollView: NSScrollView, for paneID: UUID) {
        paneScrollViews[paneID] = scrollView
    }

    func unregisterScrollView(for paneID: UUID) {
        paneScrollViews.removeValue(forKey: paneID)
    }

    func synchronizeScroll(from paneID: UUID, to origin: NSPoint) {
        guard synchronizedScrolling, !isSynchronizingScroll else { return }
        isSynchronizingScroll = true
        defer { isSynchronizingScroll = false }
        for (id, scrollView) in paneScrollViews where id != paneID {
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    // MARK: Sessions

    func captureSessionState(name: String = "Automatisch") -> SessionState {
        var paneStates = [SessionPaneState]()
        for pane in panes {
            var documentStates = [SessionDocumentState]()
            for id in pane.documentIDs {
                guard let editorDocument = documents[id] else { continue }
                var scratchName: String?
                if editorDocument.fileURL == nil || editorDocument.isDirty {
                    scratchName = try? environment.sessionStore.writeScratch(editorDocument.text)
                }
                documentStates.append(SessionDocumentState(
                    filePath: editorDocument.fileURL?.path,
                    scratchFileName: scratchName,
                    displayName: editorDocument.displayName,
                    selections: [editorDocument.selection],
                    scrollOffset: editorDocument.scrollOffset,
                    encoding: editorDocument.document.encoding,
                    lineEnding: editorDocument.document.lineEnding,
                    languageIdentifier: editorDocument.language.identifier,
                    indentation: editorDocument.document.indentation,
                    bookmarkedLines: editorDocument.document.bookmarks.sorted))
            }
            let activeIndex = pane.activeDocumentID
                .flatMap { pane.documentIDs.firstIndex(of: $0) } ?? 0
            paneStates.append(SessionPaneState(documents: documentStates, activeIndex: activeIndex))
        }
        return SessionState(name: name,
                            panes: paneStates,
                            activePaneIndex: panes.firstIndex { $0.id == activePaneID } ?? 0,
                            splitOrientation: splitOrientation,
                            synchronizedScrolling: synchronizedScrolling,
                            explorerRoots: explorerRoots.map(\.path))
    }

    func restore(_ state: SessionState) {
        closeAllDocuments(force: true)
        panes = []
        for paneState in state.panes {
            let pane = EditorPane()
            panes.append(pane)
            for documentState in paneState.documents {
                restore(documentState, into: pane)
            }
            if pane.documentIDs.indices.contains(paneState.activeIndex) {
                pane.activeDocumentID = pane.documentIDs[paneState.activeIndex]
            }
        }
        if panes.isEmpty { panes = [EditorPane()] }
        activePaneID = panes.indices.contains(state.activePaneIndex) ? panes[state.activePaneIndex].id : panes[0].id
        splitOrientation = panes.count > 1 ? state.splitOrientation : .none
        synchronizedScrolling = state.synchronizedScrolling
        explorerRoots = state.explorerRoots.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func restore(_ documentState: SessionDocumentState, into pane: EditorPane) {
        let scratchText = documentState.scratchFileName.flatMap { environment.sessionStore.readScratch($0) }

        var textDocument: TextDocument?
        if let url = documentState.url, FileManager.default.fileExists(atPath: url.path) {
            textDocument = try? TextDocument.open(contentsOf: url,
                                                  forcedEncoding: documentState.encoding,
                                                  indentation: documentState.indentation)
            if let scratchText, let loaded = textDocument, loaded.buffer.text != scratchText {
                // The buffer had unsaved changes when we quit: keep them.
                loaded.buffer.reset(to: scratchText)
                loaded.markDirty()
            }
        } else if let scratchText {
            untitledCounter += 1
            textDocument = TextDocument(text: scratchText,
                                        encoding: documentState.encoding,
                                        lineEnding: documentState.lineEnding,
                                        languageIdentifier: documentState.languageIdentifier,
                                        indentation: documentState.indentation,
                                        untitledNumber: untitledCounter)
            textDocument?.markDirty()
        }

        guard let textDocument else { return }
        textDocument.languageIdentifier = documentState.languageIdentifier
        textDocument.bookmarks = BookmarkSet(lines: Set(documentState.bookmarkedLines))
        let editorDocument = addDocument(textDocument, to: pane)
        editorDocument.selection = documentState.selections.first ?? TextSelection(caret: 0)
        editorDocument.scrollOffset = documentState.scrollOffset
    }

    func closeAllDocuments(force: Bool) {
        for id in documents.keys { closeDocument(id: id, force: force) }
    }

    func scheduleAutosave() {
        guard environment.settings.restoresSessionOnLaunch else { return }
        autosaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.saveAutosaveSession() }
        }
        autosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    func saveAutosaveSession() {
        let state = captureSessionState()
        try? environment.sessionStore.saveAutosave(state)
        environment.sessionStore.pruneScratchFiles(keeping: [state])
    }

    func saveNamedSession(_ name: String) {
        do {
            try environment.sessionStore.save(captureSessionState(name: name), named: name)
        } catch {
            alert = WorkspaceAlert(title: NSLocalizedString("Sessie bewaren mislukt", comment: "Foutmelding"),
                                   message: error.localizedDescription)
        }
    }

    func loadNamedSession(_ name: String) {
        guard let state = environment.sessionStore.load(named: name) else { return }
        restore(state)
    }
}

struct WorkspaceAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
