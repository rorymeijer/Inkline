import Foundation
import InklineSyntax

#if canImport(SwiftTreeSitter)
import SwiftTreeSitter
#endif

/// Loads tree-sitter grammars at runtime from dynamic libraries.
///
/// This is what makes "een nieuwe taal toevoegen zonder codewijziging" true:
/// a grammar is a `libtree-sitter-<taal>.dylib` next to its `highlights.scm`,
/// and the language JSON points at both. Inkline `dlopen`s the library, looks
/// up the `tree_sitter_<grammar>` entry point and hands the result to
/// tree-sitter.
///
/// Grammar directories, searched in order:
/// 1. `Inkline.app/Contents/Resources/Grammars`
/// 2. `~/Library/Application Support/Inkline/Grammars`
public final class TreeSitterGrammarLoader {

    public enum LoaderError: LocalizedError {
        case libraryNotFound(String)
        case openFailed(String, String)
        case symbolNotFound(String)
        case queryNotFound(String)
        case unavailable

        public var errorDescription: String? {
            switch self {
            case let .libraryNotFound(name):
                return "Grammatica-bibliotheek niet gevonden: \(name)"
            case let .openFailed(name, reason):
                return "Kon \(name) niet laden: \(reason)"
            case let .symbolNotFound(symbol):
                return "Het symbool \(symbol) ontbreekt in de grammatica-bibliotheek."
            case let .queryNotFound(path):
                return "Highlight-query niet gevonden: \(path)"
            case .unavailable:
                return "Deze build van Inkline bevat geen tree-sitter-ondersteuning."
            }
        }
    }

    public private(set) var searchPaths: [URL]
    private var handles: [String: UnsafeMutableRawPointer] = [:]
    private var languagePointers: [String: OpaquePointer] = [:]
    private let lock = NSLock()

    public init(searchPaths: [URL]) {
        self.searchPaths = searchPaths
    }

    public func addSearchPath(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard !searchPaths.contains(url) else { return }
        searchPaths.append(url)
    }

    /// Grammars that are actually present on disk — the plugin manager's
    /// "Talen" tab lists these.
    public func availableGrammars() -> [String] {
        var names = Set<String>()
        for directory in searchPaths {
            let contents = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                         includingPropertiesForKeys: nil)) ?? []
            for url in contents where url.pathExtension == "dylib" {
                let name = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "libtree-sitter-", with: "")
                names.insert(name)
            }
        }
        return names.sorted()
    }

    public func locate(_ fileName: String) -> URL? {
        for directory in searchPaths {
            let candidate = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// `dlopen`s the library and returns the raw `TSLanguage *`.
    public func languagePointer(for configuration: LanguageDefinition.TreeSitterConfiguration) throws -> OpaquePointer {
        lock.lock()
        defer { lock.unlock() }
        if let cached = languagePointers[configuration.grammar] { return cached }

        guard let libraryURL = locate(configuration.library) else {
            throw LoaderError.libraryNotFound(configuration.library)
        }
        guard let handle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            throw LoaderError.openFailed(configuration.library, String(cString: dlerror()))
        }
        let symbolName = "tree_sitter_\(configuration.grammar)"
        guard let symbol = dlsym(handle, symbolName) else {
            dlclose(handle)
            throw LoaderError.symbolNotFound(symbolName)
        }

        typealias LanguageFunction = @convention(c) () -> OpaquePointer
        let function = unsafeBitCast(symbol, to: LanguageFunction.self)
        let pointer = function()

        handles[configuration.grammar] = handle
        languagePointers[configuration.grammar] = pointer
        return pointer
    }

    public func queryText(for configuration: LanguageDefinition.TreeSitterConfiguration) throws -> String {
        guard let relativePath = configuration.highlightsQuery else {
            throw LoaderError.queryNotFound("(geen highlightsQuery in de taaldefinitie)")
        }
        guard let url = locate(relativePath) else {
            throw LoaderError.queryNotFound(relativePath)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Standard search paths for a running app.
    public static func standardSearchPaths(bundle: Bundle = .main,
                                           applicationSupport: URL? = nil) -> [URL] {
        var paths = [URL]()
        if let resources = bundle.resourceURL {
            paths.append(resources.appendingPathComponent("Grammars", isDirectory: true))
        }
        if let applicationSupport {
            paths.append(applicationSupport.appendingPathComponent("Grammars", isDirectory: true))
        }
        return paths
    }
}
