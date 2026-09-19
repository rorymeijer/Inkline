import XCTest
@testable import InklineCore

final class DiffEngineTests: XCTestCase {

    func testIdenticalFiles() {
        let result = DiffEngine.compare("een\ntwee\n", "een\ntwee\n")
        XCTAssertTrue(result.isIdentical)
        XCTAssertTrue(result.hunks.isEmpty)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertTrue(result.rows.allSatisfy { $0.operation == .equal })
    }

    func testInsertedLine() {
        let result = DiffEngine.compare("een\ndrie\n", "een\ntwee\ndrie\n")
        XCTAssertEqual(result.insertions, 1)
        XCTAssertEqual(result.deletions, 0)
        XCTAssertEqual(result.rows.map(\.text), ["een", "twee", "drie"])
        XCTAssertEqual(result.rows.map(\.operation), [.equal, .insert, .equal])
    }

    func testDeletedLine() {
        let result = DiffEngine.compare("een\ntwee\ndrie\n", "een\ndrie\n")
        XCTAssertEqual(result.deletions, 1)
        XCTAssertEqual(result.rows.map(\.operation), [.equal, .delete, .equal])
    }

    func testChangedLineIsDeletePlusInsert() {
        let result = DiffEngine.compare("een\ntwee\n", "een\nTWEE\n")
        XCTAssertEqual(result.insertions, 1)
        XCTAssertEqual(result.deletions, 1)
        XCTAssertEqual(result.hunks.count, 1)
        XCTAssertEqual(result.hunks[0].rowRange, 1..<3)
    }

    func testEmptySides() {
        XCTAssertEqual(DiffEngine.compare("", "een\n").insertions, 1)
        XCTAssertEqual(DiffEngine.compare("een\n", "").deletions, 1)
        XCTAssertTrue(DiffEngine.compare("", "").isIdentical)
    }

    func testIgnoreCaseAndWhitespace() {
        let options = DiffOptions(ignoresCase: true, ignoresWhitespace: true)
        let result = DiffEngine.compare("Een   twee\n", "een twee\n", options: options)
        XCTAssertTrue(result.isIdentical)
    }

    func testRowsPreserveLineNumbers() {
        let result = DiffEngine.compare("a\nb\nc\n", "a\nx\nc\n")
        let deleted = result.rows.first { $0.operation == .delete }
        let inserted = result.rows.first { $0.operation == .insert }
        XCTAssertEqual(deleted?.leftLine, 1)
        XCTAssertNil(deleted?.rightLine)
        XCTAssertEqual(inserted?.rightLine, 1)
    }

    func testLargeDifferenceFallsBackToApproximate() {
        let left = (0..<200).map { "links \($0)" }.joined(separator: "\n")
        let right = (0..<200).map { "rechts \($0)" }.joined(separator: "\n")
        let result = DiffEngine.compare(left, right, options: DiffOptions(maximumEditDistance: 10))
        XCTAssertTrue(result.isApproximate)
        XCTAssertEqual(result.insertions, 200)
        XCTAssertEqual(result.deletions, 200)
    }

    func testDiffOfRealisticEdit() {
        let left = """
        func doe() {
            let x = 1
            print(x)
        }
        """
        let right = """
        func doe() {
            let x = 2
            let y = 3
            print(x + y)
        }
        """
        let result = DiffEngine.compare(left, right)
        XCTAssertEqual(result.deletions, 2)
        XCTAssertEqual(result.insertions, 3)
        // The unchanged first and last line must be recognised as equal.
        XCTAssertEqual(result.rows.first?.operation, .equal)
        XCTAssertEqual(result.rows.last?.operation, .equal)
    }
}
