import Foundation

public enum DiffOperation: String, Sendable {
    case equal
    case insert      // present on the right only
    case delete      // present on the left only
}

/// One row of the side-by-side compare view.
public struct DiffRow: Equatable, Sendable {
    public let operation: DiffOperation
    public let leftLine: Int?
    public let rightLine: Int?
    public let text: String

    public init(operation: DiffOperation, leftLine: Int?, rightLine: Int?, text: String) {
        self.operation = operation
        self.leftLine = leftLine
        self.rightLine = rightLine
        self.text = text
    }
}

/// A group of adjacent changed rows, used for "volgend verschil".
public struct DiffHunk: Equatable, Sendable {
    public let rowRange: Range<Int>
    public let leftRange: Range<Int>
    public let rightRange: Range<Int>
}

public struct DiffResult: Equatable, Sendable {
    public let rows: [DiffRow]
    public let hunks: [DiffHunk]
    public let insertions: Int
    public let deletions: Int
    /// True when the files were too different to diff within the configured
    /// budget and the result is a whole-file replace.
    public let isApproximate: Bool

    public var isIdentical: Bool { insertions == 0 && deletions == 0 }
}

public struct DiffOptions: Equatable, Sendable {
    public var ignoresCase: Bool
    public var ignoresWhitespace: Bool
    /// Upper bound on the Myers edit distance. Beyond this the files are
    /// reported as a wholesale replacement rather than hanging the UI.
    public var maximumEditDistance: Int

    public init(ignoresCase: Bool = false,
                ignoresWhitespace: Bool = false,
                maximumEditDistance: Int = 200_000) {
        self.ignoresCase = ignoresCase
        self.ignoresWhitespace = ignoresWhitespace
        self.maximumEditDistance = maximumEditDistance
    }

    public static let `default` = DiffOptions()
}

/// Line-based Myers diff (the "An O(ND) Difference Algorithm" one) behind the
/// Vergelijk view. Hashing the comparison key per line first keeps the inner
/// loop to integer comparisons.
public enum DiffEngine {

    public static func compare(_ leftText: String,
                               _ rightText: String,
                               options: DiffOptions = .default) -> DiffResult {
        let left = TextTransforms.splitIntoLines(leftText)
        let right = TextTransforms.splitIntoLines(rightText)
        return compare(left: left, right: right, options: options)
    }

    public static func compare(left: [String],
                               right: [String],
                               options: DiffOptions = .default) -> DiffResult {
        var interned = [String: Int]()
        func identifier(_ line: String) -> Int {
            let value = key(line, options: options)
            if let existing = interned[value] { return existing }
            let next = interned.count
            interned[value] = next
            return next
        }
        let leftKeys = left.map(identifier)
        let rightKeys = right.map(identifier)

        guard let script = myers(leftKeys, rightKeys, limit: options.maximumEditDistance) else {
            return wholesaleReplacement(left: left, right: right)
        }

        var rows = [DiffRow]()
        rows.reserveCapacity(script.count)
        var insertions = 0
        var deletions = 0
        for step in script {
            switch step.operation {
            case .equal:
                rows.append(DiffRow(operation: .equal,
                                    leftLine: step.leftIndex,
                                    rightLine: step.rightIndex,
                                    text: left[step.leftIndex!]))
            case .delete:
                deletions += 1
                rows.append(DiffRow(operation: .delete,
                                    leftLine: step.leftIndex,
                                    rightLine: nil,
                                    text: left[step.leftIndex!]))
            case .insert:
                insertions += 1
                rows.append(DiffRow(operation: .insert,
                                    leftLine: nil,
                                    rightLine: step.rightIndex,
                                    text: right[step.rightIndex!]))
            }
        }
        return DiffResult(rows: rows,
                          hunks: hunks(in: rows),
                          insertions: insertions,
                          deletions: deletions,
                          isApproximate: false)
    }

    // MARK: Hunks

