import Foundation
import InklineCore

#if canImport(AppKit)
import AppKit
/// The view type a plugin panel provides. On macOS this is an `NSView`; the
/// alias keeps the protocol compiling in headless test builds.
public typealias PluginPanelView = NSView
#else
public typealias PluginPanelView = AnyObject
#endif

/// The protocol every plugin implements.
///
/// A plugin is a bundle (`MyPlugin.inklineplugin`) whose `NSPrincipalClass` is
/// an `NSObject` subclass conforming to this protocol. Inkline instantiates it
/// with `init()`, calls `activate(host:)` once, and calls `deactivate()` when
/// the plugin is disabled or the app quits.
///
/// See `docs/Plugins-schrijven.md` and the three examples in `Plugins/`.
public protocol InklinePlugin: AnyObject {
    /// Declared statically so the manager can show details before activating.
    static var manifest: PluginManifest { get }

    init()

    /// Register commands, menu items and panels here. Throwing aborts loading
    /// and shows the reason in the plugin manager.
    func activate(host: PluginHost) throws

    /// Undo everything `activate(host:)` did. The host unregisters commands,
    /// menu items and panels automatically; use this for your own resources.
    func deactivate()
}

extension InklinePlugin {
    public func deactivate() {}
}

/// A command contributed by a plugin. Appears in the Plugins menu, in the
/// command palette, and can be recorded into a macro.
public struct PluginCommand {
    public let identifier: String
    public let title: String
    public let keyEquivalent: String?
    public let modifierDescription: String?
    /// `nil` means "always enabled".
    public let isEnabled: ((PluginDocument?) -> Bool)?
    public let handler: (PluginInvocation) throws -> Void

    public init(identifier: String,
                title: String,
                keyEquivalent: String? = nil,
                modifierDescription: String? = nil,
                isEnabled: ((PluginDocument?) -> Bool)? = nil,
                handler: @escaping (PluginInvocation) throws -> Void) {
        self.identifier = identifier
        self.title = title
        self.keyEquivalent = keyEquivalent
        self.modifierDescription = modifierDescription
        self.isEnabled = isEnabled
        self.handler = handler
    }
}

/// What a command receives when it runs.
public struct PluginInvocation {
    public let host: PluginHost
    public let document: PluginDocument?

    public init(host: PluginHost, document: PluginDocument?) {
        self.host = host
        self.document = document
    }
}

public struct PluginMenuItem {
    public enum Placement: String, Sendable {
        case pluginsMenu
        case editMenu
        case viewMenu
        case contextMenu
    }

    public let title: String
    public let commandIdentifier: String
    public let placement: Placement

    public init(title: String, commandIdentifier: String, placement: Placement = .pluginsMenu) {
        self.title = title
        self.commandIdentifier = commandIdentifier
        self.placement = placement
    }
}

/// A docking panel contributed by a plugin.
public struct PluginPanelDescriptor {
    public enum Placement: String, Sendable {
        case leftSidebar
        case rightSidebar
        case bottomBar
    }

    public let identifier: String
    public let title: String
    /// SF Symbol name for the panel's tab.
    public let symbolName: String
    public let placement: Placement
    public let preferredSize: Double
    /// Called on the main thread the first time the panel is shown.
    public let makeView: () -> PluginPanelView

    public init(identifier: String,
                title: String,
                symbolName: String = "puzzlepiece.extension",
                placement: Placement = .rightSidebar,
                preferredSize: Double = 280,
                makeView: @escaping () -> PluginPanelView) {
        self.identifier = identifier
        self.title = title
        self.symbolName = symbolName
        self.placement = placement
        self.preferredSize = preferredSize
        self.makeView = makeView
    }
}

/// The document a plugin edits. Implemented by the editor over `TextDocument`;
/// the tests implement it over a bare `TextBuffer`.
public protocol PluginDocument: AnyObject {
    var fileURL: URL? { get }
    var displayName: String { get }
    var languageIdentifier: String? { get }
    var text: String { get }
    var length: Int { get }
    /// Primary selection; additional selections are exposed separately.
    var selectedRange: Range<Int> { get set }
    var selectedRanges: [Range<Int>] { get }

    func string(in range: Range<Int>) -> String
    func replace(range: Range<Int>, with replacement: String)
    /// Groups several replacements into one undo step.
    func performGrouped(_ body: () -> Void)
    func lineNumber(at offset: Int) -> Int
    func offsetOfLineStart(_ line: Int) -> Int
}

extension PluginDocument {
    public var selectedText: String { string(in: selectedRange) }

    /// Replaces the selection, or the whole document when nothing is selected —
    /// the behaviour a formatter plugin wants.
    public func replaceSelectionOrAll(with replacement: String) {
        if selectedRange.isEmpty {
            replace(range: 0..<length, with: replacement)
        } else {
            replace(range: selectedRange, with: replacement)
        }
    }
}

/// Services the host offers to plugins.
public protocol PluginHost: AnyObject {
    var apiVersion: PluginAPIVersion { get }
    /// Identifier of the plugin currently being activated; the host uses it to
    /// attribute registrations so they can be removed on disable.
    var activePluginIdentifier: String? { get }

    var activeDocument: PluginDocument? { get }
    var openDocuments: [PluginDocument] { get }

    func register(command: PluginCommand)
    func register(menuItem: PluginMenuItem)
    func register(panel: PluginPanelDescriptor)

    /// Shows a panel the plugin registered.
    func showPanel(identifier: String)

    /// A private directory for the plugin's own files.
    func storageDirectory(forPlugin identifier: String) -> URL

    func showMessage(_ message: String, style: PluginMessageStyle)
    func log(_ message: String)

    /// Runs `body` on the main thread; plugin work that touches the UI must go
    /// through this.
    func performOnMainThread(_ body: @escaping () -> Void)
}

public enum PluginMessageStyle: String, Sendable {
    case informational
    case warning
    case error
}

public enum PluginError: LocalizedError, Equatable {
    case incompatibleAPIVersion(required: PluginAPIVersion, host: PluginAPIVersion)
    case missingPrincipalClass(String)
    case principalClassIsNotAPlugin(String)
    case bundleLoadFailed(String)
    case activationFailed(String)
    case noActiveDocument

    public var errorDescription: String? {
        switch self {
        case let .incompatibleAPIVersion(required, host):
            return "Plugin vereist API-versie \(required); Inkline biedt \(host)."
        case let .missingPrincipalClass(name):
            return "De plugin-bundel \(name) heeft geen NSPrincipalClass."
        case let .principalClassIsNotAPlugin(name):
            return "De hoofdklasse van \(name) voldoet niet aan InklinePlugin."
        case let .bundleLoadFailed(reason):
            return "De plugin kon niet worden geladen: \(reason)"
        case let .activationFailed(reason):
            return "De plugin kon niet worden geactiveerd: \(reason)"
        case .noActiveDocument:
            return "Er is geen actief document."
        }
    }
}
