import Foundation

public struct FoldRegion: Equatable, Sendable {
    /// Line that carries the fold arrow; it stays visible when folded.
    public let startLine: Int
    /// Last line that disappears when the region is folded.
    public let endLine: Int
    public let level: Int

    public init(startLine: Int, endLine: Int, level: Int) {
        self.startLine = startLine
        self.endLine = endLine
        self.level = level
    }

    public var hiddenLines: ClosedRange<Int>? {
        endLine > startLine ? (startLine + 1)...endLine : nil
    }

    public func contains(line: Int) -> Bool { line > startLine && line <= endLine }
}

/// Where fold regions come from. Brackets give better results in C-like
/// languages, indentation is the right answer for Python and YAML, and a
/// language definition picks one.
public enum FoldingStrategy: String, Codable, CaseIterable, Sendable {
    case brackets
    case indentation
    case none
}

public enum FoldingCalculator {

    /// Computes every foldable region in the document. Runs off the main
    /// thread for large files; the result is a plain value that the ruler view
    /// can consume as-is.
    public static func regions(in table: PieceTable,
                               strategy: FoldingStrategy,
                               indentation: IndentationSettings = .default,
                               pairs: [BracketMatcher.Pair] = BracketMatcher.defaultPairs) -> [FoldRegion] {
        switch strategy {
        case .none: return []
        case .brackets: return bracketRegions(in: table, pairs: pairs)
        case .indentation: return indentationRegions(in: table, indentation: indentation)
        }
    }

    private static func bracketRegions(in table: PieceTable, pairs: [BracketMatcher.Pair]) -> [FoldRegion] {
        var stack = [(line: Int, unit: UInt16)]()
        var regions = [FoldRegion]()
        var offset = 0
        let count = table.count
        var line = 0
        var lineEnd = table.lineRange(0).upperBound

        while offset < count {
            if offset >= lineEnd, line + 1 < table.lineCount {
                line += 1
                lineEnd = table.lineRange(line).upperBound
            }
            let unit = table.codeUnit(at: offset)
            if let pair = pairs.first(where: { $0.open == unit }) {
                stack.append((line, pair.close))
            } else if pairs.contains(where: { $0.close == unit }),
                      let opened = stack.last, opened.unit == unit {
                stack.removeLast()
                if line > opened.line {
                    regions.append(FoldRegion(startLine: opened.line, endLine: line - 1, level: stack.count))
                }
            }
            offset += 1
        }
        return regions.sorted { $0.startLine < $1.startLine }
    }

    private static func indentationRegions(in table: PieceTable,
                                           indentation: IndentationSettings) -> [FoldRegion] {
        var widths = [Int?]()
        widths.reserveCapacity(table.lineCount)
        for line in 0..<table.lineCount {
            let text = table.line(line)
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                widths.append(nil)                      // blank lines belong to the block above
            } else {
                widths.append(indentation.visualWidth(of: IndentationEngine.leadingWhitespace(of: text)))
            }
        }

        var regions = [FoldRegion]()
        for line in 0..<widths.count {
            guard let width = widths[line] else { continue }
            var end = line
            var next = line + 1
            while next < widths.count {
                guard let nextWidth = widths[next] else { next += 1; continue }
                if nextWidth > width {
                    end = next
                    next += 1
                } else {
                    break
                }
            }
            if end > line {
                regions.append(FoldRegion(startLine: line, endLine: end, level: width / max(1, indentation.indentWidth)))
            }
        }
        return regions
    }
}

/// Which regions are currently collapsed, and which lines that hides.
public struct FoldingState: Equatable, Sendable {
    public private(set) var collapsedStartLines: Set<Int> = []
    public private(set) var regions: [FoldRegion] = []

    public init() {}

    public mutating func update(regions: [FoldRegion]) {
        self.regions = regions
        let valid = Set(regions.map(\.startLine))
        collapsedStartLines.formIntersection(valid)
    }

    public func region(startingAt line: Int) -> FoldRegion? {
        regions.first { $0.startLine == line }
    }

    public func isCollapsed(_ line: Int) -> Bool { collapsedStartLines.contains(line) }

    @discardableResult
    public mutating func toggle(at line: Int) -> Bool {
        guard region(startingAt: line) != nil else { return false }
        if collapsedStartLines.contains(line) {
            collapsedStartLines.remove(line)
        } else {
            collapsedStartLines.insert(line)
        }
        return true
    }

    public mutating func collapseAll() {
        collapsedStartLines = Set(regions.map(\.startLine))
    }

    public mutating func expandAll() {
        collapsedStartLines.removeAll()
    }

    public mutating func collapse(toLevel level: Int) {
        collapsedStartLines = Set(regions.filter { $0.level >= level }.map(\.startLine))
    }

    /// Lines hidden by the collapsed regions, merged and sorted. Nested folds
    /// inside a collapsed parent add nothing, which the merge handles.
    public var hiddenLines: [ClosedRange<Int>] {
        let ranges = regions
            .filter { collapsedStartLines.contains($0.startLine) }
            .compactMap(\.hiddenLines)
            .sorted { $0.lowerBound < $1.lowerBound }
        var merged = [ClosedRange<Int>]()
        for range in ranges {
            if let last = merged.last, range.lowerBound <= last.upperBound + 1 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    public func isHidden(line: Int) -> Bool {
        hiddenLines.contains { $0.contains(line) }
    }
}
