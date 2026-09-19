import Foundation

/// A single replacement expressed in coordinates of the document *before* it is
/// applied.
public struct TextEdit: Equatable, Sendable {
    public var range: Range<Int>
    public var replacement: String

    public init(range: Range<Int>, replacement: String) {
        self.range = range
        self.replacement = replacement
    }

    public static func insert(_ text: String, at offset: Int) -> TextEdit {
        TextEdit(range: offset..<offset, replacement: text)
    }

    public static func delete(_ range: Range<Int>) -> TextEdit {
        TextEdit(range: range, replacement: "")
    }

    /// How much the document grows (or shrinks) when this edit is applied.
    public var delta: Int { replacement.utf16.count - range.count }
}

/// What actually happened, including the text that was removed. Enough to undo
/// the edit and to tell observers which part of the document to re-highlight.
public struct TextChange: Equatable, Sendable {
    public let editedRange: Range<Int>      // range before the edit
    public let removedText: String
    public let insertedText: String

    public init(editedRange: Range<Int>, removedText: String, insertedText: String) {
        self.editedRange = editedRange
        self.removedText = removedText
        self.insertedText = insertedText
    }

    public var delta: Int { insertedText.utf16.count - removedText.utf16.count }

    /// Range covered by the *new* text after the edit.
    public var newRange: Range<Int> {
        editedRange.lowerBound..<(editedRange.lowerBound + insertedText.utf16.count)
    }

    public var inverse: TextEdit {
        TextEdit(range: newRange, replacement: removedText)
    }
}

/// Applying a batch of edits at once (multi-cursor, "replace all", macros)
/// requires them to be sorted and non-overlapping; this normalises a batch.
public enum TextEditBatch {
    public static func normalized(_ edits: [TextEdit]) -> [TextEdit] {
        let sorted = edits.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var result = [TextEdit]()
        for edit in sorted {
            if let last = result.last, edit.range.lowerBound < last.range.upperBound {
                continue    // overlapping edit: first one wins
            }
            result.append(edit)
        }
        return result
    }
}
