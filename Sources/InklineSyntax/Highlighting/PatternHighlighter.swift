import Foundation
import InklineCore

/// The regular-expression highlighter.
///
/// It is the fallback when no tree-sitter grammar is installed for a language,
/// and it is what makes a hand-written language JSON useful on its own. It is
/// line-oriented: single-line rules run only over the range the editor asks
/// for, while multi-line rules (block comments, heredocs, template strings)
/// are scanned once per document revision and cached, because a block comment
/// opened 10 000 lines up still colours the visible screen.
public final class PatternHighlighter: SyntaxHighlighter {

    struct CompiledRule {
        let regex: NSRegularExpression
        let scope: HighlightScope
        let captureGroup: Int
        let priority: Int
    }

    public let language: LanguageDefinition

    private let singleLineRules: [CompiledRule]
    private let multilineRules: [CompiledRule]
    private var cachedBlockTokens: [HighlightToken] = []
    private var blockTokensAreValid = false
    private let lock = NSLock()

    public init(language: LanguageDefinition) {
        self.language = language

        var single = [CompiledRule]()
        var multi = [CompiledRule]()
        for (index, rule) in language.patterns.enumerated() {
            var options: NSRegularExpression.Options = [.anchorsMatchLines]
            if rule.caseInsensitive { options.insert(.caseInsensitive) }
            if rule.multiline { options.insert(.dotMatchesLineSeparators) }
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: options) else {
                continue        // a broken rule disables itself, never the app
            }
            let compiled = CompiledRule(regex: regex,
                                        scope: rule.scope,
                                        captureGroup: rule.captureGroup,
                                        priority: index)
            if rule.multiline { multi.append(compiled) } else { single.append(compiled) }
        }
        singleLineRules = single
        multilineRules = multi
    }

    // MARK: SyntaxHighlighter

    public func tokens(in range: Range<Int>, text: String) -> [HighlightToken] {
        guard !language.patterns.isEmpty, !text.isEmpty else { return [] }
        let nsText = text as NSString
        let clamped = clamp(range, to: nsText.length)
        guard !clamped.isEmpty else { return [] }

        let expanded = lineAlignedRange(clamped, in: nsText)
        let blocks = blockTokens(in: text)

        var candidates = [HighlightToken]()
        var priorities = [Int]()

        for token in blocks where token.range.overlaps(expanded) {
            candidates.append(token)
            priorities.append(-1)                    // block rules always win
        }

        let searchRange = NSRange(location: expanded.lowerBound, length: expanded.count)
        for rule in singleLineRules {
            rule.regex.enumerateMatches(in: text, options: [], range: searchRange) { match, _, _ in
                guard let match else { return }
                let group = rule.captureGroup < match.numberOfRanges ? rule.captureGroup : 0
                let nsRange = match.range(at: group)
                guard nsRange.location != NSNotFound, nsRange.length > 0 else { return }
                candidates.append(HighlightToken(range: nsRange.location..<(nsRange.location + nsRange.length),
                                                 scope: rule.scope))
                priorities.append(rule.priority)
            }
        }

        return resolveOverlaps(candidates, priorities: priorities)
    }

    public func didChange(_ change: TextChange, newText: String) {
        // Any edit can open or close a block comment, so the cheap and correct
        // answer is to re-scan the block rules on the next request.
        guard !multilineRules.isEmpty else { return }
        lock.lock()
        blockTokensAreValid = false
        lock.unlock()
    }

    public func invalidate() {
        lock.lock()
        blockTokensAreValid = false
        cachedBlockTokens = []
        lock.unlock()
    }

    // MARK: Internals

    private func blockTokens(in text: String) -> [HighlightToken] {
        guard !multilineRules.isEmpty else { return [] }
        lock.lock()
        if blockTokensAreValid {
            defer { lock.unlock() }
            return cachedBlockTokens
        }
        lock.unlock()

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var candidates = [HighlightToken]()
        var priorities = [Int]()
        for rule in multilineRules {
            rule.regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match, match.range.length > 0 else { return }
                candidates.append(HighlightToken(range: match.range.location..<(match.range.location + match.range.length),
                                                 scope: rule.scope))
                priorities.append(rule.priority)
            }
        }
        let resolved = resolveOverlaps(candidates, priorities: priorities)

        lock.lock()
        cachedBlockTokens = resolved
        blockTokensAreValid = true
        lock.unlock()
        return resolved
    }

    /// Keeps the highest-priority (lowest number) token at each position and
    /// drops anything that overlaps it, so a keyword inside a string never
    /// steals colour from the string.
    private func resolveOverlaps(_ tokens: [HighlightToken], priorities: [Int]) -> [HighlightToken] {
        guard !tokens.isEmpty else { return [] }
        let order = tokens.indices.sorted { lhs, rhs in
            if tokens[lhs].range.lowerBound != tokens[rhs].range.lowerBound {
                return tokens[lhs].range.lowerBound < tokens[rhs].range.lowerBound
            }
            if priorities[lhs] != priorities[rhs] { return priorities[lhs] < priorities[rhs] }
            return tokens[lhs].range.count > tokens[rhs].range.count
        }

        var result = [HighlightToken]()
        var cursor = Int.min
        for index in order {
            let token = tokens[index]
            guard token.range.lowerBound >= cursor else { continue }
            result.append(token)
            cursor = token.range.upperBound
        }
        return result
    }

    private func clamp(_ range: Range<Int>, to length: Int) -> Range<Int> {
        let lower = min(max(range.lowerBound, 0), length)
        let upper = min(max(range.upperBound, lower), length)
        return lower..<upper
    }

    private func lineAlignedRange(_ range: Range<Int>, in text: NSString) -> Range<Int> {
        let nsRange = text.lineRange(for: NSRange(location: range.lowerBound, length: range.count))
        return nsRange.location..<(nsRange.location + nsRange.length)
    }
}
