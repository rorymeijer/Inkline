import Foundation

/// Persists named macros as one JSON file under Application Support, so they
/// survive restarts and can be shared by copying a file.
public final class MacroStore {

    public private(set) var macros: [Macro] = []
    public var onChange: (([Macro]) -> Void)?

    private let url: URL
    private let queue = DispatchQueue(label: "nl.rorymeijer.inkline.macro-store")

    public init(url: URL) {
        self.url = url
        load()
    }

    public convenience init(applicationSupportDirectory: URL) {
        self.init(url: applicationSupportDirectory.appendingPathComponent("Macros.json"))
    }

    public func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        macros = (try? decoder.decode([Macro].self, from: data)) ?? []
        onChange?(macros)
    }

    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(macros)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    public func add(_ macro: Macro) {
        macros.append(macro)
        persist()
    }

    public func update(_ macro: Macro) {
        guard let index = macros.firstIndex(where: { $0.id == macro.id }) else { return }
        macros[index] = macro
        persist()
    }

    public func remove(id: UUID) {
        macros.removeAll { $0.id == id }
        persist()
    }

    public func macro(named name: String) -> Macro? {
        macros.first { $0.name == name }
    }

    public func macro(id: UUID) -> Macro? {
        macros.first { $0.id == id }
    }

    private func persist() {
        onChange?(macros)
        queue.async { [macros, url] in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(macros) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic])
        }
    }
}
