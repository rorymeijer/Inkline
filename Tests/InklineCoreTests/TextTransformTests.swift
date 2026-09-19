import XCTest
@testable import InklineCore

final class TextTransformTests: XCTestCase {

    func testCaseTransforms() {
        XCTAssertEqual(TextTransforms.uppercased("hallo"), "HALLO")
        XCTAssertEqual(TextTransforms.lowercased("HALLO"), "hallo")
        XCTAssertEqual(TextTransforms.titleCased("hallo mooie wereld"), "Hallo Mooie Wereld")
        XCTAssertEqual(TextTransforms.sentenceCased("hallo. tweede zin"), "Hallo. Tweede zin")
        XCTAssertEqual(TextTransforms.invertedCase("Hallo"), "hALLO")
    }

    func testSortLines() {
        let text = "banaan\nappel\nCitroen\n"
        XCTAssertEqual(TextTransforms.sortLines(text), "appel\nbanaan\nCitroen\n")
        XCTAssertEqual(TextTransforms.sortLines(text, options: .init(ascending: false)),
                       "Citroen\nbanaan\nappel\n")
    }

    func testSortLinesNumeric() {
        let text = "item10\nitem9\nitem1"
        XCTAssertEqual(TextTransforms.sortLines(text, options: .init(numeric: true)),
                       "item1\nitem9\nitem10")
    }

    func testSortRemovesDuplicatesWhenAsked() {
        let text = "b\na\nb\n"
        XCTAssertEqual(TextTransforms.sortLines(text, options: .init(removesDuplicates: true)), "a\nb\n")
    }

    func testReverseLines() {
        XCTAssertEqual(TextTransforms.reversedLines("een\ntwee\ndrie"), "drie\ntwee\neen")
    }

    func testRemoveDuplicateLines() {
        XCTAssertEqual(TextTransforms.removeDuplicateLines("a\nb\na\nc\nb"), "a\nb\nc")
        XCTAssertEqual(TextTransforms.removeDuplicateLines("a\na\nb\na", adjacentOnly: true), "a\nb\na")
    }

    func testRemoveEmptyLines() {
        XCTAssertEqual(TextTransforms.removeEmptyLines("een\n\n  \ntwee\n"), "een\ntwee\n")
    }

    func testJoinAndSplitLines() {
        XCTAssertEqual(TextTransforms.joinLines("een\ntwee\ndrie"), "een twee drie")
        XCTAssertEqual(TextTransforms.splitLines("aaa bbb ccc", at: 7), "aaa bbb\nccc")
        XCTAssertEqual(TextTransforms.splitLines("aaaaaaaaaa", at: 4), "aaaa\naaaa\naa")
    }

    func testTrimWhitespace() {
        XCTAssertEqual(TextTransforms.trimTrailingWhitespace("een   \ntwee\t\n"), "een\ntwee\n")
        XCTAssertEqual(TextTransforms.trimLeadingWhitespace("  een\n\ttwee"), "een\ntwee")
    }

    func testIndentAndOutdent() {
        XCTAssertEqual(TextTransforms.indent("een\ntwee", using: "  "), "  een\n  twee")
        XCTAssertEqual(TextTransforms.outdent("    een\n\ttwee", indentWidth: 4), "een\ntwee")
        XCTAssertEqual(TextTransforms.indent("een\n\ntwee", using: "\t"), "\teen\n\n\ttwee",
                       "lege regels krijgen geen inspringing")
    }

    func testTabsAndSpaces() {
        XCTAssertEqual(TextTransforms.tabsToSpaces("a\tb", tabWidth: 4), "a   b")
        XCTAssertEqual(TextTransforms.tabsToSpaces("\tx", tabWidth: 4), "    x")
        XCTAssertEqual(TextTransforms.spacesToTabs("    x", tabWidth: 4), "\tx")
        XCTAssertEqual(TextTransforms.spacesToTabs("      x", tabWidth: 4), "\t  x")
    }

    func testBase64() {
        XCTAssertEqual(TextTransforms.base64Encoded("Inkline"), "SW5rbGluZQ==")
        XCTAssertEqual(TextTransforms.base64Decoded("SW5rbGluZQ=="), "Inkline")
        XCTAssertNil(TextTransforms.base64Decoded("/w=="), "bytes die geen UTF-8 zijn")
    }

    func testURLEncoding() {
        XCTAssertEqual(TextTransforms.urlEncoded("a b&c=d"), "a%20b%26c%3Dd")
        XCTAssertEqual(TextTransforms.urlDecoded("a%20b%26c"), "a b&c")
    }

    func testHTMLEncoding() {
        XCTAssertEqual(TextTransforms.htmlEncoded("<a href=\"x\">&</a>"),
                       "&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;")
        XCTAssertEqual(TextTransforms.htmlDecoded("&lt;b&gt;caf&#233;&lt;/b&gt;"), "<b>café</b>")
        XCTAssertEqual(TextTransforms.htmlDecoded("&amp;lt;"), "&lt;")
    }

    func testSplitIntoLinesHandlesTrailingNewline() {
        XCTAssertEqual(TextTransforms.splitIntoLines("a\nb\n"), ["a", "b"])
        XCTAssertEqual(TextTransforms.splitIntoLines("a\nb"), ["a", "b"])
        XCTAssertEqual(TextTransforms.splitIntoLines(""), [])
    }
}
