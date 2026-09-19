import XCTest
@testable import InklinePluginAPI
import InklineCore

/// A plugin that exists only in this test: it registers one command that
/// uppercases the selection, a menu item and a panel. Exercising the real
/// registration path is the point — if this compiles and runs, a third-party
/// plugin written against the documented API will too.
private final class UppercasePlugin: InklinePlugin {

    static let manifest = PluginManifest(identifier: "nl.rorymeijer.inkline.test.uppercase",
                                         name: "Hoofdletters",
                                         version: "1.0",
                                         author: "Test",
                                         summary: "Maakt de selectie hoofdletters",
                                         capabilities: [.editText, .contributeMenu])

    private(set) var didActivate = false
    private(set) var didDeactivate = false

    init() {}

    func activate(host: PluginHost) throws {
        didActivate = true
        host.register(command: PluginCommand(identifier: "test.uppercase",
                                             title: "Selectie naar hoofdletters",
                                             keyEquivalent: "u",
                                             modifierDescription: "cmd,shift",
                                             isEnabled: { $0 != nil }) { invocation in
            guard let document = invocation.document else { throw PluginError.noActiveDocument }
            document.replaceSelectionOrAll(with: document.selectedText.uppercased())
        })
        host.register(menuItem: PluginMenuItem(title: "Selectie naar hoofdletters",
                                               commandIdentifier: "test.uppercase"))
    }

    func deactivate() {
        didDeactivate = true
    }
}

private final class FailingPlugin: InklinePlugin {
    static let manifest = PluginManifest(identifier: "nl.rorymeijer.inkline.test.failing",
                                         name: "Stuk",
                                         version: "1.0")
    init() {}
    func activate(host: PluginHost) throws {
        throw PluginError.activationFailed("expres kapot")
    }
}

private final class FuturePlugin: InklinePlugin {
    static let manifest = PluginManifest(identifier: "nl.rorymeijer.inkline.test.future",
                                         name: "Toekomst",
                                         version: "1.0",
                                         apiVersion: PluginAPIVersion(major: 99, minor: 0))
    init() {}
    func activate(host: PluginHost) throws {}
}

final class PluginAPITests: XCTestCase {

    private var registry: CommandRegistry!
    private var host: DefaultPluginHost!
    private var manager: PluginManager!
    private var directory: URL!
    private var document: BufferPluginDocument!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("inkline-plugins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        registry = CommandRegistry()
        host = DefaultPluginHost(registry: registry, storageRoot: directory)
        document = BufferPluginDocument(buffer: TextBuffer(text: "hallo wereld"))
        host.documentProvider = { [unowned self] in self.document }
        host.openDocumentsProvider = { [unowned self] in [self.document] }
        manager = PluginManager(searchPaths: [directory],
                                stateURL: directory.appendingPathComponent("enabled.json"),
                                host: host)
    }

    override func tearDownWithError() throws {
        manager.unloadAll()
        try? FileManager.default.removeItem(at: directory)
    }

    func testActivatingAPluginRegistersItsCommand() throws {
        let plugin = UppercasePlugin()
        try host.withActivePlugin(UppercasePlugin.manifest.identifier) {
            try manager.registerBuiltIn(plugin)
        }

        XCTAssertTrue(plugin.didActivate)
        XCTAssertNotNil(registry.command(for: "test.uppercase"))
        XCTAssertEqual(registry.commands(in: .plugin).count, 1)
        XCTAssertEqual(host.menuItems.count, 1)
    }

    func testCommandEditsTheDocument() throws {
        try host.withActivePlugin(UppercasePlugin.manifest.identifier) {
            try manager.registerBuiltIn(UppercasePlugin())
        }
        document.selectedRange = 0..<5

        let command = try XCTUnwrap(registry.command(for: "test.uppercase"))
        try command.handler(CommandContext(document: nil))

        XCTAssertEqual(document.text, "HALLO wereld")
    }

    func testDisablingAPluginRemovesItsContributions() throws {
        let plugin = UppercasePlugin()
        try host.withActivePlugin(UppercasePlugin.manifest.identifier) {
            try manager.registerBuiltIn(plugin)
        }
        XCTAssertNotNil(registry.command(for: "test.uppercase"))

        manager.unload(identifier: UppercasePlugin.manifest.identifier)
        host.removeContributions(ofPlugin: UppercasePlugin.manifest.identifier)

        XCTAssertTrue(plugin.didDeactivate)
        XCTAssertNil(registry.command(for: "test.uppercase"))
        XCTAssertTrue(host.menuItems.isEmpty)
    }

