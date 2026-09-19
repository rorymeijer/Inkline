import XCTest
@testable import InklineCore

final class EncodingTests: XCTestCase {

    func testDetectsUTF8BOM() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("hallo".utf8))
        let detection = EncodingDetector.detect(data)
        XCTAssertEqual(detection.encoding, .utf8BOM)
        XCTAssertEqual(detection.byteOrderMarkLength, 3)
        XCTAssertEqual(detection.confidence, .certain)
    }

    func testDetectsUTF16WithBOM() {
        let leData = Data([0xFF, 0xFE]) + "hallo".data(using: .utf16LittleEndian)!
        XCTAssertEqual(EncodingDetector.detect(leData).encoding, .utf16LEWithBOM)

        let beData = Data([0xFE, 0xFF]) + "hallo".data(using: .utf16BigEndian)!
        XCTAssertEqual(EncodingDetector.detect(beData).encoding, .utf16BEWithBOM)
    }

    func testUTF32BOMIsNotMistakenForUTF16() {
        let data = Data([0xFF, 0xFE, 0x00, 0x00]) + Data([0x41, 0x00, 0x00, 0x00])
        XCTAssertEqual(EncodingDetector.detect(data).encoding, .utf32LEWithBOM)
    }

    func testDetectsBOMlessUTF16() {
        let text = String(repeating: "abcdefgh", count: 8)
        let data = text.data(using: .utf16LittleEndian)!
        XCTAssertEqual(EncodingDetector.detect(data).encoding, .utf16LE)
    }

    func testDetectsUTF8WithoutBOM() {
        let data = Data("café — naïve — Ω".utf8)
        let detection = EncodingDetector.detect(data)
        XCTAssertEqual(detection.encoding, .utf8)
        XCTAssertEqual(detection.confidence, .high)
    }

    func testFallsBackToSingleByteEncoding() {
        // 0xE9 alone is "é" in Latin-1 but invalid UTF-8.
        let data = Data([0x63, 0x61, 0x66, 0xE9])
        let detection = EncodingDetector.detect(data)
        XCTAssertEqual(detection.encoding, .windowsCP1252)
        XCTAssertEqual(detection.confidence, .low)
    }

    func testRejectsOverlongAndSurrogateEncodings() {
        XCTAssertFalse(EncodingDetector.isValidUTF8(Data([0xC0, 0xAF])))          // overlong "/"
        XCTAssertFalse(EncodingDetector.isValidUTF8(Data([0xED, 0xA0, 0x80])))    // surrogate
        XCTAssertFalse(EncodingDetector.isValidUTF8(Data([0xF5, 0x80, 0x80, 0x80])))
        XCTAssertTrue(EncodingDetector.isValidUTF8(Data("ok ✓".utf8)))
    }

    func testTruncatedTailIsToleratedForLargeFiles() {
        let euro = Data([0xE2, 0x82])   // first two bytes of "€"
        XCTAssertFalse(EncodingDetector.isValidUTF8(euro, allowTruncatedTail: false))
        XCTAssertTrue(EncodingDetector.isValidUTF8(euro, allowTruncatedTail: true))
    }

    func testDecodeNormalisesLineEndings() throws {
        let data = Data("een\r\ntwee\r\ndrie".utf8)
        let document = try FileLoader.decode(data)
        XCTAssertEqual(document.text, "een\ntwee\ndrie")
        XCTAssertEqual(document.lineEnding, .crlf)
        XCTAssertFalse(document.hasMixedLineEndings)
    }

    func testMixedLineEndingsAreReported() throws {
        let document = try FileLoader.decode(Data("een\r\ntwee\ndrie\r".utf8))
        XCTAssertTrue(document.hasMixedLineEndings)
    }

    func testEncodeRoundTrip() throws {
        let text = "een\ntwee\n"
        let data = try FileLoader.encode(text, encoding: .utf8BOM, lineEnding: .crlf)
        XCTAssertEqual([UInt8](data.prefix(3)), [0xEF, 0xBB, 0xBF])
        let reloaded = try FileLoader.decode(data)
        XCTAssertEqual(reloaded.text, text)
        XCTAssertEqual(reloaded.encoding, .utf8BOM)
        XCTAssertEqual(reloaded.lineEnding, .crlf)
    }

    func testSaveOptionsTrimAndTerminate() throws {
        let data = try FileLoader.encode("een   \ntwee\t\n\nvier",
                                         encoding: .utf8,
                                         lineEnding: .lf,
                                         options: SaveOptions(trimTrailingWhitespace: true,
                                                              ensureTrailingNewline: true))
        XCTAssertEqual(String(data: data, encoding: .utf8), "een\ntwee\n\nvier\n")
    }

    func testEncodingFailureIsReported() {
        XCTAssertThrowsError(try FileLoader.encode("日本語", encoding: .ascii, lineEnding: .lf)) { error in
            XCTAssertEqual(error as? FileIOError, .encodingFailed(.ascii))
        }
    }

    func testLineEndingStatistics() {
        let stats = LineEnding.statistics(of: "a\r\nb\nc\rd")
        XCTAssertEqual(stats.crlf, 1)
        XCTAssertEqual(stats.lf, 1)
        XCTAssertEqual(stats.cr, 1)
        XCTAssertTrue(stats.isMixed)
        XCTAssertEqual(stats.dominant, .crlf)
    }

    func testLineEndingConversion() {
        XCTAssertEqual(LineEnding.normalize("a\r\nb\rc\nd"), "a\nb\nc\nd")
        XCTAssertEqual(LineEnding.crlf.applied(to: "a\nb"), "a\r\nb")
        XCTAssertEqual(LineEnding.cr.applied(to: "a\nb"), "a\rb")
    }

    func testWriteAndLoadFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inkline-test-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        try FileLoader.write("regel\n", to: url, encoding: .utf8, lineEnding: .crlf)
        let loaded = try FileLoader.load(contentsOf: url)
        XCTAssertEqual(loaded.text, "regel\n")
        XCTAssertEqual(loaded.lineEnding, .crlf)
        XCTAssertEqual(loaded.byteCount, 7)
    }
}
