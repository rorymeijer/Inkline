import Foundation

/// The mutable document text: a piece table plus undo/redo and change
/// notifications. Deliberately UI-agnostic — the AppKit layer mirrors these
/// changes into an `NSTextStorage`, and headless callers (macros, plugins,
/// "replace in all open tabs", tests) drive the very same type.
public final class TextBuffer {

    public struct ObserverToken: Hashable {
        fileprivate let value: Int
    }

    /// Undo groups are coalesced while the user keeps typing in the same place.
    public struct UndoCoalescing: Equatable, Sendable {
        public var maximumInterval: TimeInterval
        public var enabled: Bool

        public init(enabled: Bool = true, maximumInterval: TimeInterval = 0.8) {
            self.enabled = enabled
            self.maximumInterval = maximumInterval
        }

        public static let `default` = UndoCoalescing()
        public static let disabled = UndoCoalescing(enabled: false)
    }

    private struct UndoGroup {
        var edits: [TextEdit]          // inverse edits, newest last
        var selectionBefore: [TextSelection]
        var selectionAfter: [TextSelection]
        var timestamp: Date
        var endOffset: Int             // where the last edit finished, for coalescing
    }

    private var table: PieceTable
    private var undoStack: [UndoGroup] = []
    private var redoStack: [UndoGroup] = []
    private var observers: [Int: (TextChange) -> Void] = [:]
    private var nextObserverID = 0
    private var groupingDepth = 0
    private var pendingGroup: UndoGroup?

    public var coalescing: UndoCoalescing = .default
    public var maximumUndoDepth = 512

    /// Selections owned by the UI, kept here so undo can restore them.
    public var selections: [TextSelection] = [TextSelection(caret: 0)]

    public init(text: String = "") {
        table = PieceTable(text)
    }

    // MARK: Reading

    public var text: String { table.materialize() }
    public var length: Int { table.count }
    public var lineCount: Int { table.lineCount }
    public var isEmpty: Bool { table.isEmpty }

    public func string(in range: Range<Int>) -> String { table.string(in: range) }
    public func line(_ index: Int) -> String { table.line(index) }
    public func lineRange(_ index: Int) -> Range<Int> { table.lineRange(index) }
    public func lineContentRange(_ index: Int) -> Range<Int> { table.lineContentRange(index) }
    public func lineNumber(at offset: Int) -> Int { table.lineNumber(at: offset) }
    public func offsetOfLineStart(_ line: Int) -> Int { table.offsetOfLineStart(line) }
    public func position(at offset: Int) -> TextPosition { table.position(at: offset) }
    public func offset(of position: TextPosition) -> Int { table.offset(of: position) }
    public func codeUnit(at offset: Int) -> UInt16 { table.codeUnit(at: offset) }

    /// Range of the lines touched by `range`, terminators included — the unit
    /// most line-based commands (sort, indent, comment) work on.
    public func lineSpan(covering range: Range<Int>) -> Range<Int> {
        let firstLine = lineNumber(at: range.lowerBound)
        let lastLine = lineNumber(at: max(range.lowerBound, range.upperBound))
        return lineRange(firstLine).lowerBound..<lineRange(lastLine).upperBound
    }

    // MARK: Observing

    @discardableResult
    public func addObserver(_ handler: @escaping (TextChange) -> Void) -> ObserverToken {
        nextObserverID += 1
        observers[nextObserverID] = handler
        return ObserverToken(value: nextObserverID)
    }

    public func removeObserver(_ token: ObserverToken) {
        observers.removeValue(forKey: token.value)
    }

    // MARK: Editing

    @discardableResult
    public func replace(_ range: Range<Int>, with replacement: String) -> TextChange {
        apply(TextEdit(range: range, replacement: replacement), recordUndo: true)
    }

    /// Applies a batch as a single undo step, adjusting later offsets for the
    /// edits already applied. Used by multi-cursor typing and "replace all".
    @discardableResult
    public func applyBatch(_ edits: [TextEdit]) -> [TextChange] {
        let normalized = TextEditBatch.normalized(edits)
        guard !normalized.isEmpty else { return [] }
        beginUndoGroup()
        defer { endUndoGroup() }

        var delta = 0
        var changes = [TextChange]()
        for edit in normalized {
            let shifted = Range(uncheckedBounds: (edit.range.lowerBound + delta, edit.range.upperBound + delta))
            let change = apply(TextEdit(range: shifted, replacement: edit.replacement), recordUndo: true)
            delta += change.delta
            changes.append(change)
        }
        return changes
    }

