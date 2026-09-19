import Foundation

/// A piece table over UTF-16 code units.
///
/// Why UTF-16: `NSTextView`, `NSRange` and `NSRegularExpression` all speak
/// UTF-16, so using the same unit throughout removes an entire class of
/// index-conversion bugs at the UI boundary.
///
/// Design notes
/// ------------
/// * The *original* buffer is the file as it was loaded and is never mutated.
///   Every insertion is appended to the *added* buffer. Pieces are (source,
///   start, length) triples describing the document as a sequence of spans.
///   Deleting therefore costs nothing but a little bookkeeping, and loading a
///   100 MB file costs exactly one allocation.
/// * Each piece caches the offsets of its line starts plus prefix sums over
///   pieces, so `lineNumber(at:)` and `offsetOfLineStart(_:)` are
///   O(log pieces + log lines-in-piece) rather than a document scan.
/// * Line terminators inside the table are always `\n`. `LineEnding` conversion
///   happens at the I/O boundary (see `FileLoader`), which keeps the table free
///   of CRLF-straddles-two-pieces edge cases.
public struct PieceTable {

    public enum Source: UInt8, Sendable {
        case original
        case added
    }

    struct Piece {
        var source: Source
        /// Offset into the source buffer, in UTF-16 code units.
        var start: Int
        var length: Int
        /// Offsets, relative to the start of the piece, of the code unit that
        /// follows each `\n` in the piece. Sorted ascending.
        var lineStarts: [Int]

        var newlineCount: Int { lineStarts.count }
    }

    // MARK: Storage

    private var original: [UInt16]
    private var added: [UInt16]
    private var pieces: [Piece]

    /// Prefix sums; `pieceOffsets[i]` is the document offset of `pieces[i]`.
    /// Both arrays have `pieces.count + 1` entries, so the last element is the
    /// document length / total newline count.
    private var pieceOffsets: [Int]
    private var pieceNewlines: [Int]

    private var cachedString: String?

    // MARK: Creation

    public init() {
        self.init("")
    }

    public init(_ text: String) {
        original = Array(text.utf16)
        added = []
        if original.isEmpty {
            pieces = []
        } else {
            pieces = [Piece(source: .original,
                            start: 0,
                            length: original.count,
                            lineStarts: Self.lineStarts(in: original[0..<original.count]))]
        }
        pieceOffsets = []
        pieceNewlines = []
        rebuildIndex(from: 0)
    }

    // MARK: Metrics

    /// Document length in UTF-16 code units.
    public var count: Int { pieceOffsets.last ?? 0 }

    public var isEmpty: Bool { count == 0 }

    /// Number of lines. An empty document has one (empty) line; a document that
    /// ends in a newline has a trailing empty line, matching every editor's
    /// line count.
    public var lineCount: Int { (pieceNewlines.last ?? 0) + 1 }

    /// Number of pieces. Exposed for diagnostics and for `compact()` heuristics.
    public var pieceCount: Int { pieces.count }

    // MARK: Reading

    public subscript(range: Range<Int>) -> String {
        string(in: range)
    }

    public var string: String {
        if let cachedString { return cachedString }
        let value = string(in: 0..<count)
        return value
    }

    /// Materialises the whole document and keeps the result around. Call this
    /// when you know the caller will ask again (e.g. handing text to TextKit);
    /// any mutation drops the cache.
    public mutating func materialize() -> String {
        if let cachedString { return cachedString }
        let value = string(in: 0..<count)
        cachedString = value
        return value
    }

    public func string(in range: Range<Int>) -> String {
        let units = codeUnits(in: range)
        guard !units.isEmpty else { return "" }
        return units.withUnsafeBufferPointer { buffer in
            String(utf16CodeUnits: buffer.baseAddress!, count: buffer.count)
        }
    }

    public func codeUnits(in range: Range<Int>) -> [UInt16] {
        precondition(range.lowerBound >= 0 && range.upperBound <= count,
                     "range \(range) out of bounds for document of length \(count)")
        guard !range.isEmpty else { return [] }

        var result = [UInt16]()
        result.reserveCapacity(range.count)

        var index = pieceIndex(containing: range.lowerBound)
        while index < pieces.count {
            let pieceStart = pieceOffsets[index]
            if pieceStart >= range.upperBound { break }
            let piece = pieces[index]
            let pieceEnd = pieceStart + piece.length
            let from = max(range.lowerBound, pieceStart) - pieceStart
            let to = min(range.upperBound, pieceEnd) - pieceStart
            if from < to {
                let buffer = self.buffer(for: piece.source)
                result.append(contentsOf: buffer[(piece.start + from)..<(piece.start + to)])
            }
            index += 1
        }
        return result
    }

