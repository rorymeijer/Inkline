import Foundation

/// A single recorded editor action. Deliberately semantic ("move one word
/// left") rather than raw key events: a recorded macro then replays correctly
/// on a different keyboard layout and can be read, edited and stored as JSON.
public enum MacroAction: Codable, Equatable, Sendable {

    public enum Movement: String, Codable, Sendable {
        case left, right, up, down
        case wordLeft, wordRight
        case lineStart, lineEnd
        case documentStart, documentEnd
        case pageUp, pageDown
    }

    case insertText(String)
    case newline
    case tab
    case deleteBackward
    case deleteForward
    case deleteWordBackward
    case deleteWordForward
    case deleteLine
    case move(Movement, extendingSelection: Bool)
    case selectAll
    case selectLine
    case indent
    case outdent
    case find(query: SearchQuery, direction: SearchDirection)
    case replaceSelection(String)
    case replaceAll(query: SearchQuery, replacement: String)
    case goToLine(Int)
    /// Any command registered in the command registry, plugin commands
    /// included. The string is the command identifier.
    case command(String)

    public var displayDescription: String {
        switch self {
        case let .insertText(text):
            let preview = text.count > 20 ? String(text.prefix(20)) + "…" : text
            return "Tekst invoegen: \"\(preview)\""
        case .newline: return "Nieuwe regel"
        case .tab: return "Tab"
        case .deleteBackward: return "Backspace"
        case .deleteForward: return "Delete"
        case .deleteWordBackward: return "Woord terug verwijderen"
        case .deleteWordForward: return "Woord vooruit verwijderen"
        case .deleteLine: return "Regel verwijderen"
        case let .move(movement, extending):
            return (extending ? "Selecteren: " : "Cursor: ") + movement.rawValue
        case .selectAll: return "Alles selecteren"
        case .selectLine: return "Regel selecteren"
        case .indent: return "Inspringen"
        case .outdent: return "Uitspringen"
        case let .find(query, direction):
            return "Zoeken naar \"\(query.pattern)\" (\(direction == .forward ? "vooruit" : "terug"))"
        case let .replaceSelection(text): return "Selectie vervangen door \"\(text)\""
        case let .replaceAll(query, replacement):
            return "Alles vervangen: \"\(query.pattern)\" → \"\(replacement)\""
        case let .goToLine(line): return "Ga naar regel \(line + 1)"
        case let .command(identifier): return "Commando: \(identifier)"
        }
    }
}

/// A named, storable macro. `keyEquivalent`/`modifiers` back the "sneltoets
/// toewijzen" feature; they are plain strings so the menu can build an
/// `NSMenuItem` without the core knowing about AppKit.
public struct Macro: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var actions: [MacroAction]
    public var keyEquivalent: String?
    public var modifierDescription: String?
    public var createdAt: Date

    public init(id: UUID = UUID(),
                name: String,
                actions: [MacroAction],
                keyEquivalent: String? = nil,
                modifierDescription: String? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.actions = actions
        self.keyEquivalent = keyEquivalent
        self.modifierDescription = modifierDescription
        self.createdAt = createdAt
    }

    public var isEmpty: Bool { actions.isEmpty }
}

/// How often a macro runs: once, a fixed number of times, or until it stops
/// making progress / reaches the end of the document.
public enum MacroRepeatMode: Equatable, Sendable {
    case once
    case times(Int)
    case untilEndOfDocument

    public var maximumIterations: Int {
        switch self {
        case .once: return 1
        case let .times(count): return max(1, count)
        case .untilEndOfDocument: return 100_000      // safety valve
        }
    }
}
