import AppKit
import Foundation
import InklineCore
import InklinePluginAPI

/// Example plugin #3 — commands that do real text surgery.
///
/// Column tools: align on a separator, insert a numbered series, and cut a
/// single column out of delimited text. It leans on `InklineCore`'s
/// `ColumnEditor` and `PieceTable`, which plugins are welcome to use — the core
/// is part of the published API surface.
@objc(ColumnToolsPlugin)
public final class ColumnToolsPlugin: NSObject, InklinePlugin {

    public static let manifest = PluginManifest(
        identifier: "nl.rorymeijer.inkline.plugin.columntools",
        name: "Kolomgereedschap",
        version: "1.0",
        author: "Inkline",
        summary: "Uitlijnen op een scheidingsteken, genummerde reeksen en kolommen knippen.",
        capabilities: [.editText, .contributeMenu])

    public override required init() {
        super.init()
    }

    public func activate(host: PluginHost) throws {
        host.register(command: PluginCommand(identifier: "columntools.align",
                                             title: "Uitlijnen op scheidingsteken…") { invocation in
            guard let separator = Self.prompt(title: "Uitlijnen",
                                              message: "Scheidingsteken:",
                                              defaultValue: "=") , !separator.isEmpty else { return }
            try Self.transformLines(invocation) { Self.align($0, on: separator) }
        })

        host.register(command: PluginCommand(identifier: "columntools.numbering",
                                             title: "Genummerde reeks invoegen…") { invocation in
            guard let startText = Self.prompt(title: "Genummerde reeks",
                                              message: "Beginwaarde:",
                                              defaultValue: "1"),
                  let start = Int(startText),
                  let stepText = Self.prompt(title: "Genummerde reeks",
                                             message: "Stapgrootte:",
                                             defaultValue: "1"),
                  let step = Int(stepText) else { return }
            try Self.transformLines(invocation) { text in
                var value = start
                let lines = TextTransforms.splitIntoLines(text).map { line -> String in
                    defer { value += step }
                    return "\(value)\t\(line)"
                }
                return lines.joined(separator: "\n") + (text.hasSuffix("\n") ? "\n" : "")
            }
        })

        host.register(command: PluginCommand(identifier: "columntools.extract",
                                             title: "Kolom knippen…") { invocation in
            guard let separator = Self.prompt(title: "Kolom knippen",
                                              message: "Scheidingsteken:",
                                              defaultValue: ","),
                  let columnText = Self.prompt(title: "Kolom knippen",
                                               message: "Kolomnummer (vanaf 1):",
                                               defaultValue: "1"),
                  let column = Int(columnText), column > 0 else { return }
            try Self.transformLines(invocation) { text in
                let lines = TextTransforms.splitIntoLines(text).map { line -> String in
                    let parts = line.components(separatedBy: separator)
                    return parts.indices.contains(column - 1) ? parts[column - 1] : ""
                }
                return lines.joined(separator: "\n") + (text.hasSuffix("\n") ? "\n" : "")
            }
        })

        for (identifier, title) in [("columntools.align", "Uitlijnen op scheidingsteken…"),
                                    ("columntools.numbering", "Genummerde reeks invoegen…"),
                                    ("columntools.extract", "Kolom knippen…")] {
            host.register(menuItem: PluginMenuItem(title: title, commandIdentifier: identifier))
        }
    }

    // MARK: Implementation

    /// Pads every line so the first occurrence of `separator` lands in the same
    /// column, which is what "align on =" means to everyone who asks for it.
    static func align(_ text: String, on separator: String) -> String {
        let lines = TextTransforms.splitIntoLines(text)
        let split = lines.map { line -> (String, String)? in
            guard let range = line.range(of: separator) else { return nil }
            return (String(line[line.startIndex..<range.lowerBound]),
                    String(line[range.lowerBound...]))
        }
        let width = split.compactMap { $0?.0.trimmingTrailingWhitespace().count }.max() ?? 0

        let aligned = zip(lines, split).map { line, parts -> String in
            guard let parts else { return line }
            let head = parts.0.trimmingTrailingWhitespace()
            let padding = String(repeating: " ", count: max(0, width - head.count))
            return head + padding + " " + parts.1
        }
        return aligned.joined(separator: "\n") + (text.hasSuffix("\n") ? "\n" : "")
    }

    private static func transformLines(_ invocation: PluginInvocation,
                                       _ body: (String) -> String) throws {
        guard let document = invocation.document else { throw PluginError.noActiveDocument }
        let selection = document.selectedRange
        let range: Range<Int>
        if selection.isEmpty {
            range = 0..<document.length
        } else {
            // Grow the selection to whole lines: column tools operate on rows.
            let firstLine = document.lineNumber(at: selection.lowerBound)
            let lastLine = document.lineNumber(at: max(selection.lowerBound, selection.upperBound - 1))
            let start = document.offsetOfLineStart(firstLine)
            let end = document.offsetOfLineStart(lastLine + 1)
            range = start..<(end > start ? end : document.length)
        }
        let input = document.string(in: range)
        let output = body(input)
        guard output != input else { return }
        document.performGrouped {
            document.replace(range: range, with: output)
        }
    }

    private static func prompt(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Annuleer")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = Substring(self)
        while let last = result.last, last == " " || last == "\t" { result = result.dropLast() }
        return String(result)
    }
}