    /// The UTF-16 code unit at `offset`.
    public func codeUnit(at offset: Int) -> UInt16 {
        precondition(offset >= 0 && offset < count, "offset \(offset) out of bounds")
        let index = pieceIndex(containing: offset)
        let piece = pieces[index]
        return buffer(for: piece.source)[piece.start + (offset - pieceOffsets[index])]
    }

    // MARK: Mutating

    /// Replaces `range` with `text`. This is the single mutation primitive;
    /// insertion is a replacement of an empty range and deletion a replacement
    /// with an empty string.
    public mutating func replaceSubrange(_ range: Range<Int>, with text: String) {
        precondition(range.lowerBound >= 0 && range.upperBound <= count,
                     "range \(range) out of bounds for document of length \(count)")
        cachedString = nil

        let inserted = Array(text.utf16)

        // Fast path: appending to the end of the add buffer, which is what
        // typing looks like. Extends the last piece instead of creating one.
        if range.isEmpty, !inserted.isEmpty, let lastIndex = pieces.indices.last {
            let last = pieces[lastIndex]
            if last.source == .added,
               range.lowerBound == count,
               last.start + last.length == added.count {
                let relativeBase = last.length
                added.append(contentsOf: inserted)
                pieces[lastIndex].length += inserted.count
                pieces[lastIndex].lineStarts.append(
                    contentsOf: Self.lineStarts(in: inserted[0..<inserted.count]).map { $0 + relativeBase }
                )
                rebuildIndex(from: lastIndex)
                return
            }
        }

        var rebuilt = [Piece]()
        rebuilt.reserveCapacity(pieces.count + 2)

        var firstChangedIndex = pieces.count
        var index = 0
        var appendedInsertion = false

        func appendInsertion() {
            guard !appendedInsertion else { return }
            appendedInsertion = true
            guard !inserted.isEmpty else { return }
            let start = added.count
            added.append(contentsOf: inserted)
            rebuilt.append(Piece(source: .added,
                                 start: start,
                                 length: inserted.count,
                                 lineStarts: Self.lineStarts(in: inserted[0..<inserted.count])))
        }

        while index < pieces.count {
            let piece = pieces[index]
            let pieceStart = pieceOffsets[index]
            let pieceEnd = pieceStart + piece.length

            if pieceEnd <= range.lowerBound {
                rebuilt.append(piece)                      // entirely before
            } else if pieceStart >= range.upperBound {
                if firstChangedIndex == pieces.count { firstChangedIndex = min(firstChangedIndex, rebuilt.count) }
                appendInsertion()
                rebuilt.append(piece)                      // entirely after
            } else {
                firstChangedIndex = min(firstChangedIndex, rebuilt.count)
                // Head of the piece that survives on the left of the range.
                if pieceStart < range.lowerBound {
                    rebuilt.append(subpiece(piece, from: 0, to: range.lowerBound - pieceStart))
                }
                appendInsertion()
                // Tail of the piece that survives on the right of the range.
                if pieceEnd > range.upperBound {
                    rebuilt.append(subpiece(piece, from: range.upperBound - pieceStart, to: piece.length))
                }
            }
            index += 1
        }
        appendInsertion()

        pieces = rebuilt
        rebuildIndex(from: 0)
    }

    public mutating func insert(_ text: String, at offset: Int) {
        replaceSubrange(offset..<offset, with: text)
    }

    public mutating func remove(_ range: Range<Int>) {
        replaceSubrange(range, with: "")
    }

    /// Collapses the table back into a single original piece. Long editing
    /// sessions grow the piece list; call this when `pieceCount` gets silly
    /// (the document model does so above `PieceTable.compactionThreshold`).
    public mutating func compact() {
        let units = codeUnits(in: 0..<count)
        original = units
        added = []
        pieces = units.isEmpty
            ? []
            : [Piece(source: .original,
                     start: 0,
                     length: units.count,
                     lineStarts: Self.lineStarts(in: units[0..<units.count]))]
        rebuildIndex(from: 0)
    }

    public static let compactionThreshold = 4096

    // MARK: Lines

    /// Zero-based line number containing `offset`. An offset equal to `count`
    /// reports the last line.
    public func lineNumber(at offset: Int) -> Int {
        precondition(offset >= 0 && offset <= count, "offset \(offset) out of bounds")
        guard offset > 0, !pieces.isEmpty else { return 0 }
        if offset == count {
            // A document ending in "\n" has a trailing empty line, so the total
            // newline count is exactly the index of the last line.
            return pieceNewlines[pieces.count]
        }
        let index = pieceIndex(containing: offset)
        let relative = offset - pieceOffsets[index]
        let within = upperBound(pieces[index].lineStarts, value: relative)
        return pieceNewlines[index] + within
    }

