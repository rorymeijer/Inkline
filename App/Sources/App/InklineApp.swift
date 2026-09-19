import AppKit
import SwiftUI
import InklineCore

/// Inkline — "Elke taal. Elk bestand. Meteen open."
@main
struct InklineApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(environment: appDelegate.environment)
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            InklineCommands(environment: appDelegate.environment)
        }

        Settings {
            SettingsView(environment: appDelegate.environment)
        }
    }
}

/// Creates the workspace for a window and wires it to the shared environment.
struct RootView: View {

    @ObservedObject var environment: AppEnvironment
    @StateObject private var workspace: WorkspaceModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _workspace = StateObject(wrappedValue: WorkspaceModel(environment: environment))
    }

    var body: some View {
        MainWindowView(workspace: workspace, environment: environment)
            .onAppear {
                environment.activeWorkspaceProvider = { [weak workspace] in workspace }
                (NSApp.delegate as? AppDelegate)?.register(workspace: workspace)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                environment.activeWorkspaceProvider = { [weak workspace] in workspace }
            }
            .onChange(of: environment.style.font) { _ in
                for document in workspace.documents.values {
                    document.updateStyle(environment.style)
                }
            }
            .onChange(of: environment.settings) { settings in
                for document in workspace.documents.values {
                    document.updateSettings(settings)
                }
            }
    }

}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let environment = AppEnvironment()
    private weak var workspace: WorkspaceModel?
    private var appearanceObservation: NSKeyValueObservation?
    /// Files handed to us before a window existed (double-click on a file with
    /// Inkline not running).
    private var pendingURLs: [URL] = []

    func register(workspace: WorkspaceModel) {
        self.workspace = workspace
        environment.activeWorkspaceProvider = { [weak workspace] in workspace }
        restoreSessionIfNeeded()
        openPendingURLs()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        BuiltInCommands.register(in: environment)
        environment.loadPlugins()
        environment.updater.automaticallyChecksForUpdates = environment.settings.checksForUpdatesAutomatically

        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] app, _ in
            Task { @MainActor in
                let isDark = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                self?.environment.updateAppearance(systemIsDark: isDark)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        workspace?.saveAutosaveSession()
        guard let workspace, workspace.hasUnsavedChanges else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Er zijn niet-bewaarde wijzigingen",
                                              comment: "Waarschuwing bij afsluiten")
        alert.informativeText = NSLocalizedString(
            "Inkline bewaart je tabbladen en herstelt ze bij de volgende start. Toch afsluiten?",
            comment: "Toelichting bij afsluiten")
        alert.addButton(withTitle: NSLocalizedString("Afsluiten", comment: "Knop"))
        alert.addButton(withTitle: NSLocalizedString("Alles bewaren", comment: "Knop"))
        alert.addButton(withTitle: NSLocalizedString("Annuleer", comment: "Knop"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .terminateNow
        case .alertSecondButtonReturn:
            workspace.saveAll()
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        workspace?.saveAutosaveSession()
        environment.pluginManager.unloadAll()
    }

    // MARK: Opening files from Finder, the Dock and drag & drop

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let workspace else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                workspace.addExplorerRoot(url)
            } else {
                workspace.open(url: url)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openPendingURLs() {
        guard !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs = []
        application(NSApp, open: urls)
    }

    private func restoreSessionIfNeeded() {
        guard environment.settings.restoresSessionOnLaunch,
              let workspace,
              workspace.documents.isEmpty,
              let state = environment.sessionStore.loadAutosave(),
              state.documentCount > 0 else {
            if workspace?.documents.isEmpty == true, pendingURLs.isEmpty {
                workspace?.newDocument()
            }
            return
        }
        workspace.restore(state)
    }
}
