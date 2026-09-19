import AppKit
import Combine
import InklineCore
import InklinePluginAPI
import InklineSyntax

/// The services every window and view needs, created once at launch.
///
/// Kept as one explicit object rather than a scattering of singletons: it makes
/// the dependency graph obvious, and it is what lets the whole app be
/// instantiated in a test with temporary directories.
@MainActor
final class AppEnvironment: ObservableObject {

    // Persistent services
    let settingsStore: SettingsStore
    let languageRegistry: LanguageRegistry
    let themeRegistry: ThemeRegistry
    let commandRegistry: CommandRegistry
    let macroStore: MacroStore
    let macroRecorder = MacroRecorder()
    let sessionStore: SessionStore
    let grammarLoader: TreeSitterGrammarLoader
    let pluginHost: DefaultPluginHost
    let pluginManager: PluginManager
    let updater = UpdaterController()

    @Published private(set) var style: ThemeStyle
    @Published private(set) var appearance: Theme.Appearance
    @Published var pluginDescriptors: [PluginDescriptor] = []
    @Published var isRecordingMacro = false
    @Published var lastMessage: String?

    /// The workspace of the key window. Commands registered in the shared
    /// registry (menus, macros, plugins) act on whatever that is right now.
    var activeWorkspaceProvider: (() -> WorkspaceModel?)?
    var activeWorkspace: WorkspaceModel? { activeWorkspaceProvider?() }

    var settings: EditorSettings { settingsStore.settings }

    private var cancellables = Set<AnyCancellable>()

    // MARK: Directories

    static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let url = base.appendingPathComponent("Inkline", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    let supportDirectory: URL

    var userLanguagesDirectory: URL { supportDirectory.appendingPathComponent("Languages", isDirectory: true) }
    var userThemesDirectory: URL { supportDirectory.appendingPathComponent("Themes", isDirectory: true) }
    var userPluginsDirectory: URL { supportDirectory.appendingPathComponent("Plugins", isDirectory: true) }
    var userGrammarsDirectory: URL { supportDirectory.appendingPathComponent("Grammars", isDirectory: true) }

    // MARK: Creation

    init(supportDirectory: URL = AppEnvironment.applicationSupportDirectory()) {
        self.supportDirectory = supportDirectory
        for directory in ["Languages", "Themes", "Plugins", "Grammars", "Sessions"] {
            try? FileManager.default.createDirectory(at: supportDirectory.appendingPathComponent(directory),
                                                     withIntermediateDirectories: true)
        }

        settingsStore = SettingsStore()
        languageRegistry = LanguageRegistry.standard(bundle: .inklineSyntax,
                                                     userDirectory: supportDirectory.appendingPathComponent("Languages"))
        themeRegistry = ThemeRegistry.standard(bundle: .inklineSyntax,
                                               userDirectory: supportDirectory.appendingPathComponent("Themes"))
        commandRegistry = CommandRegistry()
        macroStore = MacroStore(applicationSupportDirectory: supportDirectory)
        sessionStore = SessionStore(directory: supportDirectory.appendingPathComponent("Sessions"))
        grammarLoader = TreeSitterGrammarLoader(
            searchPaths: TreeSitterGrammarLoader.standardSearchPaths(bundle: .main,
                                                                     applicationSupport: supportDirectory))

        let settings = settingsStore.settings
        let systemIsDark = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let appearance: Theme.Appearance = settings.followsSystemAppearance
            ? (systemIsDark ? .dark : .light)
            : .light
        self.appearance = appearance
        let theme = themeRegistry.theme(withIdentifier: appearance == .dark ? settings.darkThemeIdentifier
                                                                            : settings.lightThemeIdentifier,
                                        appearance: appearance)
        style = ThemeStyle(theme: theme,
                           fontName: settings.fontName,
                           fontSize: settings.fontSize,
                           lineHeightMultiple: settings.lineHeightMultiple)

        pluginHost = DefaultPluginHost(registry: commandRegistry,
                                       storageRoot: supportDirectory.appendingPathComponent("PluginData"))
        pluginManager = PluginManager(searchPaths: [Bundle.main.builtInPlugInsURL,
                                                    supportDirectory.appendingPathComponent("Plugins")].compactMap { $0 },
                                      stateURL: supportDirectory.appendingPathComponent("EnabledPlugins.json"),
                                      host: pluginHost)

        settingsStore.$settings
            .sink { [weak self] newSettings in self?.settingsDidChange(newSettings) }
            .store(in: &cancellables)

        macroRecorder.onChange = { [weak self] recorder in
            Task { @MainActor in self?.isRecordingMacro = recorder.isRecording }
        }
        pluginHost.messageHandler = { [weak self] message, _ in
            Task { @MainActor in self?.lastMessage = message }
        }
        pluginHost.logHandler = { message in
            NSLog("[Inkline-plugin] %@", message)
        }
        pluginManager.onChange = { [weak self] descriptors in
            Task { @MainActor in self?.pluginDescriptors = descriptors }
        }
    }

    // MARK: Lifecycle

    func loadPlugins() {
        pluginManager.discover()
        let failures = pluginManager.loadEnabledPlugins()
        if !failures.isEmpty {
            lastMessage = failures
                .map { "\($0.0.manifest.name): \($0.1.localizedDescription)" }
                .joined(separator: "\n")
        }
    }

    func updateAppearance(systemIsDark: Bool) {
        let settings = settingsStore.settings
        let newAppearance: Theme.Appearance = settings.followsSystemAppearance
            ? (systemIsDark ? .dark : .light)
            : appearance
        guard newAppearance != appearance else { return }
        appearance = newAppearance
        rebuildStyle()
    }

    func selectTheme(identifier: String) {
        guard let theme = themeRegistry.theme(withIdentifier: identifier) else { return }
        var settings = settingsStore.settings
        if theme.appearance == .dark {
            settings.darkThemeIdentifier = identifier
        } else {
            settings.lightThemeIdentifier = identifier
        }
        settings.followsSystemAppearance = false
        appearance = theme.appearance
        settingsStore.settings = settings
    }

    private func settingsDidChange(_ newSettings: EditorSettings) {
        rebuildStyle(with: newSettings)
    }

    private func rebuildStyle(with newSettings: EditorSettings? = nil) {
        let settings = newSettings ?? settingsStore.settings
        let identifier = appearance == .dark ? settings.darkThemeIdentifier : settings.lightThemeIdentifier
        let theme = themeRegistry.theme(withIdentifier: identifier, appearance: appearance)
        style = ThemeStyle(theme: theme,
                           fontName: settings.fontName,
                           fontSize: settings.fontSize,
                           lineHeightMultiple: settings.lineHeightMultiple)
    }

    func adjustFontSize(by delta: Double) {
        var settings = settingsStore.settings
        settings.fontSize = min(48, max(8, settings.fontSize + delta))
        settingsStore.settings = settings
    }

    func resetFontSize() {
        var settings = settingsStore.settings
        settings.fontSize = EditorSettings.default.fontSize
        settingsStore.settings = settings
    }
}

extension Bundle {
    /// The resource bundle of the `InklineSyntax` package target, which carries
    /// the bundled languages and themes.
    static var inklineSyntax: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        // Inside the app, SwiftPM resource bundles sit in the app bundle.
        let name = "Inkline_InklineSyntax.bundle"
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .main
        #endif
    }
}
