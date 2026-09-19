import Foundation

/// One hit in one file, with enough context to render a result row and to jump
/// to the exact spot on double click.
public struct FileSearchHit: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public let url: URL
    /// Zero-based line number.
    public let line: Int
    /// Match range in document offsets (UTF-16, LF-normalised text).
    public let range: Range<Int>
    /// Match range relative to the start of `lineText`.
    public let rangeInLine: Range<Int>
    public let lineText: String

    public init(url: URL, line: Int, range: Range<Int>, rangeInLine: Range<Int>, lineText: String) {
        self.url = url
        self.line = line
        self.range = range
        self.rangeInLine = rangeInLine
        self.lineText = lineText
    }

    public static func == (lhs: FileSearchHit, rhs: FileSearchHit) -> Bool {
        lhs.url == rhs.url && lhs.line == rhs.line && lhs.range == rhs.range
    }
}

public struct FindInFilesRequest: Sendable {
    public var roots: [URL]
    public var query: SearchQuery
    /// Glob-ish filters on the file name, e.g. `["*.swift", "*.json"]`. Empty
    /// means "every text file".
    public var includePatterns: [String]
    public var excludePatterns: [String]
    public var excludedDirectoryNames: Set<String>
    public var includesHiddenFiles: Bool
    public var followsSymlinks: Bool
    public var maximumFileSize: Int
    public var maximumHitsPerFile: Int
    public var maximumTotalHits: Int

    public init(roots: [URL],
                query: SearchQuery,
                includePatterns: [String] = [],
                excludePatterns: [String] = [],
                excludedDirectoryNames: Set<String> = FindInFilesRequest.defaultExcludedDirectories,
                includesHiddenFiles: Bool = false,
                followsSymlinks: Bool = false,
                maximumFileSize: Int = 32 * 1024 * 1024,
                maximumHitsPerFile: Int = 2_000,
                maximumTotalHits: Int = 50_000) {
        self.roots = roots
        self.query = query
        self.includePatterns = includePatterns
        self.excludePatterns = excludePatterns
        self.excludedDirectoryNames = excludedDirectoryNames
        self.includesHiddenFiles = includesHiddenFiles
        self.followsSymlinks = followsSymlinks
        self.maximumFileSize = maximumFileSize
        self.maximumHitsPerFile = maximumHitsPerFile
        self.maximumTotalHits = maximumTotalHits
    }

    public static let defaultExcludedDirectories: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".build", "DerivedData", ".venv", "__pycache__", "Pods"
    ]
}

public struct FindInFilesSummary: Sendable {
    public var scannedFiles = 0
    public var matchedFiles = 0
    public var hits = 0
    public var skippedBinaryFiles = 0
    public var skippedLargeFiles = 0
    public var wasCancelled = false
    public var duration: TimeInterval = 0
    public var reachedLimit = false
}

/// Walks directories on a background queue and reports hits as they are found,
/// so the results panel fills in while the search is still running.
public final class FindInFilesSearch: @unchecked Sendable {

    private let request: FindInFilesRequest
    private let lock = NSLock()
    private var cancelled = false

