import Foundation
import Combine
import InklineCore

/// Preferences, stored as one JSON blob in `UserDefaults`.
///
/// One blob rather than thirty keys: the settings are a value type in the core,
/// they version cleanly (decoding tolerates missing keys), and exporting them is
/// a file copy.
final class SettingsStore: ObservableObject {

    private static let defaultsKey = "nl.rorymeijer.inkline.settings"

    @Published var settings: EditorSettings {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(EditorSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func reset() {
        settings = .default
    }

    // MARK: Recent files

    private static let recentKey = "nl.rorymeijer.inkline.recentFiles"

    var recentFiles: [URL] {
        (defaults.array(forKey: Self.recentKey) as? [String] ?? []).map { URL(fileURLWithPath: $0) }
    }

    func noteRecentFile(_ url: URL) {
        var paths = recentFiles.map(\.path)
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        defaults.set(Array(paths.prefix(settings.maximumRecentFiles)), forKey: Self.recentKey)
    }

    func clearRecentFiles() {
        defaults.removeObject(forKey: Self.recentKey)
    }
}
