import AppKit
import Combine
import InklineCore
import InklineSyntax

/// One open tab: the core `TextDocument`, the TextKit storage that renders it,
/// and the derived state the panels show (symbols, fold regions, word index).
///
/// The text storage is the live editing surface; every edit it makes is
/// mirrored into the core `TextBuffer`, which is what search, transforms,
/// macros and plugins work against. The mirror is one-way during typing and
/// re-entrancy guarded in the other direction, so there is exactly one place
/// where text changes enter the model.
@MainActor
final class EditorDocument: ObservableObject, Identifiable {

    let id: UUID
    let document: TextDocument
    let textStorage: InklineTextStorage
    let coordinator: HighlightCoordinator

    @Published private(set) var displayName: String
    @Published private(set) var isDirty = false
    @Published var language: LanguageDefinition
    @Published private(set) var symbols: [DocumentSymbol] = []
    @Published private(set) var foldingState = FoldingState()
    @Published var selection = TextSelection(caret: 0)
    @Published var selectedRangeCount = 1
    @Published var selectedCharacterCount = 0
    @Published var isOverwriteMode = false

    /// Scroll position, saved into the session.
    var scrollOffset: Double = 0

    /// Set by the editor view so model-driven edits go through the same undo
    /// manager as typing.
    weak var textView: InklineTextView?

    private let environment: AppEnvironment
    private var isMirroring = false
    private var wordIndex = WordIndex()
    private var analysisWorkItem: DispatchWorkItem?
    private var documentObserver: Int?

    init(document: TextDocument, environment: AppEnvironment) {
        self.id = document.id
        self.document = document
        self.environment = environment

        let registry = environment.languageRegistry
        let language = document.languageIdentifier.flatMap { registry.language(withIdentifier: $0) }
            ?? registry.bestMatch(for: document.fileURL, text: document.buffer.text)
        self.language = language
        document.languageIdentifier = language.identifier
        if document.isUntitled || document.indentation == .default {
            document.indentation = language.indentation
        }

        let highlighter = TreeSitterHighlighterFactory.makeHighlighter(for: language,
                                                                       loader: environment.grammarLoader)
        coordinator = HighlightCoordinator(highlighter: highlighter)
        textStorage = InklineTextStorage(style: environment.style, coordinator: coordinator)
        displayName = document.displayName

        textStorage.indentation = document.indentation
        textStorage.wrapsLines = environment.settings.wrapsLines
        textStorage.setText(document.buffer.text)

        textStorage.onEdit = { [weak self] change in
            self?.mirrorIntoBuffer(change)
        }
        documentObserver = document.addObserver { [weak self] _, kind in
            Task { @MainActor in self?.handleDocumentChange(kind) }
        }
        scheduleAnalysis()
    }

    // MARK: Text access

    var text: String { textStorage.swiftString }
    var length: Int { textStorage.length }
    var fileURL: URL? { document.fileURL }

    /// Line index backed by the core piece table, used by the gutter and the
    /// status bar so neither has to scan the text.
    private(set) var lineIndex = PieceTable("")

    func lineNumber(at offset: Int) -> Int {
        lineIndex.lineNumber(at: min(max(offset, 0), lineIndex.count))
    }

    func position(at offset: Int) -> TextPosition {
        lineIndex.position(at: min(max(offset, 0), lineIndex.count))
    }

    func offsetOfLineStart(_ line: Int) -> Int {
        guard line >= 0, line < lineIndex.lineCount else { return 0 }
        return lineIndex.offsetOfLineStart(line)
    }

    // MARK: Mirroring

    private func mirrorIntoBuffer(_ change: TextChange) {
        guard !isMirroring else { return }
        isMirroring = true
        document.buffer.replace(change.editedRange, with: change.insertedText)
        isMirroring = false
        scheduleAnalysis()
    }

    /// Applies an edit that came from outside the text view (a plugin, a macro,
    /// "replace all") to the view, so undo and highlighting stay consistent.
    func applyExternalEdits(_ edits: [TextEdit]) {
        guard !edits.isEmpty else { return }
        isMirroring = true
        defer { isMirroring = false }

        textView?.undoManager?.beginUndoGrouping()
        for edit in TextEditBatch.normalized(edits).reversed() {
            let range = NSRange(location: edit.range.lowerBound, length: edit.range.count)
            if let textView, textView.shouldChangeText(in: range, replacementString: edit.replacement) {
                textStorage.replaceCharacters(in: range, with: edit.replacement)
                textView.didChangeText()
            } else {
                textStorage.replaceCharacters(in: range, with: edit.replacement)
            }
            document.buffer.replace(edit.range, with: edit.replacement)
        }
        textView?.undoManager?.endUndoGrouping()
        scheduleAnalysis()
    }

