import AppKit
import Combine
import InklineCore

/// The Find bar: incremental search in the active document, replace, replace
/// all, and "replace in all open tabs".
@MainActor
final class FindModel: ObservableObject {

    @Published var isVisible = false
    @Published var showsReplaceField = false
    @Published var query = SearchQuery()
    @Published var replacement = ""
    @Published private(set) var matchCount = 0
    @Published private(set) var currentMatchIndex: Int?
    @Published private(set) var errorMessage: String?
    /// Highlight every match, not just the current one.
    @Published var highlightsAllMatches = true

    var workspaceProvider: (() -> WorkspaceModel?)?

    private var searchWorkItem: DispatchWorkItem?

    private var workspace: WorkspaceModel? { workspaceProvider?() }
    private var document: EditorDocument? { workspace?.activeDocument }
    private var textView: InklineTextView? { workspace?.activeTextView }

    // MARK: Presentation

    func show(replacing: Bool = false) {
        showsReplaceField = replacing || showsReplaceField
        isVisible = true
        if let selected = textView?.selectedRange(), selected.length > 0, selected.length < 200 {
            query.pattern = (textView?.string as NSString?)?.substring(with: selected) ?? query.pattern
        }
        updateMatches()
    }

    func hide() {
        isVisible = false
        textView?.findHighlightRanges = []
        textView?.currentFindRange = nil
    }

    func useSelectionForFind() {
        guard let textView, textView.selectedRange().length > 0 else { return }
        query.pattern = (textView.string as NSString).substring(with: textView.selectedRange())
        updateMatches()
    }

    // MARK: Searching