    @discardableResult
    private func apply(_ edit: TextEdit, recordUndo: Bool) -> TextChange {
        let clamped = Range(uncheckedBounds: (min(max(edit.range.lowerBound, 0), table.count),
                                              min(max(edit.range.upperBound, 0), table.count)))
        let removed = table.string(in: clamped)
        let change = TextChange(editedRange: clamped,
                                removedText: removed,
                                insertedText: edit.replacement)

        table.replaceSubrange(clamped, with: edit.replacement)
        if table.pieceCount > PieceTable.compactionThreshold {
            table.compact()
        }

        if recordUndo {
            record(inverse: change.inverse, at: change.newRange.upperBound)
            redoStack.removeAll(keepingCapacity: true)
        }

        for handler in observers.values { handler(change) }
        return change
    }

    public func setText(_ newText: String) {
        replace(0..<length, with: newText)
    }

    /// Replaces the contents without touching the undo stack — used when a file
    /// is (re)loaded from disk.
    public func reset(to newText: String) {
        let change = TextChange(editedRange: 0..<table.count,
                                removedText: table.materialize(),
                                insertedText: newText)
        table = PieceTable(newText)
        undoStack.removeAll()
        redoStack.removeAll()
        pendingGroup = nil
        selections = [TextSelection(caret: 0)]
        for handler in observers.values { handler(change) }
    }

    // MARK: Undo / redo

    public var canUndo: Bool { !undoStack.isEmpty || pendingGroup != nil }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func beginUndoGroup() {
        if groupingDepth == 0 { flushPendingGroup() }
        groupingDepth += 1
    }

    public func endUndoGroup() {
        groupingDepth = max(0, groupingDepth - 1)
        if groupingDepth == 0 { flushPendingGroup() }
    }

    private func record(inverse: TextEdit, at endOffset: Int) {
        let now = Date()
        if var group = pendingGroup,
           groupingDepth > 0
            || (coalescing.enabled
                && now.timeIntervalSince(group.timestamp) < coalescing.maximumInterval
                && abs(group.endOffset - inverse.range.lowerBound) <= 1) {
            group.edits.append(inverse)
            group.timestamp = now
            group.endOffset = endOffset
            group.selectionAfter = selections
            pendingGroup = group
        } else {
            flushPendingGroup()
            pendingGroup = UndoGroup(edits: [inverse],
                                     selectionBefore: selections,
                                     selectionAfter: selections,
                                     timestamp: now,
                                     endOffset: endOffset)
        }
    }

    private func flushPendingGroup() {
        guard let group = pendingGroup else { return }
        pendingGroup = nil
        undoStack.append(group)
        if undoStack.count > maximumUndoDepth {
            undoStack.removeFirst(undoStack.count - maximumUndoDepth)
        }
    }

    @discardableResult
    public func undo() -> [TextSelection]? {
        flushPendingGroup()
        guard let group = undoStack.popLast() else { return nil }
        var redoEdits = [TextEdit]()
        for edit in group.edits.reversed() {
            let change = apply(edit, recordUndo: false)
            redoEdits.append(change.inverse)
        }
        redoStack.append(UndoGroup(edits: redoEdits.reversed(),
                                   selectionBefore: group.selectionAfter,
                                   selectionAfter: group.selectionBefore,
                                   timestamp: Date(),
                                   endOffset: group.endOffset))
        selections = group.selectionBefore.map { $0.clamped(to: length) }
        return selections
    }

    @discardableResult
    public func redo() -> [TextSelection]? {
        guard let group = redoStack.popLast() else { return nil }
        var undoEdits = [TextEdit]()
        for edit in group.edits.reversed() {
            let change = apply(edit, recordUndo: false)
            undoEdits.append(change.inverse)
        }
        undoStack.append(UndoGroup(edits: undoEdits.reversed(),
                                   selectionBefore: group.selectionAfter,
                                   selectionAfter: group.selectionBefore,
                                   timestamp: Date(),
                                   endOffset: group.endOffset))
        selections = group.selectionBefore.map { $0.clamped(to: length) }
        return selections
    }

    /// Snapshot for background work (highlighting, find-in-files over open
    /// documents) that must not see half-applied edits.
    public func snapshot() -> TextSnapshot {
        TextSnapshot(text: table.materialize(), length: table.count, lineCount: table.lineCount)
    }
}

public struct TextSnapshot: Sendable {
    public let text: String
    public let length: Int
    public let lineCount: Int
}