    func replaceAll(with newText: String) {
        applyExternalEdits([TextEdit(range: 0..<length, replacement: newText)])
    }

    // MARK: Derived state

    private func handleDocumentChange(_ kind: TextDocument.ChangeKind) {
        switch kind {
        case .dirtyState:
            isDirty = document.isDirty
        case .fileURL:
            displayName = document.displayName
            retargetLanguageIfNeeded()
        case .metadata:
            textStorage.indentation = document.indentation
            objectWillChange.send()
        case .text:
            break
        }
    }

    private func retargetLanguageIfNeeded() {
        guard let url = document.fileURL,
              let match = environment.languageRegistry.language(for: url) else { return }
        setLanguage(match)
    }

    func setLanguage(_ newLanguage: LanguageDefinition) {
        guard newLanguage.identifier != language.identifier else { return }
        language = newLanguage
        document.languageIdentifier = newLanguage.identifier
        let highlighter = TreeSitterHighlighterFactory.makeHighlighter(for: newLanguage,
                                                                       loader: environment.grammarLoader)
        coordinator.setHighlighter(highlighter)
        textStorage.applyBaseAttributes()
        textStorage.applyHighlighting(in: NSRange(location: 0, length: min(length, 200_000)))
        scheduleAnalysis()
    }

    func updateStyle(_ style: ThemeStyle) {
        textStorage.style = style
    }

    func updateSettings(_ settings: EditorSettings) {
        textStorage.wrapsLines = settings.wrapsLines
    }

    /// Recomputes the line index, symbol list, fold regions and word index off
    /// the main thread, coalesced so that holding down a key does not queue up
    /// a hundred analyses.
    func scheduleAnalysis() {
        analysisWorkItem?.cancel()
        let snapshot = text
        let language = self.language
        let indentation = document.indentation

        let workItem = DispatchWorkItem { [weak self] in
            let table = PieceTable(snapshot)
            let symbols = SymbolExtractor.symbols(in: snapshot, language: language)
            let regions = FoldingCalculator.regions(in: table,
                                                    strategy: language.folding,
                                                    indentation: indentation,
                                                    pairs: language.bracketPairs.isEmpty
                                                        ? BracketMatcher.defaultPairs
                                                        : language.bracketPairs)
            // Word completion over a 100 MB file would cost more than it is
            // worth; above the limit the editor simply offers keywords and
            // symbols instead.
            let index = WordIndex()
            if snapshot.utf16.count < 4 * 1024 * 1024 {
                index.rebuild(from: snapshot)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.lineIndex = table
                self.symbols = symbols
                var folding = self.foldingState
                folding.update(regions: regions)
                self.foldingState = folding
                self.wordIndex = index
            }
        }
        analysisWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    func completions(for prefix: String) -> [String] {
        var groups = [wordIndex.candidates(prefix: prefix)]
        if environment.settings.completionIncludesKeywords {
            groups.append(language.keywords
                .filter { $0.lowercased().hasPrefix(prefix.lowercased()) && $0 != prefix }
                .map { CompletionCandidate(text: $0, kind: .keyword, score: 1) })
            groups.append(symbols
                .filter { $0.name.lowercased().hasPrefix(prefix.lowercased()) && $0.name != prefix }
                .map { CompletionCandidate(text: $0.name, kind: .symbol, score: 2) })
        }
        return CompletionRanker.merge(groups, prefix: prefix).map(\.text)
    }

    // MARK: Folding & bookmarks

    func toggleFold(atLine line: Int) {
        var folding = foldingState
        guard folding.toggle(at: line) else { return }
        foldingState = folding
    }

    func collapseAllFolds() {
        var folding = foldingState
        folding.collapseAll()
        foldingState = folding
    }

    func expandAllFolds() {
        var folding = foldingState
        folding.expandAll()
        foldingState = folding
    }

    func collapseFolds(toLevel level: Int) {
        var folding = foldingState
        folding.collapse(toLevel: level)
        foldingState = folding
    }

    func toggleBookmark(atLine line: Int) {
        document.bookmarks.toggle(line)
        objectWillChange.send()
    }

    // MARK: Saving

    func save(to url: URL? = nil) throws {
        syncBufferBeforeSaving()
        try document.save(to: url, options: environment.settings.saveOptions)
        if document.buffer.text != text {
            // Trimming on save rewrote the text; bring the view in line.
            isMirroring = true
            textStorage.setText(document.buffer.text)
            isMirroring = false
        }
        displayName = document.displayName
    }

    /// The mirror can only drift if something wrote to the storage without
    /// going through `replaceCharacters`; this is the cheap safety net that
    /// guarantees what we write to disk is what the user sees.
    private func syncBufferBeforeSaving() {
        if document.buffer.text != text {
            document.buffer.reset(to: text)
            document.markDirty()
        }
    }
}
