import Foundation
import InklineCore

/// A plugin found on disk, whether or not it is loaded.
public struct PluginDescriptor: Identifiable, Equatable {
    public let manifest: PluginManifest
    public let url: URL
    public private(set) var isEnabled: Bool
    public private(set) var isLoaded: Bool
    public private(set) var loadError: String?

    public var id: String { manifest.identifier }

    public init(manifest: PluginManifest,
                url: URL,
                isEnabled: Bool = false,
                isLoaded: Bool = false,
                loadError: String? = nil) {
        self.manifest = manifest
        self.url = url
        self.isEnabled = isEnabled
        self.isLoaded = isLoaded
        self.loadError = loadError
    }

    mutating func update(isEnabled: Bool? = nil, isLoaded: Bool? = nil, loadError: String?? = nil) {
        if let isEnabled { self.isEnabled = isEnabled }
        if let isLoaded { self.isLoaded = isLoaded }
        if let loadError { self.loadError = loadError }
    }
}

/// Finds, loads, enables and disables plugins.
///
/// Plugins are searched for in, in order:
/// 1. `Inkline.app/Contents/PlugIns` (the bundled examples),
/// 2. `~/Library/Application Support/Inkline/Plugins` (the user's own).
///
/// The enabled set is persisted, so a plugin the user switched off stays off.
/// A plugin that throws while loading is recorded with its error and skipped —
/// one bad plugin never stops Inkline from starting.
public final class PluginManager {

    public private(set) var descriptors: [PluginDescriptor] = []
    public var onChange: (([PluginDescriptor]) -> Void)?

    private var instances: [String: InklinePlugin] = [:]
    private let searchPaths: [URL]
    private let stateURL: URL
    private let host: PluginHost
    private var enabledIdentifiers: Set<String>

    public init(searchPaths: [URL], stateURL: URL, host: PluginHost) {
        self.searchPaths = searchPaths
        self.stateURL = stateURL
        self.host = host
        self.enabledIdentifiers = Self.readEnabledIdentifiers(at: stateURL) ?? []
    }

    // MARK: Discovery

