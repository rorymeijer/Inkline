import AppKit
import InklineCore
import InklinePluginAPI

/// Exposes an open tab to plugins.
///
/// Edits go through the text view when there is one, so a plugin's changes land
/// in the same undo stack as the user's own — "undo" after running a formatter
/// does what the user expects.
@MainActor
final class AppPluginDocument: PluginDocument {

    private let document: EditorDocument
    private weak var workspace: WorkspaceModel?

    init(document: EditorDocument, workspace: WorkspaceModel) {
        self.document = document
        self.workspace = workspace
    }

    var fileURL: URL? { document.fileURL }
    var displayName: String { document.displayName }
    var languageIdentifier: String? { document.language.identifier }
    var text: String { document.text }
    var length: Int { document.length }

    var selectedRange: Range<Int> {
        get {
            guard let textView = currentTextView else { return document.selection.range }
            let range = textView.selectedRange()
            return range.location..<NSMaxRange(range)
        }
        set {
            let clamped = min(max(newValue.lowerBound, 0), length)
            let upper = min(max(newValue.upperBound, clamped), length)
            currentTextView?.setSelectedRange(NSRange(location: clamped, length: upper - clamped))
            document.selection = TextSelection(anchor: clamped, head: upper)
        }
    }

    var selectedRanges: [Range<Int>] {
        guard let textView = currentTextView else { return [document.selection.range] }
        return textView.selectedRanges.map { value in
            let range = value.rangeValue
            return range.location..<NSMaxRange(range)
        }
    }

    func string(in range: Range<Int>) -> String {
        let text = document.text as NSString
        let lower = min(max(range.lowerBound, 0), text.length)
        let upper = min(max(range.upperBound, lower), text.length)
        return text.substring(with: NSRange(location: lower, length: upper - lower))
    }

    func replace(range: Range<Int>, with replacement: String) {
        document.applyExternalEdits([TextEdit(range: range, replacement: replacement)])
    }

    func performGrouped(_ body: () -> Void) {
        currentTextView?.undoManager?.beginUndoGrouping()
        body()
        currentTextView?.undoManager?.endUndoGrouping()
    }

    func lineNumber(at offset: Int) -> Int { document.lineNumber(at: offset) }
    func offsetOfLineStart(_ line: Int) -> Int { document.offsetOfLineStart(line) }

    private var currentTextView: InklineTextView? {
        guard workspace?.activeDocument?.id == document.id else { return document.textView }
        return workspace?.activeTextView ?? document.textView
    }
}
