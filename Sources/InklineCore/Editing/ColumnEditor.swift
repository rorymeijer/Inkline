import Foundation

/// Rectangular (column/block) selections and the column editor from the Edit
/// menu: insert the same text, or an incrementing number series, at the same
/// column on a range of lines.
public enum ColumnEditor {

    /// A rectangular selection: the same column span on a range of lines.
    public struct Block: Equatable, Sendable {
        public var firstLine: Int
        public var lastLine: Int
        public var startColumn: Int
        public var endColumn: Int

        public init(firstLine: Int, lastLine: Int, startColumn: Int, endColumn: Int) {
            self.firstLine = min(firstLine, lastLine)
            self.lastLine = max(firstLine, lastLine)
            self.startColumn = min(startColumn, endColumn)
            self.endColumn = max(startColumn, endColumn)
        }

        public var lines: ClosedRange<Int> { firstLine...lastLine }
        public var isCaretColumn: Bool { startColumn == endColumn }
    }

    public enum NumberFormat: String, Codable, CaseIterable, Sendable {
        case decimal
        case hexadecimalLower
        case hexadecimalUpper
        case octal
        case binary

        public func string(for value: Int, minimumDigits: Int) -> String {
            let body: String
            switch self {
            case .decimal: body = String(value, radix: 10)
            case .hexadecimalLower: body = String(value, radix: 16)
            case .hexadecimalUpper: body = String(value, radix: 16).uppercased()
            case .octal: body = String(value, radix: 8)
            case .binary: body = String(value, radix: 2)
            }
            guard body.count < minimumDigits else { return body }
            return String(repeating: "0", count: minimumDigits - body.count) + body
        }
    }

    public enum Insertion: Equatable, Sendable {
        case text(String)
        case numbers(start: Int, increment: Int, format: NumberFormat, minimumDigits: Int)
    }

    /// The per-line ranges covered by a block selection; these become the
    /// multiple selection ranges of the text view.
    public static func selectionRanges(for block: Block, in table: PieceTable) -> [Range<Int>] {
        var result = [Range<Int>]()
        for line in block.lines where line < table.lineCount {
            let content = table.lineContentRange(line)
            let length = content.count
            let start = content.lowerBound + min(block.startColumn, length)
            let end = content.lowerBound + min(block.endColumn, length)
            result.append(start..<max(start, end))
        }
        return result
    }

    /// Edits that insert `insertion` at `block.startColumn` on every line of the
    /// block, replacing whatever the block covers. Short lines are padded with
    /// spaces so the column stays a column.
    public static func edits(for insertion: Insertion,
                             block: Block,
                             in table: PieceTable) -> [TextEdit] {
        var edits = [TextEdit]()
        var value = 0
        var increment = 1
        if case let .numbers(start, step, _, _) = insertion {
            value = start
            increment = step
        }

        for line in block.lines where line < table.lineCount {
            let content = table.lineContentRange(line)
            let length = content.count
            let replacement: String
            switch insertion {
            case let .text(text):
                replacement = text
            case let .numbers(_, _, format, minimumDigits):
                replacement = format.string(for: value, minimumDigits: minimumDigits)
                value += increment
            }

            if block.startColumn > length {
                let padding = String(repeating: " ", count: block.startColumn - length)
                edits.append(TextEdit(range: content.upperBound..<content.upperBound,
                                      replacement: padding + replacement))
            } else {
                let start = content.lowerBound + block.startColumn
                let end = content.lowerBound + min(block.endColumn, length)
                edits.append(TextEdit(range: start..<max(start, end), replacement: replacement))
            }
        }
        return edits
    }

    /// The text of a block selection, one line per row — what Copy puts on the
    /// pasteboard for a column selection.
    public static func text(of block: Block, in table: PieceTable) -> String {
        selectionRanges(for: block, in: table)
            .map { table.string(in: $0) }
            .joined(separator: "\n")
    }
}