    /// Scans the search paths. Does not load any code.
    @discardableResult
    public func discover() -> [PluginDescriptor] {
        var found = [String: PluginDescriptor]()
        for directory in searchPaths {
            let contents = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                         includingPropertiesForKeys: nil)) ?? []
            for url in contents where url.pathExtension == PluginManager.bundleExtension {
                guard let bundle = Bundle(url: url), let manifest = PluginManifest(bundle: bundle) else { continue }
                // A user's copy shadows a bundled one with the same identifier.
                found[manifest.identifier] = PluginDescriptor(manifest: manifest,
                                                              url: url,
                                                              isEnabled: enabledIdentifiers.contains(manifest.identifier),
                                                              isLoaded: instances[manifest.identifier] != nil)
            }
        }
        descriptors = found.values.sorted { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }
        onChange?(descriptors)
        return descriptors
    }

    public static let bundleExtension = "inklineplugin"

    /// Loads every enabled plugin. Returns the errors that occurred, so the app
    /// can show them once instead of one alert per plugin.
    @discardableResult
    public func loadEnabledPlugins() -> [(PluginDescriptor, Error)] {
        var failures = [(PluginDescriptor, Error)]()
        for descriptor in descriptors where descriptor.isEnabled {
            do {
                try load(identifier: descriptor.manifest.identifier)
            } catch {
                failures.append((descriptor, error))
            }
        }
        return failures
    }

    // MARK: Loading

    public func load(identifier: String) throws {
        guard instances[identifier] == nil else { return }
        guard let index = descriptors.firstIndex(where: { $0.manifest.identifier == identifier }) else {
            throw PluginError.bundleLoadFailed(identifier)
        }
        let descriptor = descriptors[index]

        guard descriptor.manifest.apiVersion.isCompatible(with: host.apiVersion) else {
            let error = PluginError.incompatibleAPIVersion(required: descriptor.manifest.apiVersion,
                                                           host: host.apiVersion)
            descriptors[index].update(isLoaded: false, loadError: error.localizedDescription)
            onChange?(descriptors)
            throw error
        }

        guard let bundle = Bundle(url: descriptor.url) else {
            throw PluginError.bundleLoadFailed(descriptor.url.lastPathComponent)
        }
        do {
            try bundle.loadAndReturnError()
        } catch {
            descriptors[index].update(isLoaded: false, loadError: error.localizedDescription)
            onChange?(descriptors)
            throw PluginError.bundleLoadFailed(error.localizedDescription)
        }

        guard let principalClass = bundle.principalClass else {
            throw PluginError.missingPrincipalClass(descriptor.url.lastPathComponent)
        }
        guard let pluginType = principalClass as? InklinePlugin.Type else {
            throw PluginError.principalClassIsNotAPlugin(String(describing: principalClass))
        }

        let plugin = pluginType.init()
        do {
            try plugin.activate(host: host)
        } catch {
            descriptors[index].update(isLoaded: false, loadError: error.localizedDescription)
            onChange?(descriptors)
            throw PluginError.activationFailed(error.localizedDescription)
        }

        instances[identifier] = plugin
        descriptors[index].update(isLoaded: true, loadError: .some(nil))
        onChange?(descriptors)
    }

    /// Registers a plugin that is compiled into the app (or into a test) rather
    /// than loaded from a bundle. Same lifecycle, no dynamic loading.
    public func registerBuiltIn(_ plugin: InklinePlugin, at url: URL? = nil) throws {
        let manifest = type(of: plugin).manifest
        guard manifest.apiVersion.isCompatible(with: host.apiVersion) else {
            throw PluginError.incompatibleAPIVersion(required: manifest.apiVersion, host: host.apiVersion)
        }
        try plugin.activate(host: host)
        instances[manifest.identifier] = plugin
        if let index = descriptors.firstIndex(where: { $0.manifest.identifier == manifest.identifier }) {
            descriptors[index].update(isEnabled: true, isLoaded: true, loadError: .some(nil))
        } else {
            descriptors.append(PluginDescriptor(manifest: manifest,
                                                url: url ?? URL(fileURLWithPath: "/"),
                                                isEnabled: true,
                                                isLoaded: true))
        }
        enabledIdentifiers.insert(manifest.identifier)
        onChange?(descriptors)
    }

    public func unload(identifier: String) {
        guard let plugin = instances.removeValue(forKey: identifier) else { return }
        plugin.deactivate()
        if let index = descriptors.firstIndex(where: { $0.manifest.identifier == identifier }) {
            descriptors[index].update(isLoaded: false)
        }
        onChange?(descriptors)
    }

    public func unloadAll() {
        for identifier in Array(instances.keys) { unload(identifier: identifier) }
    }

    public func plugin(identifier: String) -> InklinePlugin? {
        instances[identifier]
    }

    // MARK: Enabling

    public func setEnabled(_ enabled: Bool, identifier: String) throws {
        if enabled {
            enabledIdentifiers.insert(identifier)
        } else {
            enabledIdentifiers.remove(identifier)
        }
        if let index = descriptors.firstIndex(where: { $0.manifest.identifier == identifier }) {
            descriptors[index].update(isEnabled: enabled)
        }
        persistEnabledIdentifiers()

        if enabled {
            try load(identifier: identifier)
        } else {
            unload(identifier: identifier)
        }
        onChange?(descriptors)
    }

    public func isEnabled(identifier: String) -> Bool {
        enabledIdentifiers.contains(identifier)
    }

    /// Installs a plugin bundle by copying it into the user plugins directory.
    @discardableResult
    public func install(from url: URL, into directory: URL) throws -> PluginDescriptor {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        discover()
        guard let bundle = Bundle(url: destination),
              let manifest = PluginManifest(bundle: bundle) else {
            throw PluginError.bundleLoadFailed(destination.lastPathComponent)
        }
        return descriptors.first { $0.manifest.identifier == manifest.identifier }
            ?? PluginDescriptor(manifest: manifest, url: destination)
    }

    // MARK: Persistence

    private func persistEnabledIdentifiers() {
        let data = try? JSONEncoder().encode(Array(enabledIdentifiers).sorted())
        guard let data else { return }
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: stateURL, options: [.atomic])
    }

    private static func readEnabledIdentifiers(at url: URL) -> Set<String>? {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return Set(list)
    }
}
