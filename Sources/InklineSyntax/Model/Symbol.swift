import Foundation
import InklineCore

public enum SymbolKind: String, Codable, CaseIterable, Sendable {
    case function
    case method
    case type
    case `class`
    case structure
    case `enum`
    case `protocol`
    case interface
    case property
    case variable
    case constant
    case section      // Markdown headings, INI sections
    case tag          // HTML ids
    case selector     // CSS selectors
    case key          // JSON/YAML keys
    case target       // Makefile targets, Dockerfile stages

    public var symbolName: String {
        switch self {
        case .function, .method: return "function"
        case .type, .class, .structure: return "cube"
        case .enum: return "list.bullet.rectangle"
        case .protocol, .interface: return "point.3.connected.trianglepath.dotted"
        case .property, .variable: return "textformat.abc"
        case .constant: return "number"
        case .section: return "number.square"
        case .tag: return "tag"
        case .selector: return "paintbrush"
        case .key: return "key"
        case .target: return "target"
        }
    }
}

/// An entry in the Functielijst / Document map panel.
public struct DocumentSymbol: Equatable, Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let kind: SymbolKind
    public let line: Int
    public let range: Range<Int>
    public let container: String?
    public let indentationLevel: Int

    public init(name: String,
                kind: SymbolKind,
                line: Int,
                range: Range<Int>,
                container: String? = nil,
                indentationLevel: Int = 0) {
        self.name = name
        self.kind = kind
        self.line = line
        self.range = range
        self.container = container
        self.indentationLevel = indentationLevel
    }

    public static func == (lhs: DocumentSymbol, rhs: DocumentSymbol) -> Bool {
        lhs.name == rhs.name && lhs.kind == rhs.kind && lhs.range == rhs.range
    }
}

/// Builds the symbol list from the language's data-driven rules. Grammar-based
/// extraction (tree-sitter `locals`/`tags` queries) plugs into the same
/// `DocumentSymbol` list from `InklineTreeSitter`.
public enum SymbolExtractor {

    public static func symbols(in text: String,
                               language: LanguageDefinition,
                               limit: Int = 5_000) -> [DocumentSymbol] {
        guard !language.symbols.isEmpty, !text.isEmpty else { return [] }
        let table = PieceTable(text)
        let nsText = text as NSString
        var result = [DocumentSymbol]()

        for rule in language.symbols {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern,
                                                       options: [.anchorsMatchLines]) else { continue }
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: nsText.length)) { match, _, stop in
                guard let match, rule.nameGroup < match.numberOfRanges else { return }
                let nameRange = match.range(at: rule.nameGroup)
                guard nameRange.location != NSNotFound else { return }
                let name = nsText.substring(with: nameRange)
                let container = rule.containerGroup
                    .flatMap { group -> String? in
                        guard group < match.numberOfRanges else { return nil }
                        let range = match.range(at: group)
                        return range.location == NSNotFound ? nil : nsText.substring(with: range)
                    }
                let line = table.lineNumber(at: match.range.location)
                let indentation = table.line(line).prefix(while: { $0 == " " || $0 == "\t" }).count
                result.append(DocumentSymbol(name: name,
                                             kind: rule.kind,
                                             line: line,
                                             range: match.range.location..<(match.range.location + match.range.length),
                                             container: container,
                                             indentationLevel: indentation))
                if result.count >= limit { stop.pointee = true }
            }
        }
        return result.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}
