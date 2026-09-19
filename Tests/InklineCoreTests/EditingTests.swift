import XCTest
@testable import InklineCore

final class BracketMatcherTests: XCTestCase {

    func testMatchesForward() {
        let table = PieceTable("func doe(a: [Int]) {}")
        let match = BracketMatcher.match(at: 8, in: table)
        XCTAssertEqual(match?.origin, 8)
        XCTAssertEqual(match?.counterpart, 17)
    }

    func testMatchesBackwardFromClosingBracket() {
        let table = PieceTable("(een (twee) drie)")
        let match = BracketMatcher.match(at: 16, in: table)
        XCTAssertEqual(match?.counterpart, 0)
    }

    func testCaretAfterBracketAlsoMatches() {
        let table = PieceTable("{abc}")
        // Caret sits just after "}"; editors match the bracket to the left.
        XCTAssertEqual(BracketMatcher.match(at: 5, in: table)?.counterpart, 0)
    }

    func testUnbalancedReturnsNil() {
        let table = PieceTable("(een twee")
        XCTAssertNil(BracketMatcher.match(at: 0, in: table))
    }

    func testIgnoredRangesAreSkipped() {
        let table = PieceTable("(\"}\" )")           // the } lives inside a string
        let match = BracketMatcher.match(at: 0, in: table, ignoredRanges: [1..<4])
        XCTAssertEqual(match?.counterpart, 5)
    }

    func testEnclosingPair() {
        let table = PieceTable("aaa { bbb { ccc } ddd } eee")
        XCTAssertEqual(BracketMatcher.enclosingPair(at: 13, in: table), 10..<17)
    }
}

final class IndentationEngineTests: XCTestCase {

    private let engine = IndentationEngine(settings: IndentationSettings(usesTabs: false, indentWidth: 4))

    func testKeepsIndentation() {
        XCTAssertEqual(engine.indentation(after: "    let x = 1"), "    ")
    }

    func testIncreasesAfterOpeningBrace() {
        XCTAssertEqual(engine.indentation(after: "    func doe() {"), "        ")
    }

    func testReindentsClosingBrace() {
        XCTAssertEqual(engine.reindentation(for: "        }", previousLine: "        let x = 1"), "    ")
        XCTAssertNil(engine.reindentation(for: "    let x = 1", previousLine: "    let y = 2"))
    }

    func testTabIndentation() {
        let tabEngine = IndentationEngine(settings: IndentationSettings(usesTabs: true, indentWidth: 4, tabWidth: 4))
        XCTAssertEqual(tabEngine.indentation(after: "\tif x {"), "\t\t")
    }

    func testVisualWidthHonoursTabStops() {
        let settings = IndentationSettings(usesTabs: true, indentWidth: 4, tabWidth: 8)
        XCTAssertEqual(settings.visualWidth(of: "\t"), 8)
        XCTAssertEqual(settings.visualWidth(of: "  \t"), 8)
        XCTAssertEqual(settings.visualWidth(of: "\t  "), 10)
    }

    func testBracketPairExpansion() {
        XCTAssertTrue(engine.shouldExpandBracketPair(before: "{", after: "}"))
        XCTAssertFalse(engine.shouldExpandBracketPair(before: "{", after: "]"))
        XCTAssertFalse(engine.shouldExpandBracketPair(before: nil, after: "}"))
    }
}

final class FoldingTests: XCTestCase {

    func testBracketFolding() {
        let table = PieceTable("func a() {\n    let x = 1\n}\nfunc b() {\n}\n")
        let regions = FoldingCalculator.regions(in: table, strategy: .brackets)
        XCTAssertEqual(regions.first?.startLine, 0)
        XCTAssertEqual(regions.first?.endLine, 1)
    }

    func testIndentationFolding() {
        let table = PieceTable("def a():\n    x = 1\n    y = 2\ndef b():\n    pass\n")
        let regions = FoldingCalculator.regions(in: table, strategy: .indentation)
        XCTAssertTrue(regions.contains { $0.startLine == 0 && $0.endLine == 2 })
        XCTAssertTrue(regions.contains { $0.startLine == 3 && $0.endLine == 4 })
    }

