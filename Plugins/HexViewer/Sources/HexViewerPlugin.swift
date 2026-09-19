import AppKit
import Foundation
import InklineCore
import InklinePluginAPI

/// Example plugin #2 — a docking panel.
///
/// Shows how a plugin contributes an `NSView` to the sidebar and keeps it in
/// step with the active document. Everything the panel needs comes from the
/// host; the plugin never reaches into the editor.
@objc(HexViewerPlugin)
public final class HexViewerPlugin: NSObject, InklinePlugin {

    public static let manifest = PluginManifest(
        identifier: "nl.rorymeijer.inkline.plugin.hexviewer",
        name: "Hex-weergave",
        version: "1.0",
        author: "Inkline",
        summary: "Toont de bytes van het actieve document of van een bestand op schijf.",
        capabilities: [.readFiles, .contributePanel, .contributeMenu])

    private weak var host: PluginHost?
    private var panel: HexPanelView?

    public override required init() {
        super.init()
    }

    public func activate(host: PluginHost) throws {
        self.host = host

        host.register(panel: PluginPanelDescriptor(identifier: "hexviewer.panel",
                                                   title: "Hex",
                                                   symbolName: "number.square",
                                                   placement: .rightSidebar,
                                                   preferredSize: 360) { [weak self] in
            let view = HexPanelView()
            self?.panel = view
            self?.refresh()
            return view
        })

        host.register(command: PluginCommand(identifier: "hexviewer.show",
                                             title: "Hex-weergave tonen") { [weak self] invocation in
            invocation.host.showPanel(identifier: "hexviewer.panel")
            self?.refresh()
        })

        host.register(command: PluginCommand(identifier: "hexviewer.openFile",
                                             title: "Bestand in hex openen…") { [weak self] invocation in
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = true
            openPanel.canChooseDirectories = false
            guard openPanel.runModal() == .OK, let url = openPanel.url else { return }
            guard let data = try? Data(contentsOf: url) else {
                invocation.host.showMessage("Kon \(url.lastPathComponent) niet lezen.", style: .error)
                return
            }
            invocation.host.showPanel(identifier: "hexviewer.panel")
            self?.panel?.show(data: data, title: url.lastPathComponent)
        })

        host.register(menuItem: PluginMenuItem(title: "Hex-weergave tonen",
                                                commandIdentifier: "hexviewer.show"))
        host.register(menuItem: PluginMenuItem(title: "Bestand in hex openen…",
                                                commandIdentifier: "hexviewer.openFile"))
    }

    public func deactivate() {
        panel = nil
    }

    private func refresh() {
        guard let panel, let document = host?.activeDocument else { return }
        panel.show(data: Data(document.text.utf8), title: document.displayName)
    }
}

/// The panel itself: a monospaced hex dump with an ASCII column.
final class HexPanelView: NSView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let scrollView = NSScrollView()

    /// Bytes beyond this are not rendered; a hex dump of a 100 MB file helps
    /// nobody and would freeze the panel.
    static let byteLimit = 1 << 20

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: .greatestFiniteMagnitude,
                                                       height: .greatestFiniteMagnitude)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func show(data: Data, title: String) {
        let truncated = data.count > Self.byteLimit
        let slice = truncated ? data.prefix(Self.byteLimit) : data
        titleLabel.stringValue = truncated
            ? "\(title) — eerste \(Self.byteLimit) van \(data.count) bytes"
            : "\(title) — \(data.count) bytes"
        textView.string = HexPanelView.dump(slice)
    }

    /// `offset  00 11 22 …  |ascii|`, sixteen bytes per line.
    static func dump(_ data: some Collection<UInt8>) -> String {
        var output = ""
        var offset = 0
        var iterator = Array(data).makeIterator()
        var row = [UInt8]()

        func flush() {
            guard !row.isEmpty else { return }
            let hex = row.map { String(format: "%02X", $0) }.joined(separator: " ")
            let padding = String(repeating: " ", count: max(0, (16 - row.count) * 3))
            let ascii = row.map { byte -> String in
                (byte >= 32 && byte < 127) ? String(UnicodeScalar(byte)) : "."
            }.joined()
            output += String(format: "%08X  %@%@  |%@|\n", offset, hex, padding, ascii)
            offset += row.count
            row.removeAll(keepingCapacity: true)
        }

        while let byte = iterator.next() {
            row.append(byte)
            if row.count == 16 { flush() }
        }
        flush()
        return output
    }
}
