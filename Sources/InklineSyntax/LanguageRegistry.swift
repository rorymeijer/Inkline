import Foundation
import InklineCore

/// Loads language definitions from disk and answers "which language is this
/// file?".
///
/// Definitions come from three places, later ones overriding earlier ones by
/// identifier:
/// 1. the bundled `Languages` resource directory,
/// 2. `~/Library/Application Support/Inkline/Languages`,
/// 3. definitions registered at runtime by plugins.
public final class LanguageRegistry {

    public private(set) var languages: [LanguageDefinition] = []
    public var onChange: (() -> Void)?

    private var byIdentifier: [String: LanguageDefinition] = [:]
    private var byExtension: [String: [LanguageDefinition]] = [:]
    private var byFileName: [String: [LanguageDefinition]] = [:]

    public init(languages: [LanguageDefinition] = []) {
        register(contentsOf: languages.isEmpty ? [.plainText] : languages)
    }

    // MARK: Loading

    /// Loads every `*.json` in `directory`. Invalid files are skipped and
    /// reported, never fatal: one broken language file must not stop the app
    /// from opening.
    @discardableResult
    public func loadDefinitions(in directory: URL) -> [LanguageLoadIssue] {
        var issues = [LanguageLoadIssue]()
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                 includingPropertiesForKeys: nil)) ?? []
        var loaded = [LanguageDefinition]()
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.pathExtension.lowercased() == "json" {
            do {
                let data = try Data(contentsOf: url)
                loaded.append(try JSONDecoder().decode(LanguageDefinition.self, from: data))
            } catch {
                issues.append(LanguageLoadIssue(url: url, message: error.localizedDescription))
            }
        }
        register(contentsOf: loaded)
        return issues
    }

    public func register(_ language: LanguageDefinition) {
        register(contentsOf: [language])
    }

    public func register(contentsOf newLanguages: [LanguageDefinition]) {
        for language in newLanguages {
            byIdentifier[language.identifier] = language
        }
        rebuildIndexes()
        onChange?()
    }

    public func unregister(identifier: String) {
        byIdentifier.removeValue(forKey: identifier)
        rebuildIndexes()
        onChange?()
    }

    private func rebuildIndexes() {
        languages = byIdentifier.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        byExtension = [:]
        byFileName = [:]
        for language in languages {
            for fileExtension in language.fileExtensions {
                byExtension[fileExtension.lowercased(), default: []].append(language)
            }
            for name in language.fileNames {
                byFileName[name.lowercased(), default: []].append(language)
            }
        }
        for key in byExtension.keys {
            byExtension[key]?.sort { $0.priority > $1.priority }
        }
        for key in byFileName.keys {
            byFileName[key]?.sort { $0.priority > $1.priority }
        }
    }

    // MARK: Lookup

    public func language(withIdentifier identifier: String) -> LanguageDefinition? {
        byIdentifier[identifier]
    }

    public var plainText: LanguageDefinition {
        byIdentifier["plaintext"] ?? .plainText
    }

    /// Full name match first (`Dockerfile`, `Package.swift`), then extension,
    /// then the first line. Matches what users expect from Notepad++ and from
    /// every editor that gets this right.
    public func language(for url: URL, firstLine: String? = nil) -> LanguageDefinition? {
        if let match = byFileName[url.lastPathComponent.lowercased()]?.first { return match }
        let fileExtension = url.pathExtension.lowercased()
        if !fileExtension.isEmpty, let match = byExtension[fileExtension]?.first { return match }
        if let firstLine, let match = language(forFirstLine: firstLine) { return match }
        return nil
    }

    public func language(forFirstLine firstLine: String) -> LanguageDefinition? {
        let trimmed = String(firstLine.prefix(200))
        for language in languages {
            guard let pattern = language.firstLinePattern,
                  let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(location: 0, length: (trimmed as NSString).length)
            if regex.firstMatch(in: trimmed, options: [], range: range) != nil { return language }
        }
        return nil
    }

    /// Best guess for a document: file name, then content, then plain text.
    public func bestMatch(for url: URL?, text: String) -> LanguageDefinition {
        let firstLine = text.prefix(while: { $0 != "\n" })
        if let url, let match = language(for: url, firstLine: String(firstLine)) { return match }
        if let match = language(forFirstLine: String(firstLine)) { return match }
        return plainText
    }

    /// Languages grouped by first letter, for the Taal menu.
    public func groupedByInitial() -> [(String, [LanguageDefinition])] {
        let groups = Dictionary(grouping: languages) { language in
            String(language.name.prefix(1)).uppercased()
        }
        return groups.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

public struct LanguageLoadIssue: Equatable, Sendable {
    public let url: URL
    public let message: String
}

extension LanguageRegistry {
    /// The registry the app uses: bundled definitions plus the user's own.
    public static func standard(bundle: Bundle = .module,
                                userDirectory: URL? = nil) -> LanguageRegistry {
        let registry = LanguageRegistry()
        if let directory = bundle.url(forResource: "Languages", withExtension: nil) {
            registry.loadDefinitions(in: directory)
        }
        if let userDirectory {
            registry.loadDefinitions(in: userDirectory)
        }
        return registry
    }
}