    /// Debounced so typing in the find field does not re-scan a large document
    /// on every keystroke.
    func queryDidChange() {
        searchWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.updateMatches() }
        }
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    func updateMatches() {
        guard let textView, !query.isEmpty else {
            matchCount = 0
            currentMatchIndex = nil
            errorMessage = nil
            textView?.findHighlightRanges = []
            textView?.currentFindRange = nil
            return
        }
        do {
            let matches = try SearchEngine.matches(of: query, in: textView.string, limit: 20_000)
            matchCount = matches.count
            errorMessage = nil
            if highlightsAllMatches {
                textView.findHighlightRanges = matches.map {
                    NSRange(location: $0.range.lowerBound, length: $0.range.count)
                }
            } else {
                textView.findHighlightRanges = []
            }
            let caret = textView.selectedRange().location
            currentMatchIndex = matches.firstIndex { $0.range.lowerBound >= caret }
        } catch {
            matchCount = 0
            currentMatchIndex = nil
            errorMessage = error.localizedDescription
            textView.findHighlightRanges = []
        }
    }

    @discardableResult
    func findNext(direction: SearchDirection = .forward) -> Bool {
        guard let textView, !query.isEmpty else { return false }
        let selection = textView.selectedRange()
        let from = direction == .forward ? NSMaxRange(selection) : selection.location
        do {
            guard let match = try SearchEngine.firstMatch(of: query,
                                                          in: textView.string,
                                                          from: from,
                                                          direction: direction) else {
                NSSound.beep()
                return false
            }
            let range = NSRange(location: match.range.lowerBound, length: match.range.count)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
            textView.currentFindRange = range
            updateMatches()
            recordMacroFind(direction: direction)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func replaceCurrent() {
        guard let textView, !query.isEmpty else { return }
        let selection = textView.selectedRange()
        guard selection.length > 0 else {
            findNext()
            return
        }
        do {
            let match = SearchMatch(range: selection.location..<NSMaxRange(selection))
            let text = try SearchEngine.replacement(for: match,
                                                    query: query,
                                                    template: replacement,
                                                    in: textView.string)
            if textView.shouldChangeText(in: selection, replacementString: text) {
                textView.textStorage?.replaceCharacters(in: selection, with: text)
                textView.didChangeText()
            }
            findNext()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func replaceAllInActiveDocument() {
        guard let document, !query.isEmpty else { return }
        do {
            let result = try SearchEngine.replaceAll(query: query, in: document.text, with: replacement)
            document.applyExternalEdits(result.edits)
            errorMessage = nil
            announce(count: result.count, documents: 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func replaceAllInOpenDocuments() {
        guard let workspace, !query.isEmpty else { return }
        var total = 0
        var touched = 0
        for document in workspace.documents.values {
            guard let result = try? SearchEngine.replaceAll(query: query,
                                                            in: document.text,
                                                            with: replacement),
                  result.count > 0 else { continue }
            document.applyExternalEdits(result.edits)
            total += result.count
            touched += 1
        }
        announce(count: total, documents: touched)
    }

    func selectAllMatches() {
        guard let textView, !query.isEmpty,
              let matches = try? SearchEngine.matches(of: query, in: textView.string, limit: 5_000),
              !matches.isEmpty else { return }
        textView.clearAdditionalCarets()
        textView.setSelectedRanges(matches.map {
            NSValue(range: NSRange(location: $0.range.lowerBound, length: $0.range.count))
        }, affinity: .downstream, stillSelecting: false)
    }

    private func announce(count: Int, documents: Int) {
        let format = NSLocalizedString("%d vervangingen in %d document(en).",
                                       comment: "Melding na alles vervangen")
        workspace?.alert = WorkspaceAlert(title: NSLocalizedString("Vervangen", comment: "Titel van de melding"),
                                          message: String(format: format, count, documents))
    }

    private func recordMacroFind(direction: SearchDirection) {
        guard let workspace, workspace.environment.macroRecorder.isRecording else { return }
        workspace.environment.macroRecorder.record(.find(query: query, direction: direction))
    }
}

/// Find in Files: searches a folder tree on a background queue and streams the
/// results into the sidebar.
@MainActor
final class FindInFilesModel: ObservableObject {

    @Published var query = SearchQuery()
    @Published var searchRoot: URL?
    @Published var includePatterns = ""
    @Published var excludePatterns = ""
    @Published var includesHiddenFiles = false
    @Published private(set) var hits: [FileSearchHit] = []
    @Published private(set) var isSearching = false
    @Published private(set) var summaryText = ""
    @Published var replacement = ""

    var onOpenHit: ((FileSearchHit) -> Void)?

    private var search: FindInFilesSearch?

    var hitsByFile: [(url: URL, hits: [FileSearchHit])] {
        let grouped = Dictionary(grouping: hits, by: \.url)
        return grouped.keys.sorted { $0.path < $1.path }.map { ($0, grouped[$0] ?? []) }
    }

    func start() {
        guard let root = searchRoot, !query.isEmpty else { return }
        cancel()
        hits = []
        isSearching = true
        summaryText = NSLocalizedString("Bezig met zoeken…", comment: "Status tijdens zoeken in bestanden")

        let request = FindInFilesRequest(roots: [root],
                                         query: query,
                                         includePatterns: patterns(from: includePatterns),
                                         excludePatterns: patterns(from: excludePatterns),
                                         includesHiddenFiles: includesHiddenFiles)
        let search = FindInFilesSearch(request: request)
        self.search = search

        DispatchQueue.global(qos: .userInitiated).async {
            let summary = search.run { fileHits in
                Task { @MainActor in
                    self.hits.append(contentsOf: fileHits)
                }
            }
            Task { @MainActor in
                self.isSearching = false
                let format = NSLocalizedString("%d treffers in %d van %d bestanden (%.2f s)",
                                               comment: "Samenvatting van zoeken in bestanden")
                self.summaryText = String(format: format,
                                          summary.hits,
                                          summary.matchedFiles,
                                          summary.scannedFiles,
                                          summary.duration)
            }
        }
    }

    func cancel() {
        search?.cancel()
        search = nil
        isSearching = false
    }

    func open(_ hit: FileSearchHit) {
        onOpenHit?(hit)
    }

    /// Replaces every hit on disk. Files that are open in a tab are skipped and
    /// reported, because silently rewriting a file the user is editing is how
    /// editors lose work.
    func replaceAllOnDisk(skipping openURLs: Set<URL>) -> String {
        var changedFiles = 0
        var replacements = 0
        var skipped = 0
        for (url, _) in hitsByFile {
            if openURLs.contains(url.standardizedFileURL) {
                skipped += 1
                continue
            }
            guard let loaded = try? FileLoader.load(contentsOf: url),
                  let result = try? SearchEngine.replaceAll(query: query,
                                                            in: loaded.text,
                                                            with: replacement),
                  result.count > 0 else { continue }
            do {
                try FileLoader.write(result.text,
                                     to: url,
                                     encoding: loaded.encoding,
                                     lineEnding: loaded.lineEnding)
                changedFiles += 1
                replacements += result.count
            } catch {
                continue
            }
        }
        let format = NSLocalizedString("%d vervangingen in %d bestanden. %d open bestanden overgeslagen.",
                                       comment: "Samenvatting na vervangen op schijf")
        return String(format: format, replacements, changedFiles, skipped)
    }

    private func patterns(from text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
