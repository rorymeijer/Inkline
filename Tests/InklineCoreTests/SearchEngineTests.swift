import XCTest
@testable import InklineCore

final class SearchEngineTests: XCTestCase {

    private let text = "Een kat zat op de mat.\nDe KAT sliep.\nkatten slapen veel.\n"

    func testLiteralSearchIsCaseInsensitiveByDefault() throws {
        let query = SearchQuery(pattern: "kat")
        let matches = try SearchEngine.matches(of: query, in: text)
        XCTAssertEqual(matches.count, 3)
    }

    func testCaseSensitiveSearch() throws {
        let query = SearchQuery(pattern: "KAT", isCaseSensitive: true)
        XCTAssertEqual(try SearchEngine.count(of: query, in: text), 1)
    }

    func testWholeWordSearch() throws {
        let query = SearchQuery(pattern: "kat", matchesWholeWords: true)
        let matches = try SearchEngine.matches(of: query, in: text)
        XCTAssertEqual(matches.count, 2, "katten is geen heel woord")
    }

    func testLiteralSearchEscapesRegexMetacharacters() throws {
        let query = SearchQuery(pattern: "a.c")
        XCTAssertEqual(try SearchEngine.count(of: query, in: "abc a.c axc"), 1)
    }

    func testRegularExpressionSearchWithGroups() throws {
        let query = SearchQuery(pattern: #"(\w+)@(\w+)\.nl"#, isRegularExpression: true)
        let matches = try SearchEngine.matches(of: query, in: "mail rory@rorymeijer.nl nu")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].captureGroups.count, 3)
        XCTAssertEqual(matches[0].captureGroups[1], 5..<9)
    }

    func testInvalidRegularExpressionThrows() {
        let query = SearchQuery(pattern: "(onafgesloten", isRegularExpression: true)
        XCTAssertThrowsError(try SearchEngine.matches(of: query, in: text))
    }

    func testEmptyPatternThrows() {
        XCTAssertThrowsError(try SearchEngine.matches(of: SearchQuery(pattern: ""), in: text)) { error in
            XCTAssertEqual(error as? SearchError, .emptyPattern)
        }
    }

    func testFindNextWrapsAround() throws {
        let query = SearchQuery(pattern: "kat", wrapsAround: true)
        // Offset 40 is past the last match, so the search wraps to the first.
        let match = try XCTUnwrap(SearchEngine.firstMatch(of: query, in: text, from: 40))
        XCTAssertEqual(match.range.lowerBound, 4)
    }

    func testFindNextWithoutWrapReturnsNil() throws {
        let query = SearchQuery(pattern: "kat", wrapsAround: false)
        XCTAssertNil(try SearchEngine.firstMatch(of: query, in: text, from: text.utf16.count))
    }

    func testFindPrevious() throws {
        let query = SearchQuery(pattern: "kat")
        let match = try XCTUnwrap(SearchEngine.firstMatch(of: query, in: text, from: 30, direction: .backward))
        XCTAssertEqual(match.range.lowerBound, 26, "de laatste treffer vóór offset 30 is KAT")
    }

    func testReplaceAllLiteral() throws {
        let result = try SearchEngine.replaceAll(query: SearchQuery(pattern: "kat"),
                                                 in: text,
                                                 with: "hond")
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.text.contains("hond zat"))
        XCTAssertTrue(result.text.contains("hondten"))
    }

    func testReplaceAllWithCaptureGroups() throws {
        let query = SearchQuery(pattern: #"(\d{4})-(\d{2})-(\d{2})"#, isRegularExpression: true)
        let result = try SearchEngine.replaceAll(query: query,
                                                 in: "datum 2026-09-19 einde",
                                                 with: "$3/$2/$1")
        XCTAssertEqual(result.text, "datum 19/09/2026 einde")
        XCTAssertEqual(result.edits.count, 1)
        XCTAssertEqual(result.edits[0].range, 6..<16)
    }

    func testReplaceAllWithinRange() throws {
        let result = try SearchEngine.replaceAll(query: SearchQuery(pattern: "a"),
                                                 in: "aaa aaa",
                                                 with: "b",
                                                 range: 0..<3)
        XCTAssertEqual(result.text, "bbb aaa")
    }

    func testEscapeSequencesInExtendedMode() throws {
        let query = SearchQuery(pattern: #"\t"#, usesEscapeSequences: true)
        XCTAssertEqual(try SearchEngine.count(of: query, in: "een\ttwee"), 1)

        let result = try SearchEngine.replaceAll(query: SearchQuery(pattern: ";", usesEscapeSequences: true),
                                                 in: "a;b",
                                                 with: #";\n"#)
        XCTAssertEqual(result.text, "a;\nb")
    }

    func testExpandEscapeSequences() {
        XCTAssertEqual(SearchEngine.expandEscapeSequences(#"a\tb\nc\\d"#), "a\tb\nc\\d")
        XCTAssertEqual(SearchEngine.expandEscapeSequences(#"\x41B"#), "AB")
        XCTAssertEqual(SearchEngine.expandEscapeSequences(#"\q"#), #"\q"#)
    }

    func testMultilineRegularExpression() throws {
        let query = SearchQuery(pattern: #"^De .*$"#, isRegularExpression: true)
        XCTAssertEqual(try SearchEngine.count(of: query, in: text), 1)
    }
}
