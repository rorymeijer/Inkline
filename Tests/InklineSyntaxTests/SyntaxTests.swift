import XCTest
@testable import InklineSyntax
import InklineCore

final class LanguageRegistryTests: XCTestCase {

    private var registry: LanguageRegistry!

    override func setUp() {
        super.setUp()
        registry = LanguageRegistry.standard()
    }

    func testBundledLanguagesAreLoaded() {
        XCTAssertGreaterThanOrEqual(registry.languages.count, 20,
                                    "alle meegeleverde taaldefinities horen geladen te zijn")
        XCTAssertNotNil(registry.language(withIdentifier: "swift"))
        XCTAssertNotNil(registry.language(withIdentifier: "python"))
        XCTAssertNotNil(registry.language(withIdentifier: "dockerfile"))
    }

    func testMatchByExtension() {
        XCTAssertEqual(registry.language(for: URL(fileURLWithPath: "/tmp/Editor.swift"))?.identifier, "swift")
        XCTAssertEqual(registry.language(for: URL(fileURLWithPath: "/tmp/style.css"))?.identifier, "css")
        XCTAssertEqual(registry.language(for: URL(fileURLWithPath: "/tmp/data.JSON"))?.identifier, "json")
    }

    func testMatchByFileName() {
        XCTAssertEqual(registry.language(for: URL(fileURLWithPath: "/tmp/Dockerfile"))?.identifier, "dockerfile")
        XCTAssertEqual(registry.language(for: URL(fileURLWithPath: "/tmp/Gemfile"))?.identifier, "ruby")
    }

    func testMatchByShebang() {
        XCTAssertEqual(registry.language(forFirstLine: "#!/usr/bin/env python3")?.identifier, "python")
        XCTAssertEqual(registry.language(forFirstLine: "#!/bin/bash")?.identifier, "shell")
    }

    func testUnknownExtensionFallsBackToPlainText() {
        let language = registry.bestMatch(for: URL(fileURLWithPath: "/tmp/ding.qqq"), text: "inhoud")
        XCTAssertEqual(language.identifier, "plaintext")
    }

    func testRegisteringALanguageAtRuntime() {
        let custom = LanguageDefinition(identifier: "brainfuck",
                                        name: "Brainfuck",
                                        fileExtensions: ["bf"],
                                        patterns: [.init(scope: .operator, pattern: "[<>+\\-.,\\[\\]]")])
        registry.register(custom)
        XCTAssertEqual(registry.language(for: URL(fileURLWithPath: "/tmp/hello.bf"))?.identifier, "brainfuck")
    }

    func testPriorityDecidesBetweenCompetingLanguages() {
        let low = LanguageDefinition(identifier: "laag", name: "Laag", fileExtensions: ["conf"], priority: 1)
        let high = LanguageDefinition(identifier: "hoog", name: "Hoog", fileExtensions: ["conf"], priority: 99)
        registry.register(contentsOf: [low, high])
        XCTAssertEqual(registry.language(for: URL(fileURLWithPath: "/tmp/x.conf"))?.identifier, "hoog")
    }

