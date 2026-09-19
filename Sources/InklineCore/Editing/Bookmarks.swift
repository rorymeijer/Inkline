import Foundation

/// Per-line bookmarks, the ones F2 cycles through. Stored as line numbers and
/// shifted when lines are inserted or removed above them, so they survive
/// editing the way users expect.
public struct BookmarkSet: Equatable, Codable, Sendable {
    public private(set) var lines: Set<Int>

    public init(lines: Set<Int> = []) {
        self.lines = lines
    }

    public var isEmpty: Bool { lines.isEmpty }
    public var sorted: [Int] { lines.sorted() }

    public func contains(_ line: Int) -> Bool { lines.contains(line) }

    @discardableResult
    public mutating func toggle(_ line: Int) -> Bool {
        if lines.contains(line) {
            lines.remove(line)
            return false
        }
        lines.insert(line)
        return true
    }

    public mutating func add(_ line: Int) { lines.insert(line) }
    public mutating func remove(_ line: Int) { lines.remove(line) }
    public mutating func removeAll() { lines.removeAll() }

    public func next(after line: Int, wrapping: Bool = true) -> Int? {
        if let next = sorted.first(where: { $0 > line }) { return next }
        return wrapping ? sorted.first : nil
    }

    public func previous(before line: Int, wrapping: Bool = true) -> Int? {
        if let previous = sorted.last(where: { $0 < line }) { return previous }
        return wrapping ? sorted.last : nil
    }

    /// Shifts bookmarks after an edit that replaced `removedLineCount` lines
    /// starting at `startLine` with `insertedLineCount` lines.
    public mutating func adjust(startLine: Int, removedLineCount: Int, insertedLineCount: Int) {
        guard removedLineCount != insertedLineCount else { return }
        let delta = insertedLineCount - removedLineCount
        let removedRange = startLine..<(startLine + removedLineCount)
        var updated = Set<Int>()
        for line in lines {
            if line < startLine {
                updated.insert(line)
            } else if removedRange.contains(line) && delta < 0 {
                continue                                // the line itself was deleted
            } else {
                updated.insert(max(startLine, line + delta))
            }
        }
        lines = updated
    }

    /// Convenience for a `TextChange`: works out the line delta from the text.
    public mutating func adjust(for change: TextChange, startLine: Int) {
        let removed = change.removedText.reduce(into: 0) { $0 += $1 == "\n" ? 1 : 0 }
        let inserted = change.insertedText.reduce(into: 0) { $0 += $1 == "\n" ? 1 : 0 }
        adjust(startLine: startLine, removedLineCount: removed, insertedLineCount: inserted)
    }
}
