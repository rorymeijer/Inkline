import Foundation
import InklineCore

/// Drives highlighting for one document without ever blocking the main thread.
///
/// The editor asks for the range it is about to draw; the coordinator answers
/// immediately from its cache and, when the answer is missing or stale, schedules
/// the work on a background queue and calls back when the tokens are ready. That
/// is the whole trick behind "a 100 MB file opens instantly": only the visible
/// window is ever highlighted.
public final class HighlightCoordinator {

    /// Highlighting granularity. Larger chunks mean fewer background jobs but
    /// more work per job; 16 KB is roughly two screens of code.
    public static let chunkSize = 16 * 1024

    public private(set) var highlighter: SyntaxHighlighter
    public var language: LanguageDefinition { highlighter.language }

    /// Called on the main queue when new tokens are available for a range.
    public var onTokensReady: ((Range<Int>, [HighlightToken]) -> Void)?

    private var cache: [Int: [HighlightToken]] = [:]
    private var inFlight: Set<Int> = []
    private let queue = DispatchQueue(label: "nl.rorymeijer.inkline.highlight", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = 0

    public init(highlighter: SyntaxHighlighter) {
        self.highlighter = highlighter
    }

    public convenience init(language: LanguageDefinition) {
        self.init(highlighter: PatternHighlighter(language: language))
    }

    // MARK: Language / lifecycle

    public func setHighlighter(_ newHighlighter: SyntaxHighlighter) {
        lock.lock()
        highlighter = newHighlighter
        cache.removeAll()
        inFlight.removeAll()
        generation += 1
        lock.unlock()
    }

    public func invalidateAll() {
        lock.lock()
        cache.removeAll()
        inFlight.removeAll()
        generation += 1
        lock.unlock()
        highlighter.invalidate()
    }

    /// Drops the cache from the edited position onwards: everything after an
    /// edit has moved, and an edit can change how later text parses.
    public func handle(_ change: TextChange, newText: String) {
        highlighter.didChange(change, newText: newText)
        let firstChunk = change.editedRange.lowerBound / Self.chunkSize
        lock.lock()
        cache = cache.filter { $0.key < firstChunk }
        inFlight.removeAll()
        generation += 1
        lock.unlock()
    }

    // MARK: Requesting

    /// Cached tokens for `range`, or `nil` when some chunk is missing. The text
    /// view draws what it has and repaints when the callback arrives.
    public func cachedTokens(in range: Range<Int>) -> [HighlightToken]? {
        let chunks = chunkIndexes(for: range)
        lock.lock()
        defer { lock.unlock() }
        var result = [HighlightToken]()
        for chunk in chunks {
            guard let tokens = cache[chunk] else { return nil }
            result.append(contentsOf: tokens.filter { $0.range.overlaps(range) })
        }
        return result
    }

    /// Highlights `range` on a background queue (unless already cached) and
    /// reports back on the main queue.
    public func requestTokens(in range: Range<Int>, text: String) {
        let chunks = chunkIndexes(for: range)
        lock.lock()
        let missing = chunks.filter { cache[$0] == nil && !inFlight.contains($0) }
        for chunk in missing { inFlight.insert(chunk) }
        let currentGeneration = generation
        lock.unlock()
        guard !missing.isEmpty else { return }

        queue.async { [weak self] in
            guard let self else { return }
            for chunk in missing {
                let chunkRange = self.range(ofChunk: chunk, textLength: (text as NSString).length)
                guard !chunkRange.isEmpty else { continue }
                let tokens = self.highlighter.tokens(in: chunkRange, text: text)

                self.lock.lock()
                let stillCurrent = currentGeneration == self.generation
                if stillCurrent {
                    self.cache[chunk] = tokens
                }
                self.inFlight.remove(chunk)
                self.lock.unlock()

                guard stillCurrent else { continue }
                DispatchQueue.main.async {
                    self.onTokensReady?(chunkRange, tokens)
                }
            }
        }
    }

    /// Synchronous highlighting, for printing, exporting and tests.
    public func tokensSynchronously(in range: Range<Int>, text: String) -> [HighlightToken] {
        let tokens = highlighter.tokens(in: range, text: text)
        return tokens.filter { $0.range.overlaps(range) }
    }

    // MARK: Chunks

    private func chunkIndexes(for range: Range<Int>) -> [Int] {
        let first = max(0, range.lowerBound) / Self.chunkSize
        let last = max(0, range.upperBound - 1) / Self.chunkSize
        guard first <= last else { return [first] }
        return Array(first...last)
    }

    private func range(ofChunk index: Int, textLength: Int) -> Range<Int> {
        let lower = min(index * Self.chunkSize, textLength)
        let upper = min(lower + Self.chunkSize, textLength)
        return lower..<upper
    }
}