    func testLoadingABrokenDefinitionIsReportedNotFatal() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("inkline-lang-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("{ dit is geen json".utf8).write(to: directory.appendingPathComponent("stuk.json"))
        try Data(#"{"identifier":"goed","name":"Goed","fileExtensions":["gd"]}"#.utf8)
            .write(to: directory.appendingPathComponent("goed.json"))

        let issues = registry.loadDefinitions(in: directory)
        XCTAssertEqual(issues.count, 1)
        XCTAssertNotNil(registry.language(withIdentifier: "goed"), "de goede definitie laadt gewoon door")
    }

    func testMinimalDefinitionDecodesWithDefaults() throws {
        let json = #"{"identifier":"mini"}"#
        let language = try JSONDecoder().decode(LanguageDefinition.self, from: Data(json.utf8))
        XCTAssertEqual(language.name, "mini")
        XCTAssertEqual(language.folding, .brackets)
        XCTAssertEqual(language.indentation, .default)
        XCTAssertEqual(language.brackets.count, 3)
        XCTAssertTrue(language.patterns.isEmpty)
    }
}

final class PatternHighlighterTests: XCTestCase {

    private let registry = LanguageRegistry.standard()

    private func scopes(_ text: String, language identifier: String) throws -> [(HighlightScope, String)] {
        let language = try XCTUnwrap(registry.language(withIdentifier: identifier))
        let highlighter = PatternHighlighter(language: language)
        let nsText = text as NSString
        return highlighter.tokens(in: 0..<nsText.length, text: text)
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
            .map { ($0.scope, nsText.substring(with: NSRange(location: $0.range.lowerBound,
                                                             length: $0.range.count))) }
    }

    func testSwiftKeywordsStringsAndComments() throws {
        let tokens = try scopes("// hallo\nlet naam = \"Inkline\"\n", language: "swift")
        XCTAssertEqual(tokens.first?.0, .comment)
        XCTAssertEqual(tokens.first?.1, "// hallo")
        XCTAssertTrue(tokens.contains { $0.0 == .storage && $0.1 == "let" })
        XCTAssertTrue(tokens.contains { $0.0 == .string && $0.1 == "\"Inkline\"" })
    }

    func testKeywordInsideStringIsNotHighlighted() throws {
        let tokens = try scopes("let x = \"let y = 1\"", language: "swift")
        let keywordTokens = tokens.filter { $0.0 == .storage }
        XCTAssertEqual(keywordTokens.count, 1, "het 'let' in de string telt niet mee")
    }

    func testBlockCommentSpansLines() throws {
        let text = "/* een\n   meerregelig\n   commentaar */\nlet x = 1"
        let tokens = try scopes(text, language: "swift")
        XCTAssertEqual(tokens.first?.0, .comment)
        XCTAssertTrue(tokens.first?.1.contains("meerregelig") ?? false)
        XCTAssertTrue(tokens.contains { $0.0 == .storage && $0.1 == "let" })
    }

    func testTokensForAVisibleRangeOnly() throws {
        let language = try XCTUnwrap(registry.language(withIdentifier: "swift"))
        let highlighter = PatternHighlighter(language: language)
        let line = "let waarde = 42 // uitleg\n"
        let text = String(repeating: line, count: 200)
        let nsLength = (text as NSString).length

        let windowStart = nsLength / 2
        let tokens = highlighter.tokens(in: windowStart..<(windowStart + line.utf16.count), text: text)
        XCTAssertFalse(tokens.isEmpty)
        XCTAssertTrue(tokens.allSatisfy { $0.range.lowerBound >= windowStart - line.utf16.count })
    }

    func testJSONPropertiesAndValues() throws {
        let tokens = try scopes(#"{"naam": "Inkline", "versie": 1, "actief": true}"#, language: "json")
        XCTAssertTrue(tokens.contains { $0.0 == .property && $0.1 == "\"naam\"" })
        XCTAssertTrue(tokens.contains { $0.0 == .string && $0.1 == "\"Inkline\"" })
        XCTAssertTrue(tokens.contains { $0.0 == .number && $0.1 == "1" })
        XCTAssertTrue(tokens.contains { $0.0 == .constant && $0.1 == "true" })
    }

    func testPythonAndMarkdown() throws {
        let python = try scopes("def doe(x):\n    return x  # klaar\n", language: "python")
        XCTAssertTrue(python.contains { $0.0 == .storage && $0.1 == "def" })
        XCTAssertTrue(python.contains { $0.0 == .comment && $0.1 == "# klaar" })

        let markdown = try scopes("# Titel\n\nGewone **vette** tekst.\n", language: "markdown")
        XCTAssertTrue(markdown.contains { $0.0 == .heading && $0.1 == "# Titel" })
        XCTAssertTrue(markdown.contains { $0.0 == .strong && $0.1 == "**vette**" })
    }

    func testCommentAndStringRangesForBracketMatching() throws {
        let language = try XCTUnwrap(registry.language(withIdentifier: "swift"))
        let highlighter = PatternHighlighter(language: language)
        let text = "let a = \"}\" // }"
        let ignored = highlighter.commentAndStringRanges(in: 0..<(text as NSString).length, text: text)
        XCTAssertEqual(ignored.count, 2)
        XCTAssertTrue(ignored[0].contains(9))
    }

    func testPlainTextProducesNoTokens() {
        let highlighter = PatternHighlighter(language: .plainText)
        XCTAssertTrue(highlighter.tokens(in: 0..<5, text: "hallo").isEmpty)
    }

    func testNullHighlighterIsCheap() {
        let highlighter = NullHighlighter()
        XCTAssertTrue(highlighter.tokens(in: 0..<100, text: "wat dan ook").isEmpty)
        XCTAssertTrue(highlighter.commentAndStringRanges(in: 0..<100, text: "x").isEmpty)
    }
}

final class SymbolExtractorTests: XCTestCase {

    private let registry = LanguageRegistry.standard()

    func testSwiftSymbols() throws {
        let language = try XCTUnwrap(registry.language(withIdentifier: "swift"))
        let text = """
        import Foundation

        struct Teller {
            private var waarde = 0

            mutating func verhoog() {
                waarde += 1
            }
        }

        enum Richting { case op, neer }
        """
        let symbols = SymbolExtractor.symbols(in: text, language: language)
        XCTAssertTrue(symbols.contains { $0.kind == .structure && $0.name == "Teller" })
        XCTAssertTrue(symbols.contains { $0.kind == .function && $0.name == "verhoog" })
        XCTAssertTrue(symbols.contains { $0.kind == .enum && $0.name == "Richting" })
        XCTAssertEqual(symbols.map(\.line), symbols.map(\.line).sorted())
    }

    func testMarkdownHeadings() throws {
        let language = try XCTUnwrap(registry.language(withIdentifier: "markdown"))
        let symbols = SymbolExtractor.symbols(in: "# Een\ntekst\n## Twee\n", language: language)
        XCTAssertEqual(symbols.map(\.name), ["Een", "Twee"])
        XCTAssertEqual(symbols.map(\.kind), [.section, .section])
    }

    func testPythonSymbolsWithIndentation() throws {
        let language = try XCTUnwrap(registry.language(withIdentifier: "python"))
        let symbols = SymbolExtractor.symbols(in: "class A:\n    def b(self):\n        pass\n", language: language)
        XCTAssertEqual(symbols.map(\.name), ["A", "b"])
        XCTAssertEqual(symbols.last?.indentationLevel, 4)
    }
}

final class ThemeTests: XCTestCase {

    func testColorParsing() {
        XCTAssertEqual(ThemeColor(hex: "#FFFFFF"), ThemeColor(red: 1, green: 1, blue: 1))
        XCTAssertEqual(ThemeColor(hex: "000"), ThemeColor(red: 0, green: 0, blue: 0))
        XCTAssertEqual(ThemeColor(hex: "#FF000080")?.alpha ?? 0, 0.5, accuracy: 0.01)
        XCTAssertNil(ThemeColor(hex: "#GGGGGG"))
        XCTAssertEqual(ThemeColor(hex: "#3E7BFA")?.hexString, "#3E7BFA")
    }

    func testBundledThemesLoad() {
        let registry = ThemeRegistry.standard()
        XCTAssertNotNil(registry.theme(withIdentifier: "inkline-light"))
        XCTAssertNotNil(registry.theme(withIdentifier: "inkline-dark"))
        XCTAssertFalse(registry.themes(for: .dark).isEmpty)
    }

    func testUnknownThemeFallsBack() {
        let registry = ThemeRegistry.standard()
        let theme = registry.theme(withIdentifier: "bestaat-niet", appearance: .dark)
        XCTAssertEqual(theme.appearance, .dark)
    }

    func testScopeFallbacks() {
        let theme = Theme.builtInDark
        XCTAssertEqual(theme.style(for: .controlKeyword)?.color, theme.style(for: .keyword)?.color)
        XCTAssertEqual(theme.color(for: .plain), theme.colors.foreground)
    }

    func testThemeDecodesShorthandScopes() throws {
        let json = """
        {"identifier":"t","name":"T","appearance":"light",
         "colors":{"background":"#FFFFFF","foreground":"#000000","caret":"#000000","selection":"#CCCCCC",
                   "inactiveSelection":"#DDDDDD","currentLine":"#EEEEEE","gutterBackground":"#FAFAFA",
                   "lineNumber":"#888888","activeLineNumber":"#000000","indentGuide":"#EEEEEE",
                   "invisibles":"#CCCCCC","findHighlight":"#FFFF00","currentFindHighlight":"#FFAA00",
                   "bracketMatch":"#DDEEFF","pageGuide":"#EEEEEE","diffInserted":"#E0FFE0",
                   "diffDeleted":"#FFE0E0","bookmark":"#0000FF"},
         "scopes":{"keyword":"#FF0000","comment":{"color":"#00FF00","italic":true}}}
        """
        let theme = try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
        XCTAssertEqual(theme.style(for: .keyword)?.color?.hexString, "#FF0000")
        XCTAssertTrue(theme.style(for: .comment)?.italic ?? false)
    }
}

final class HighlightScopeTests: XCTestCase {

    func testCaptureNameMapping() {
        XCTAssertEqual(HighlightScope.fromCaptureName("@keyword.control"), .controlKeyword)
        XCTAssertEqual(HighlightScope.fromCaptureName("function.method"), .method)
        XCTAssertEqual(HighlightScope.fromCaptureName("string.special.path"), .escapeSequence)
        XCTAssertEqual(HighlightScope.fromCaptureName("variable.other.member"), .variable)
        XCTAssertNil(HighlightScope.fromCaptureName("volstrekt.onbekend"))
    }

    func testCommentAndStringClassification() {
        XCTAssertTrue(HighlightScope.comment.isCommentOrString)
        XCTAssertTrue(HighlightScope.string.isCommentOrString)
        XCTAssertFalse(HighlightScope.keyword.isCommentOrString)
    }
}

final class HighlightCoordinatorTests: XCTestCase {

    func testSynchronousTokensAreClippedToRange() throws {
        let registry = LanguageRegistry.standard()
        let language = try XCTUnwrap(registry.language(withIdentifier: "swift"))
        let coordinator = HighlightCoordinator(language: language)
        let text = "let a = 1\nlet b = 2\n"
        let tokens = coordinator.tokensSynchronously(in: 10..<20, text: text)
        XCTAssertFalse(tokens.isEmpty)
        XCTAssertTrue(tokens.allSatisfy { $0.range.overlaps(10..<20) })
    }

    func testAsynchronousRequestCallsBack() throws {
        let registry = LanguageRegistry.standard()
        let language = try XCTUnwrap(registry.language(withIdentifier: "swift"))
        let coordinator = HighlightCoordinator(language: language)
        let text = String(repeating: "let waarde = 42\n", count: 100)

        let expectation = expectation(description: "tokens")
        coordinator.onTokensReady = { _, tokens in
            if !tokens.isEmpty { expectation.fulfill() }
        }
        coordinator.requestTokens(in: 0..<200, text: text)
        wait(for: [expectation], timeout: 5)

        XCTAssertNotNil(coordinator.cachedTokens(in: 0..<200))
    }

    func testEditInvalidatesCacheFromEditPoint() throws {
        let registry = LanguageRegistry.standard()
        let language = try XCTUnwrap(registry.language(withIdentifier: "swift"))
        let coordinator = HighlightCoordinator(language: language)
        let text = String(repeating: "let waarde = 42\n", count: 100)

        let expectation = expectation(description: "tokens")
        coordinator.onTokensReady = { _, _ in expectation.fulfill() }
        coordinator.requestTokens(in: 0..<100, text: text)
        wait(for: [expectation], timeout: 5)
        XCTAssertNotNil(coordinator.cachedTokens(in: 0..<100))

        coordinator.handle(TextChange(editedRange: 0..<0, removedText: "", insertedText: "x"),
                           newText: "x" + text)
        XCTAssertNil(coordinator.cachedTokens(in: 0..<100), "cache vanaf het bewerkingspunt is vervallen")
    }
}