    func testIncompatibleAPIVersionIsRejected() {
        XCTAssertThrowsError(try manager.registerBuiltIn(FuturePlugin())) { error in
            guard case PluginError.incompatibleAPIVersion = error else {
                return XCTFail("verwachtte een versiefout, kreeg \(error)")
            }
        }
        XCTAssertTrue(registry.commands.isEmpty)
    }

    func testFailingActivationIsReportedAndDoesNotLoad() {
        XCTAssertThrowsError(try manager.registerBuiltIn(FailingPlugin()))
        XCTAssertNil(manager.plugin(identifier: FailingPlugin.manifest.identifier))
    }

    func testPanelRegistrationAndReveal() throws {
        var revealed: String?
        host.panelRevealer = { revealed = $0 }
        host.register(panel: PluginPanelDescriptor(identifier: "test.panel",
                                                   title: "Testpaneel",
                                                   placement: .bottomBar,
                                                   makeView: { PluginPanelViewStub() }))
        XCTAssertEqual(host.panels.count, 1)
        host.showPanel(identifier: "test.panel")
        XCTAssertEqual(revealed, "test.panel")
    }

    func testStorageDirectoryIsCreatedPerPlugin() {
        let url = host.storageDirectory(forPlugin: "nl.rorymeijer.inkline.test.uppercase")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.lastPathComponent, "nl.rorymeijer.inkline.test.uppercase")
    }

    func testAPIVersionCompatibility() {
        let host = PluginAPIVersion(major: 1, minor: 3)
        XCTAssertTrue(PluginAPIVersion(major: 1, minor: 0).isCompatible(with: host))
        XCTAssertTrue(PluginAPIVersion(major: 1, minor: 3).isCompatible(with: host))
        XCTAssertFalse(PluginAPIVersion(major: 1, minor: 4).isCompatible(with: host))
        XCTAssertFalse(PluginAPIVersion(major: 2, minor: 0).isCompatible(with: host))
        XCTAssertEqual(PluginAPIVersion(string: "2.5"), PluginAPIVersion(major: 2, minor: 5))
        XCTAssertEqual(PluginAPIVersion(string: "3"), PluginAPIVersion(major: 3, minor: 0))
    }

    func testDiscoveryIgnoresNonPluginDirectories() throws {
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("iets.anders"),
                                                withIntermediateDirectories: true)
        XCTAssertTrue(manager.discover().isEmpty)
    }

    func testEnabledStateIsPersisted() throws {
        try host.withActivePlugin(UppercasePlugin.manifest.identifier) {
            try manager.registerBuiltIn(UppercasePlugin())
        }
        XCTAssertTrue(manager.isEnabled(identifier: UppercasePlugin.manifest.identifier))

        try manager.setEnabled(false, identifier: UppercasePlugin.manifest.identifier)
        XCTAssertFalse(manager.isEnabled(identifier: UppercasePlugin.manifest.identifier))

        let reloaded = PluginManager(searchPaths: [directory],
                                     stateURL: directory.appendingPathComponent("enabled.json"),
                                     host: host)
        XCTAssertFalse(reloaded.isEnabled(identifier: UppercasePlugin.manifest.identifier))
    }

    func testBufferDocumentAdapter() {
        let document = BufferPluginDocument(buffer: TextBuffer(text: "een\ntwee\ndrie"))
        document.selectedRange = 4..<8
        XCTAssertEqual(document.selectedText, "twee")
        XCTAssertEqual(document.lineNumber(at: 5), 1)
        XCTAssertEqual(document.offsetOfLineStart(2), 9)

        document.performGrouped {
            document.replace(range: 4..<8, with: "TWEE")
            document.replace(range: 0..<3, with: "EEN")
        }
        XCTAssertEqual(document.text, "EEN\nTWEE\ndrie")

        document.buffer.undo()
        XCTAssertEqual(document.text, "een\ntwee\ndrie", "gegroepeerde bewerkingen zijn één undo-stap")
    }

    func testManifestFromInfoDictionaryKeys() {
        let manifest = PluginManifest(identifier: "x.y", name: "X", version: "1.2",
                                      capabilities: [.editText, .network])
        XCTAssertEqual(manifest.capabilities, [.editText, .network])
        XCTAssertEqual(manifest.apiVersion, .current)
    }
}

#if canImport(AppKit)
import AppKit
private func PluginPanelViewStub() -> NSView { NSView() }
#else
private final class StubView {}
private func PluginPanelViewStub() -> AnyObject { StubView() }
#endif