    static func hunks(in rows: [DiffRow]) -> [DiffHunk] {
        var result = [DiffHunk]()
        var index = 0
        while index < rows.count {
            guard rows[index].operation != .equal else { index += 1; continue }
            let start = index
            var leftLower = Int.max, leftUpper = 0
            var rightLower = Int.max, rightUpper = 0
            while index < rows.count, rows[index].operation != .equal {
                if let line = rows[index].leftLine {
                    leftLower = min(leftLower, line)
                    leftUpper = max(leftUpper, line + 1)
                }
                if let line = rows[index].rightLine {
                    rightLower = min(rightLower, line)
                    rightUpper = max(rightUpper, line + 1)
                }
                index += 1
            }
            result.append(DiffHunk(rowRange: start..<index,
                                   leftRange: (leftLower == Int.max ? 0 : leftLower)..<max(leftUpper, leftLower == Int.max ? 0 : leftLower),
                                   rightRange: (rightLower == Int.max ? 0 : rightLower)..<max(rightUpper, rightLower == Int.max ? 0 : rightLower)))
        }
        return result
    }

    // MARK: Myers

    struct Step {
        let operation: DiffOperation
        let leftIndex: Int?
        let rightIndex: Int?
    }

    /// Returns `nil` when the edit distance exceeds `limit`.
    static func myers(_ left: [Int], _ right: [Int], limit: Int) -> [Step]? {
        let n = left.count
        let m = right.count
        if n == 0 && m == 0 { return [] }
        let maximum = min(n + m, limit)
        let offset = maximum
        var v = [Int](repeating: 0, count: 2 * maximum + 2)
        var trace = [[Int]]()
        trace.reserveCapacity(maximum + 1)

        for d in 0...maximum {
            trace.append(v)
            var k = -d
            while k <= d {
                let index = k + offset
                guard index >= 0, index + 1 < v.count else { k += 2; continue }
                var x: Int
                if k == -d || (k != d && v[index - 1] < v[index + 1]) {
                    x = v[index + 1]
                } else {
                    x = v[index - 1] + 1
                }
                var y = x - k
                while x < n && y < m && left[x] == right[y] {
                    x += 1
                    y += 1
                }
                v[index] = x
                if x >= n && y >= m {
                    return backtrack(trace: trace, left: left, right: right, offset: offset, distance: d)
                }
                k += 2
            }
        }
        return nil
    }

    private static func backtrack(trace: [[Int]],
                                  left: [Int],
                                  right: [Int],
                                  offset: Int,
                                  distance: Int) -> [Step] {
        var steps = [Step]()
        var x = left.count
        var y = right.count

        var d = distance
        while d > 0 {
            let v = trace[d]
            let k = x - y
            let index = k + offset
            let previousK: Int
            if k == -d || (k != d && v[index - 1] < v[index + 1]) {
                previousK = k + 1
            } else {
                previousK = k - 1
            }
            let previousX = v[previousK + offset]
            let previousY = previousX - previousK

            while x > previousX && y > previousY {
                x -= 1
                y -= 1
                steps.append(Step(operation: .equal, leftIndex: x, rightIndex: y))
            }
            if x > previousX {
                x -= 1
                steps.append(Step(operation: .delete, leftIndex: x, rightIndex: nil))
            } else if y > previousY {
                y -= 1
                steps.append(Step(operation: .insert, leftIndex: nil, rightIndex: y))
            }
            d -= 1
        }
        while x > 0 && y > 0 {
            x -= 1
            y -= 1
            steps.append(Step(operation: .equal, leftIndex: x, rightIndex: y))
        }
        while x > 0 {
            x -= 1
            steps.append(Step(operation: .delete, leftIndex: x, rightIndex: nil))
        }
        while y > 0 {
            y -= 1
            steps.append(Step(operation: .insert, leftIndex: nil, rightIndex: y))
        }
        return steps.reversed()
    }

    // MARK: Helpers

    private static func wholesaleReplacement(left: [String], right: [String]) -> DiffResult {
        var rows = left.enumerated().map { DiffRow(operation: .delete, leftLine: $0.offset, rightLine: nil, text: $0.element) }
        rows += right.enumerated().map { DiffRow(operation: .insert, leftLine: nil, rightLine: $0.offset, text: $0.element) }
        return DiffResult(rows: rows,
                          hunks: hunks(in: rows),
                          insertions: right.count,
                          deletions: left.count,
                          isApproximate: true)
    }

    /// Comparison key for a line. Interned into integers by the caller so the
    /// inner Myers loop only compares `Int`s — and so two different lines can
    /// never collide the way raw hash values can.
    private static func key(_ line: String, options: DiffOptions) -> String {
        var value = line
        if options.ignoresWhitespace {
            value = value.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        }
        if options.ignoresCase {
            value = value.lowercased()
        }
        return value
    }
}