    func testFoldingStateHidesLines() {
        var state = FoldingState()
        state.update(regions: [FoldRegion(startLine: 0, endLine: 3, level: 0),
                               FoldRegion(startLine: 5, endLine: 6, level: 0)])
        XCTAssertTrue(state.toggle(at: 0))
        XCTAssertEqual(state.hiddenLines, [1...3])
        XCTAssertTrue(state.isHidden(line: 2))
        XCTAssertFalse(state.isHidden(line: 0))

        state.collapseAll()
        XCTAssertEqual(state.hiddenLines.count, 2)
        state.expandAll()
        XCTAssertTrue(state.hiddenLines.isEmpty)
    }

    func testTogglingUnknownLineDoesNothing() {
        var state = FoldingState()
        state.update(regions: [])
        XCTAssertFalse(state.toggle(at: 4))
    }
}

final class BookmarkTests: XCTestCase {

    func testToggleAndNavigate() {
        var bookmarks = BookmarkSet()
        XCTAssertTrue(bookmarks.toggle(3))
        bookmarks.add(10)
        XCTAssertEqual(bookmarks.next(after: 3), 10)
        XCTAssertEqual(bookmarks.next(after: 10), 3, "wrapt naar de eerste")
        XCTAssertEqual(bookmarks.previous(before: 10), 3)
        XCTAssertFalse(bookmarks.toggle(3))
        XCTAssertEqual(bookmarks.sorted, [10])
    }

    func testAdjustForInsertedLines() {
        var bookmarks = BookmarkSet(lines: [2, 5, 9])
        bookmarks.adjust(startLine: 3, removedLineCount: 0, insertedLineCount: 2)
        XCTAssertEqual(bookmarks.sorted, [2, 7, 11])
    }

    func testAdjustForRemovedLines() {
        var bookmarks = BookmarkSet(lines: [2, 5, 9])
        bookmarks.adjust(startLine: 4, removedLineCount: 3, insertedLineCount: 0)
        XCTAssertEqual(bookmarks.sorted, [2, 6], "de bladwijzer op regel 5 verdwijnt met zijn regel")
    }
}

final class ColumnEditorTests: XCTestCase {

    func testSelectionRangesClampShortLines() {
        let table = PieceTable("langere regel\nkort\nook langere regel")
        let block = ColumnEditor.Block(firstLine: 0, lastLine: 2, startColumn: 2, endColumn: 6)
        let ranges = ColumnEditor.selectionRanges(for: block, in: table)
        XCTAssertEqual(ranges[0], 2..<6)
        XCTAssertEqual(ranges[1], 16..<18, "regel 'kort' is maar 4 tekens lang")
    }

    func testInsertTextInColumn() {
        var table = PieceTable("aaa\nbbb\nccc")
        let block = ColumnEditor.Block(firstLine: 0, lastLine: 2, startColumn: 1, endColumn: 1)
        let edits = ColumnEditor.edits(for: .text("-"), block: block, in: table)
        XCTAssertEqual(edits.count, 3)
        applyInReverse(edits, to: &table)
        XCTAssertEqual(table.string, "a-aa\nb-bb\nc-cc")
    }

    func testInsertNumberSeries() {
        var table = PieceTable("a\nb\nc")
        let block = ColumnEditor.Block(firstLine: 0, lastLine: 2, startColumn: 0, endColumn: 0)
        let edits = ColumnEditor.edits(for: .numbers(start: 8, increment: 2, format: .decimal, minimumDigits: 2),
                                       block: block,
                                       in: table)
        applyInReverse(edits, to: &table)
        XCTAssertEqual(table.string, "08a\n10b\n12c")
    }

    func testShortLinesArePaddedWithSpaces() {
        var table = PieceTable("aaaa\nb")
        let block = ColumnEditor.Block(firstLine: 0, lastLine: 1, startColumn: 4, endColumn: 4)
        let edits = ColumnEditor.edits(for: .text("!"), block: block, in: table)
        applyInReverse(edits, to: &table)
        XCTAssertEqual(table.string, "aaaa!\nb   !")
    }

    func testBlockText() {
        let table = PieceTable("abcdef\nghijkl")
        let block = ColumnEditor.Block(firstLine: 0, lastLine: 1, startColumn: 1, endColumn: 4)
        XCTAssertEqual(ColumnEditor.text(of: block, in: table), "bcd\nhij")
    }

    private func applyInReverse(_ edits: [TextEdit], to table: inout PieceTable) {
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            table.replaceSubrange(edit.range, with: edit.replacement)
        }
    }
}
