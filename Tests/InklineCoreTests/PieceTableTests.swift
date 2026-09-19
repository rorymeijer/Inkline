import XCTest
@testable import InklineCore

final class PieceTableTests: XCTestCase {

    func testEmptyTable() {
        let table = PieceTable()
        XCTAssertEqual(table.count, 0)
        XCTAssertEqual(table.lineCount, 1)
        XCTAssertTrue(table.isEmpty)
        XCTAssertEqual(table.string, "")
        XCTAssertEqual(table.lineRange(0), 0..<0)
    }

    func testInitialContent() {
        let table = PieceTable("regel een\nregel twee\n")
        XCTAssertEqual(table.count, 21)
        XCTAssertEqual(table.lineCount, 3)          // trailing newline opens a third, empty line
        XCTAssertEqual(table.line(0), "regel een")
        XCTAssertEqual(table.line(1), "regel twee")
        XCTAssertEqual(table.line(2), "")
    }

    func testInsertAtEndCoalesces() {
        var table = PieceTable("abc")
        for character in "def" {
            table.insert(String(character), at: table.count)
        }
        XCTAssertEqual(table.string, "abcdef")
        // The append fast path must not create a piece per keystroke.
        XCTAssertLessThanOrEqual(table.pieceCount, 2)
    }

    func testInsertInMiddle() {
        var table = PieceTable("hallo wereld")
        table.insert("mooie ", at: 6)
        XCTAssertEqual(table.string, "hallo mooie wereld")
        XCTAssertEqual(table.count, 18)
    }

    func testDeleteAcrossPieces() {
        var table = PieceTable("een twee drie")
        table.insert("XX", at: 4)                   // "een XXtwee drie"
        table.remove(2..<9)                         // removes "n XXtwe"
        XCTAssertEqual(table.string, "eee drie")
    }

    func testReplaceWholeDocument() {
        var table = PieceTable("oud")
        table.replaceSubrange(0..<3, with: "nieuw")
        XCTAssertEqual(table.string, "nieuw")
        XCTAssertEqual(table.lineCount, 1)
    }

    func testLineLookupAfterEdits() {
        var table = PieceTable("a\nb\nc")
        XCTAssertEqual(table.lineNumber(at: 0), 0)
        XCTAssertEqual(table.lineNumber(at: 2), 1)
        XCTAssertEqual(table.lineNumber(at: 4), 2)

        table.insert("\nX", at: 1)                  // "a\nX\nb\nc"
        XCTAssertEqual(table.string, "a\nX\nb\nc")
        XCTAssertEqual(table.lineCount, 4)
        XCTAssertEqual(table.line(1), "X")
        XCTAssertEqual(table.lineNumber(at: table.count), 3)
    }

    func testLineRangesAndPositions() {
        let table = PieceTable("een\ntwee\ndrie")
        XCTAssertEqual(table.lineRange(0), 0..<4)
        XCTAssertEqual(table.lineContentRange(0), 0..<3)
        XCTAssertEqual(table.lineRange(2), 9..<13)

        XCTAssertEqual(table.position(at: 5), TextPosition(line: 1, column: 1))
        XCTAssertEqual(table.offset(of: TextPosition(line: 1, column: 1)), 5)
        XCTAssertEqual(table.offset(of: TextPosition(line: 1, column: 99)), 8)   // clamped to line end
        XCTAssertEqual(table.offset(of: TextPosition(line: 99, column: 0)), 9)   // clamped to last line
    }

    func testStringInRange() {
        var table = PieceTable("abcdef")
        table.insert("123", at: 3)
        XCTAssertEqual(table.string(in: 2..<7), "c123d")
        XCTAssertEqual(table.string(in: 0..<0), "")
        XCTAssertEqual(table.string(in: 0..<table.count), "abc123def")
    }

    func testCompactPreservesContentAndLines() {
        var table = PieceTable("een\ntwee")
        for index in 0..<50 {
            table.insert("\(index)\n", at: index % max(1, table.count))
        }
        let before = table.string
        let linesBefore = table.lineCount
        table.compact()
        XCTAssertEqual(table.string, before)
        XCTAssertEqual(table.lineCount, linesBefore)
        XCTAssertEqual(table.pieceCount, 1)
    }

    func testRandomEditsMatchReferenceImplementation() {
        // The piece table must behave exactly like NSMutableString for any
        // sequence of edits; this is the property that everything else relies on.
        var table = PieceTable("start\ntekst\n")
        let reference = NSMutableString(string: "start\ntekst\n")
        var generator = SystemRandomNumberGenerator()
        let samples = ["x", "hallo", "\n", "ab\ncd", "", "é", "→"]

        for _ in 0..<400 {
            let length = reference.length
            let lower = Int.random(in: 0...length, using: &generator)
            let upper = Int.random(in: lower...length, using: &generator)
            let replacement = samples.randomElement(using: &generator)!

            table.replaceSubrange(lower..<upper, with: replacement)
            reference.replaceCharacters(in: NSRange(location: lower, length: upper - lower),
                                        with: replacement)

            XCTAssertEqual(table.count, reference.length)
        }
        XCTAssertEqual(table.string, reference as String)

        // And the line index must agree with a naive count.
        let expectedLines = (table.string.filter { $0 == "\n" }.count) + 1
        XCTAssertEqual(table.lineCount, expectedLines)
        for line in 0..<table.lineCount {
            let range = table.lineContentRange(line)
            XCTAssertEqual(table.lineNumber(at: range.lowerBound), line)
        }
    }

    func testUnicodeOutsideBasicPlane() {
        // An emoji is two UTF-16 code units; offsets must count units, not
        // characters, because that is what NSTextView hands us.
        var table = PieceTable("a😀b")
        XCTAssertEqual(table.count, 4)
        XCTAssertEqual(table.string(in: 1..<3), "😀")
        table.insert("!", at: 3)
        XCTAssertEqual(table.string, "a😀!b")
    }
}
