import Foundation

/// Semantic-ish version for the plugin API. A plugin declares the version it
/// was built against; the host loads it when the major version matches and the
/// plugin does not need a newer minor version than the host provides.
public struct PluginAPIVersion: Codable, Equatable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    public init?(string: String) {
        let parts = string.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 1 else { return nil }
        major = parts[0]
        minor = parts.count > 1 ? parts[1] : 0
    }

    public static func < (lhs: PluginAPIVersion, rhs: PluginAPIVersion) -> Bool {
        lhs.major == rhs.major ? lhs.minor < rhs.minor : lhs.major < rhs.major
    }

    public var description: String { "\(major).\(minor)" }

    /// The version this build of Inkline implements.
    public static let current = PluginAPIVersion(major: 1, minor: 0)

    public func isCompatible(with host: PluginAPIVersion) -> Bool {
        major == host.major && minor <= host.minor
    }
}

/// Everything the plugin manager needs to know about a plugin before loading
/// its code. Mirrors the keys in the bundle's `Info.plist`.
public struct PluginManifest: Codable, Equatable, Identifiable, Sendable {
    public let identifier: String
    public let name: String
    public let version: String
    public let author: String?
    public let summary: String?
    public let apiVersion: PluginAPIVersion
    /// Extra capabilities the plugin asks for. Purely informational today, but
    /// shown in the plugin manager so users can see what a plugin touches.
    public let capabilities: [Capability]

    public var id: String { identifier }

    public enum Capability: String, Codable, CaseIterable, Sendable {
        case editText
        case readFiles
        case writeFiles
        case runProcesses
        case network
        case contributePanel
        case contributeMenu
    }

    public init(identifier: String,
                name: String,
                version: String,
                author: String? = nil,
                summary: String? = nil,
                apiVersion: PluginAPIVersion = .current,
                capabilities: [Capability] = []) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.author = author
        self.summary = summary
        self.apiVersion = apiVersion
        self.capabilities = capabilities
    }

    /// Reads the manifest from a plugin bundle's `Info.plist`.
    ///
    /// ```xml
    /// <key>InklinePluginIdentifier</key>  <string>nl.rorymeijer.inkline.json-formatter</string>
    /// <key>InklinePluginAPIVersion</key>  <string>1.0</string>
    /// <key>NSPrincipalClass</key>         <string>JSONFormatterPlugin</string>
    /// ```
    public init?(bundle: Bundle) {
        guard let info = bundle.infoDictionary else { return nil }
        let identifier = (info["InklinePluginIdentifier"] as? String)
            ?? (info["CFBundleIdentifier"] as? String)
        guard let identifier else { return nil }
        self.identifier = identifier
        name = (info["InklinePluginName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? identifier
        version = (info["CFBundleShortVersionString"] as? String) ?? "0"
        author = info["InklinePluginAuthor"] as? String
        summary = info["InklinePluginSummary"] as? String
        apiVersion = (info["InklinePluginAPIVersion"] as? String).flatMap(PluginAPIVersion.init(string:))
            ?? PluginAPIVersion(major: 1, minor: 0)
        capabilities = (info["InklinePluginCapabilities"] as? [String])?
            .compactMap(Capability.init(rawValue:)) ?? []
    }
}