    public init(request: FindInFilesRequest) {
        self.request = request
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Synchronous run; call from a background queue. `onHits` is invoked once
    /// per file that has matches.
    @discardableResult
    public func run(onFile: ((URL) -> Void)? = nil,
                    onHits: ([FileSearchHit]) -> Void) -> FindInFilesSummary {
        let started = Date()
        var summary = FindInFilesSummary()
        let regex: NSRegularExpression
        do {
            regex = try SearchEngine.regularExpression(for: request.query)
        } catch {
            summary.duration = Date().timeIntervalSince(started)
            return summary
        }

        for url in files() {
            if isCancelled {
                summary.wasCancelled = true
                break
            }
            if summary.hits >= request.maximumTotalHits {
                summary.reachedLimit = true
                break
            }
            onFile?(url)
            summary.scannedFiles += 1

            if let size = FileLoader.byteCount(of: url), size > request.maximumFileSize {
                summary.skippedLargeFiles += 1
                continue
            }
            guard let document = try? FileLoader.load(contentsOf: url) else { continue }
            if document.looksBinary {
                summary.skippedBinaryFiles += 1
                continue
            }

            let hits = self.hits(in: document.text, url: url, regex: regex)
            if !hits.isEmpty {
                summary.matchedFiles += 1
                summary.hits += hits.count
                onHits(hits)
            }
        }

        summary.duration = Date().timeIntervalSince(started)
        return summary
    }

    func hits(in text: String, url: URL, regex: NSRegularExpression) -> [FileSearchHit] {
        let matches = SearchEngine.matches(of: regex, in: text, limit: request.maximumHitsPerFile)
        guard !matches.isEmpty else { return [] }

        // One piece table per file gives cheap offset → line/column mapping
        // without scanning the text again for every hit.
        let table = PieceTable(text)
        return matches.map { match in
            let line = table.lineNumber(at: match.range.lowerBound)
            let contentRange = table.lineContentRange(line)
            let lineText = table.string(in: contentRange)
            let lower = match.range.lowerBound - contentRange.lowerBound
            let upper = min(match.range.upperBound - contentRange.lowerBound, lineText.utf16.count)
            return FileSearchHit(url: url,
                                 line: line,
                                 range: match.range,
                                 rangeInLine: lower..<max(lower, upper),
                                 lineText: lineText)
        }
    }

    // MARK: File walking

    func files() -> [URL] {
        var result = [URL]()
        let manager = FileManager.default
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !request.includesHiddenFiles { options.insert(.skipsHiddenFiles) }

        for root in request.roots {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                if accepts(root) { result.append(root) }
                continue
            }
            guard let enumerator = manager.enumerator(at: root,
                                                      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                      options: options) else { continue }
            for case let url as URL in enumerator {
                if isCancelled { return result }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true, !request.followsSymlinks {
                    if values?.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                if values?.isDirectory == true {
                    if request.excludedDirectoryNames.contains(url.lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                if accepts(url) { result.append(url) }
            }
        }
        return result
    }

    func accepts(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if !request.excludePatterns.isEmpty,
           request.excludePatterns.contains(where: { GlobPattern.matches($0, name) }) {
            return false
        }
        if request.includePatterns.isEmpty { return true }
        return request.includePatterns.contains { GlobPattern.matches($0, name) }
    }
}

/// Minimal `*`/`?`/`[abc]` matcher for file name filters. `fnmatch(3)` would do,
/// but a Swift implementation keeps the semantics identical on every platform
/// and is easy to unit test.
public enum GlobPattern {
    public static func matches(_ pattern: String, _ name: String) -> Bool {
        let patternCharacters = Array(pattern)
        let nameCharacters = Array(name)
        return match(patternCharacters, 0, nameCharacters, 0)
    }

    private static func match(_ pattern: [Character], _ patternIndex: Int,
                              _ name: [Character], _ nameIndex: Int) -> Bool {
        var patternIndex = patternIndex
        var nameIndex = nameIndex
        while patternIndex < pattern.count {
            let token = pattern[patternIndex]
            switch token {
            case "*":
                if patternIndex + 1 == pattern.count { return true }
                for skip in nameIndex...name.count where match(pattern, patternIndex + 1, name, skip) {
                    return true
                }
                return false
            case "?":
                guard nameIndex < name.count else { return false }
                patternIndex += 1
                nameIndex += 1
            case "[":
                guard nameIndex < name.count else { return false }
                var closing = patternIndex + 1
                while closing < pattern.count, pattern[closing] != "]" { closing += 1 }
                guard closing < pattern.count else { return false }
                var set = Array(pattern[(patternIndex + 1)..<closing])
                var negated = false
                if set.first == "!" || set.first == "^" {
                    negated = true
                    set.removeFirst()
                }
                var contains = false
                var index = 0
                while index < set.count {
                    if index + 2 < set.count, set[index + 1] == "-" {
                        if set[index] <= name[nameIndex] && name[nameIndex] <= set[index + 2] { contains = true }
                        index += 3
                    } else {
                        if set[index] == name[nameIndex] { contains = true }
                        index += 1
                    }
                }
                guard contains != negated else { return false }
                patternIndex = closing + 1
                nameIndex += 1
            default:
                guard nameIndex < name.count, name[nameIndex] == token else { return false }
                patternIndex += 1
                nameIndex += 1
            }
        }
        return nameIndex == name.count
    }
}