    /// Offset of the first code unit of `line` (zero-based).
    public func offsetOfLineStart(_ line: Int) -> Int {
        precondition(line >= 0 && line < lineCount, "line \(line) out of bounds (lineCount \(lineCount))")
        guard line > 0 else { return 0 }
        let target = line - 1                      // index of the newline we need
        var lo = 0
        var hi = pieces.count - 1
        var found = pieces.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if pieceNewlines[mid + 1] > target {
                found = mid
                hi = mid - 1
            } else {
                lo = mid + 1
            }
        }
        let withinPiece = target - pieceNewlines[found]
        return pieceOffsets[found] + pieces[found].lineStarts[withinPiece]
    }

    /// Range of `line` including its terminator (if any).
    public func lineRange(_ line: Int) -> Range<Int> {
        let start = offsetOfLineStart(line)
        let end = line + 1 < lineCount ? offsetOfLineStart(line + 1) : count
        return start..<end
    }

    /// Range of `line` excluding its terminator.
    public func lineContentRange(_ line: Int) -> Range<Int> {
        let range = lineRange(line)
        var end = range.upperBound
        if end > range.lowerBound, codeUnit(at: end - 1) == 0x000A { end -= 1 }
        if end > range.lowerBound, codeUnit(at: end - 1) == 0x000D { end -= 1 }
        return range.lowerBound..<end
    }

    public func line(_ line: Int) -> String {
        string(in: lineContentRange(line))
    }

    /// Line/column position (both zero-based) for a document offset.
    public func position(at offset: Int) -> TextPosition {
        let line = lineNumber(at: offset)
        return TextPosition(line: line, column: offset - offsetOfLineStart(line))
    }

    /// Document offset for a line/column position, clamped to the document.
    public func offset(of position: TextPosition) -> Int {
        let line = min(max(position.line, 0), lineCount - 1)
        let content = lineContentRange(line)
        let column = min(max(position.column, 0), content.count)
        return content.lowerBound + column
    }

    // MARK: Index maintenance

    private mutating func rebuildIndex(from startIndex: Int) {
        // Prefix arrays are cheap to rebuild wholesale (one pass over pieces)
        // and the alternative — partial updates — has been a bug farm in every
        // editor that tried it.
        _ = startIndex
        pieceOffsets = [Int](repeating: 0, count: pieces.count + 1)
        pieceNewlines = [Int](repeating: 0, count: pieces.count + 1)
        var offset = 0
        var newlines = 0
        for (index, piece) in pieces.enumerated() {
            pieceOffsets[index] = offset
            pieceNewlines[index] = newlines
            offset += piece.length
            newlines += piece.newlineCount
        }
        pieceOffsets[pieces.count] = offset
        pieceNewlines[pieces.count] = newlines
    }

    /// Index of the piece containing `offset` (which must be < `count`).
    private func pieceIndex(containing offset: Int) -> Int {
        var lo = 0
        var hi = pieces.count - 1
        var result = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if pieceOffsets[mid] <= offset {
                result = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return result
    }

    private func buffer(for source: Source) -> [UInt16] {
        source == .original ? original : added
    }

    private func subpiece(_ piece: Piece, from: Int, to: Int) -> Piece {
        let lower = lowerBound(piece.lineStarts, value: from + 1)   // lineStarts > from
        let upper = upperBound(piece.lineStarts, value: to)         // lineStarts <= to
        let starts = lower < upper ? piece.lineStarts[lower..<upper].map { $0 - from } : []
        return Piece(source: piece.source,
                     start: piece.start + from,
                     length: to - from,
                     lineStarts: starts)
    }

    private static func lineStarts(in units: ArraySlice<UInt16>) -> [Int] {
        var result = [Int]()
        let base = units.startIndex
        for index in units.indices where units[index] == 0x000A {
            result.append(index - base + 1)
        }
        return result
    }

    /// Number of elements `<= value`.
    private func upperBound(_ array: [Int], value: Int) -> Int {
        var lo = 0
        var hi = array.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if array[mid] <= value { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Number of elements `< value`.
    private func lowerBound(_ array: [Int], value: Int) -> Int {
        var lo = 0
        var hi = array.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if array[mid] < value { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

extension PieceTable: CustomStringConvertible {
    public var description: String { "PieceTable(length: \(count), lines: \(lineCount), pieces: \(pieceCount))" }
}
