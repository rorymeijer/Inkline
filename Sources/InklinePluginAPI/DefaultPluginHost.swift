import Foundation
import InklineCore

/// A `PluginHost` built on top of the editor's `CommandRegistry`.
///
/// The app subclasses nothing and injects closures for the parts that need the
/// UI (the active document, showing a message, revealing a panel). That keeps
/// the plugin API testable: the unit tests use this very class with stub
/// closures and a `TextBuffer`-backed document.
public final class DefaultPluginHost: PluginHost {

    public let apiVersion: PluginAPIVersion
    public private(set) var activePluginIdentifier: String?

    public var documentProvider: () -> PluginDocument? = { nil }
    public var openDocumentsProvider: () -> [PluginDocument] = { [] }
    public var messageHandler: (String, PluginMessageStyle) -> Void = { _, _ in }
    public var logHandler: (String) -> Void = { _ in }
    public var panelRevealer: (String) -> Void = { _ in }
    public var mainThreadRunner: (@escaping () -> Void) -> Void = { body in
        if Thread.isMainThread { body() } else { DispatchQueue.main.async(execute: body) }
    }

    public private(set) var panels: [PluginPanelDescriptor] = []
    public private(set) var menuItems: [PluginMenuItem] = []
    /// Command identifier → owning plugin identifier, for clean unloading.
    private var ownership: [String: String] = [:]
    private var panelOwners: [String: String] = [:]

    private let registry: CommandRegistry
    private let storageRoot: URL

    public init(registry: CommandRegistry,
                storageRoot: URL,
                apiVersion: PluginAPIVersion = .current) {
        self.registry = registry
        self.storageRoot = storageRoot
        self.apiVersion = apiVersion
    }

    // MARK: Activation scope

    /// Runs `body` with `identifier` as the active plugin, so every
    /// registration made inside is attributed to it.
    public func withActivePlugin<T>(_ identifier: String, _ body: () throws -> T) rethrows -> T {
        let previous = activePluginIdentifier
        activePluginIdentifier = identifier
        defer { activePluginIdentifier = previous }
        return try body()
    }

    /// Removes everything a plugin contributed.
    public func removeContributions(ofPlugin identifier: String) {
        registry.unregisterAll(ownedBy: identifier)
        let ownedCommands = ownership.filter { $0.value == identifier }.map(\.key)
        for command in ownedCommands { ownership.removeValue(forKey: command) }
        menuItems.removeAll { ownedCommands.contains($0.commandIdentifier) }
        let ownedPanels = panelOwners.filter { $0.value == identifier }.map(\.key)
        panels.removeAll { ownedPanels.contains($0.identifier) }
        for panel in ownedPanels { panelOwners.removeValue(forKey: panel) }
    }

    // MARK: PluginHost

    public var activeDocument: PluginDocument? { documentProvider() }
    public var openDocuments: [PluginDocument] { openDocumentsProvider() }

    public func register(command: PluginCommand) {
        let owner = activePluginIdentifier
        if let owner { ownership[command.identifier] = owner }
        // Weak, so a plugin command never keeps the host alive after teardown.
        registry.register(EditorCommand(id: CommandIdentifier(command.identifier),
                                        title: command.title,
                                        category: .plugin,
                                        keyEquivalent: command.keyEquivalent,
                                        modifierDescription: command.modifierDescription,
                                        ownerIdentifier: owner,
                                        isEnabled: { [weak self] _ in
                                            guard let self else { return false }
                                            return command.isEnabled?(self.activeDocument) ?? true
                                        },
                                        handler: { [weak self] _ in
                                            guard let self else { return }
                                            try command.handler(PluginInvocation(host: self,
                                                                                 document: self.activeDocument))
                                        }))
    }

    public func register(menuItem: PluginMenuItem) {
        menuItems.append(menuItem)
    }

    public func register(panel: PluginPanelDescriptor) {
        if let owner = activePluginIdentifier { panelOwners[panel.identifier] = owner }
        panels.removeAll { $0.identifier == panel.identifier }
        panels.append(panel)
    }

    public func showPanel(identifier: String) {
        panelRevealer(identifier)
    }

    public func storageDirectory(forPlugin identifier: String) -> URL {
        let url = storageRoot.appendingPathComponent(identifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func showMessage(_ message: String, style: PluginMessageStyle) {
        messageHandler(message, style)
    }

    public func log(_ message: String) {
        logHandler(message)
    }

    public func performOnMainThread(_ body: @escaping () -> Void) {
        mainThreadRunner(body)
    }
}

/// A `PluginDocument` over a plain `TextBuffer`. The app uses its own
/// implementation backed by the text view (so selections follow the caret);
/// this one makes the plugin API usable headlessly — in tests, in scripted
/// batch runs, and in the example plugins' own tests.
public final class BufferPluginDocument: PluginDocument {

    public let buffer: TextBuffer
    public let fileURL: URL?
    public let displayName: String
    public let languageIdentifier: String?
    private var selection: Range<Int>

    public init(buffer: TextBuffer,
                fileURL: URL? = nil,
                displayName: String = "Naamloos",
                languageIdentifier: String? = nil) {
        self.buffer = buffer
        self.fileURL = fileURL
        self.displayName = displayName
        self.languageIdentifier = languageIdentifier
        self.selection = 0..<0
    }

    public var text: String { buffer.text }
    public var length: Int { buffer.length }

    public var selectedRange: Range<Int> {
        get { selection }
        set {
            let lower = min(max(newValue.lowerBound, 0), buffer.length)
            let upper = min(max(newValue.upperBound, lower), buffer.length)
            selection = lower..<upper
            buffer.selections = [TextSelection(range: selection)]
        }
    }

    public var selectedRanges: [Range<Int>] { buffer.selections.map(\.range) }

    public func string(in range: Range<Int>) -> String { buffer.string(in: range) }

    public func replace(range: Range<Int>, with replacement: String) {
        buffer.replace(range, with: replacement)
        let end = range.lowerBound + replacement.utf16.count
        selection = end..<end
    }

    public func performGrouped(_ body: () -> Void) {
        buffer.beginUndoGroup()
        body()
        buffer.endUndoGroup()
    }

    public func lineNumber(at offset: Int) -> Int { buffer.lineNumber(at: offset) }
    public func offsetOfLineStart(_ line: Int) -> Int { buffer.offsetOfLineStart(line) }
}
