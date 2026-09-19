import Foundation

public struct CommandIdentifier: Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

public enum CommandCategory: String, Codable, CaseIterable, Sendable {
    case file
    case edit
    case search
    case view
    case encoding
    case language
    case macro
    case plugin
    case window
}

/// What a command gets to work with. Kept deliberately small: a command that
/// needs more should ask the host through the plugin API.
public struct CommandContext {
    public let document: TextDocument?
    public let userInfo: [String: String]

    public init(document: TextDocument?, userInfo: [String: String] = [:]) {
        self.document = document
        self.userInfo = userInfo
    }
}

public struct EditorCommand: Identifiable {
    public let id: CommandIdentifier
    public let title: String
    public let category: CommandCategory
    /// Single character for the menu shortcut, e.g. "f".
    public let keyEquivalent: String?
    /// Modifier description understood by the menu builder, e.g. "cmd,shift".
    public let modifierDescription: String?
    /// Identifier of the plugin that contributed this command, if any.
    public let ownerIdentifier: String?
    public let isEnabled: (CommandContext) -> Bool
    public let handler: (CommandContext) throws -> Void

    public init(id: CommandIdentifier,
                title: String,
                category: CommandCategory,
                keyEquivalent: String? = nil,
                modifierDescription: String? = nil,
                ownerIdentifier: String? = nil,
                isEnabled: @escaping (CommandContext) -> Bool = { _ in true },
                handler: @escaping (CommandContext) throws -> Void) {
        self.id = id
        self.title = title
        self.category = category
        self.keyEquivalent = keyEquivalent
        self.modifierDescription = modifierDescription
        self.ownerIdentifier = ownerIdentifier
        self.isEnabled = isEnabled
        self.handler = handler
    }
}

/// The one place that knows every action Inkline can perform — menus, the
/// macro system and plugins all go through it, which is what makes
/// "record a plugin command into a macro" work without special cases.
public final class CommandRegistry {

    public private(set) var commands: [CommandIdentifier: EditorCommand] = [:]
    public var onChange: (() -> Void)?

    public init() {}

    public func register(_ command: EditorCommand) {
        commands[command.id] = command
        onChange?()
    }

    public func register(contentsOf newCommands: [EditorCommand]) {
        for command in newCommands { commands[command.id] = command }
        onChange?()
    }

    public func unregister(_ id: CommandIdentifier) {
        commands.removeValue(forKey: id)
        onChange?()
    }

    /// Removes every command a plugin contributed — called when it is disabled.
    public func unregisterAll(ownedBy ownerIdentifier: String) {
        commands = commands.filter { $0.value.ownerIdentifier != ownerIdentifier }
        onChange?()
    }

    public func command(for id: CommandIdentifier) -> EditorCommand? {
        commands[id]
    }

    public func commands(in category: CommandCategory) -> [EditorCommand] {
        commands.values.filter { $0.category == category }.sorted { $0.title < $1.title }
    }

    @discardableResult
    public func perform(_ id: CommandIdentifier, context: CommandContext) throws -> Bool {
        guard let command = commands[id], command.isEnabled(context) else { return false }
        try command.handler(context)
        return true
    }
}
