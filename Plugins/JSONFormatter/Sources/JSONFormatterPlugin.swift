import AppKit
import Foundation
import InklineCore
import InklinePluginAPI

/// Example plugin #1 — pure text commands.
///
/// Shows the smallest useful shape of a plugin: register a few commands in
/// `activate(host:)`, edit the active document through `PluginDocument`, and
/// let the host worry about menus, shortcuts, undo and macros.
@objc(JSONFormatterPlugin)
public final class JSONFormatterPlugin: NSObject, InklinePlugin {

    public static let manifest = PluginManifest(
        identifier: "nl.rorymeijer.inkline.plugin.jsonformatter",
        name: "JSON-formatter",
        version: "1.0",
        author: "Inkline",
        summary: "Netjes maken, comprimeren, sorteren en controleren van JSON.",
        capabilities: [.editText, .contributeMenu])

    public override required init() {
        super.init()
    }

    public func activate(host: PluginHost) throws {
        host.register(command: PluginCommand(identifier: "jsonformatter.pretty",
                                             title: "JSON netjes maken",
                                             keyEquivalent: "j",
                                             modifierDescription: "cmd,ctrl") { invocation in
            try Self.transform(invocation) { try Self.format($0, pretty: true, sortKeys: false) }
        })

        host.register(command: PluginCommand(identifier: "jsonformatter.minify",
                                             title: "JSON comprimeren") { invocation in
            try Self.transform(invocation) { try Self.format($0, pretty: false, sortKeys: false) }
        })

        host.register(command: PluginCommand(identifier: "jsonformatter.sortKeys",
                                             title: "JSON netjes maken en sleutels sorteren") { invocation in
            try Self.transform(invocation) { try Self.format($0, pretty: true, sortKeys: true) }
        })

        host.register(command: PluginCommand(identifier: "jsonformatter.validate",
                                             title: "JSON controleren") { invocation in
            guard let document = invocation.document else { throw PluginError.noActiveDocument }
            let text = document.selectedRange.isEmpty ? document.text : document.selectedText
            do {
                _ = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
                invocation.host.showMessage("JSON is geldig.", style: .informational)
            } catch {
                invocation.host.showMessage("Ongeldige JSON: \(error.localizedDescription)", style: .error)
            }
        })

        for (identifier, title) in [("jsonformatter.pretty", "JSON netjes maken"),
                                    ("jsonformatter.minify", "JSON comprimeren"),
                                    ("jsonformatter.sortKeys", "JSON sorteren"),
                                    ("jsonformatter.validate", "JSON controleren")] {
            host.register(menuItem: PluginMenuItem(title: title, commandIdentifier: identifier))
        }
    }

    // MARK: Implementation

    private static func transform(_ invocation: PluginInvocation,
                                  _ body: (String) throws -> String) throws {
        guard let document = invocation.document else { throw PluginError.noActiveDocument }
        let range = document.selectedRange.isEmpty ? 0..<document.length : document.selectedRange
        let input = document.string(in: range)
        do {
            let output = try body(input)
            guard output != input else { return }
            document.performGrouped {
                document.replace(range: range, with: output)
            }
        } catch {
            invocation.host.showMessage("Kon de JSON niet verwerken: \(error.localizedDescription)",
                                        style: .warning)
        }
    }

    static func format(_ text: String, pretty: Bool, sortKeys: Bool) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let object = try JSONSerialization.jsonObject(with: Data(trimmed.utf8),
                                                      options: [.fragmentsAllowed])
        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }
        if sortKeys { options.insert(.sortedKeys) }
        let data = try JSONSerialization.data(withJSONObject: object, options: options)
        guard let output = String(data: data, encoding: .utf8) else {
            throw PluginError.activationFailed("Kon het resultaat niet als tekst lezen.")
        }
        // Foundation indents with two spaces and no trailing newline; match what
        // the editor's own "netjes maken" produces elsewhere.
        return pretty ? output + "\n" : output
    }
}
