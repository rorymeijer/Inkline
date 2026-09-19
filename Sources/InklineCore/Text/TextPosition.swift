import Foundation

/// A zero-based line/column pair. Columns count UTF-16 code units, which is
/// what the status bar reports as "Kolom" after adding one.
public struct TextPosition: Hashable, Codable, Sendable, Comparable {
    public var line: Int
    public var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    public static let zero = TextPosition(line: 0, column: 0)

    public static func < (lhs: TextPosition, rhs: TextPosition) -> Bool {
        lhs.line == rhs.line ? lhs.column < rhs.column : lhs.line < rhs.line
    }

    /// One-based description for humans: `12:5`.
    public var displayDescription: String { "\(line + 1):\(column + 1)" }
}

/// A selection in a document. `anchor` is where the drag started, `head` where
/// the caret is; keeping both lets multi-cursor editing extend selections in
/// the direction the user expects.
public struct TextSelection: Hashable, Codable, Sendable {
    public var anchor: Int
    public var head: Int

    public init(anchor: Int, head: Int) {
        self.anchor = anchor
        self.head = head
    }

    public init(caret: Int) {
        self.init(anchor: caret, head: caret)
    }

    public init(range: Range<Int>) {
        self.init(anchor: range.lowerBound, head: range.upperBound)
    }

    public var range: Range<Int> { min(anchor, head)..<max(anchor, head) }
    public var isCaret: Bool { anchor == head }
    public var length: Int { abs(head - anchor) }

    public func clamped(to length: Int) -> TextSelection {
        TextSelection(anchor: min(max(anchor, 0), length), head: min(max(head, 0), length))
    }
}
