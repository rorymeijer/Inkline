import AppKit
import SwiftUI
import InklineCore
import InklinePluginAPI
import InklineSyntax

/// The docking sidebar: file explorer, function list, search results and the
/// panels plugins contribute, selected with a segmented control at the top.
struct SidebarView: View {

    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: Binding(
                get: { workspace.visibleSidebarPanel ?? .explorer },
                set: { workspace.visibleSidebarPanel = $0 }
            )) {
                ForEach(SidebarPanel.allCases) { panel in
                    Image(systemName: panel.symbolName)
                        .help(panel.title)
                        .tag(panel)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(6)

            Divider()

            switch workspace.visibleSidebarPanel ?? .explorer {
            case .explorer:
                FileExplorerPanel(workspace: workspace)
            case .symbols:
                SymbolListPanel(workspace: workspace)
            case .searchResults:
                FindInFilesPanel(model: workspace.findInFiles, workspace: workspace)
            case .plugins:
                PluginPanelHost(environment: environment)
            }
        }
        .background(.regularMaterial)
    }
}

// MARK: - File explorer

/// A lazily loaded directory tree. Children are read when a folder is expanded,
/// so opening a repository with 100 000 files costs nothing until you look.
final class FileNode: Identifiable, ObservableObject {
    let url: URL
    let isDirectory: Bool
    @Published var children: [FileNode]?

    init(url: URL) {
        self.url = url
        self.isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    func loadChildrenIfNeeded(includingHidden: Bool = false) {
        guard isDirectory, children == nil else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: includingHidden ? [] : [.skipsHiddenFiles])) ?? []
        children = contents
            .map(FileNode.init)
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}

struct FileExplorerPanel: View {

    @ObservedObject var workspace: WorkspaceModel
    @State private var roots: [FileNode] = []

    var body: some View {
        VStack(spacing: 0) {
            if workspace.explorerRoots.isEmpty {
                VStack(spacing: 8) {
                    Text(NSLocalizedString("Geen map geopend", comment: "Lege bestandsverkenner"))
                        .foregroundStyle(.secondary)
                    Button(NSLocalizedString("Map openen…", comment: "Knop")) {
                        workspace.openFolderPanel()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(roots) { root in
                        FileNodeRow(node: root, workspace: workspace)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .onAppear(perform: refreshRoots)
        .onChange(of: workspace.explorerRoots) { _ in refreshRoots() }
    }

    private func refreshRoots() {
        roots = workspace.explorerRoots.map(FileNode.init)
        for root in roots { root.loadChildrenIfNeeded() }
    }
}

struct FileNodeRow: View {

    @ObservedObject var node: FileNode
    @ObservedObject var workspace: WorkspaceModel
    @State private var isExpanded = false

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(node.children ?? []) { child in
                    FileNodeRow(node: child, workspace: workspace)
                }
            } label: {
                Label(node.name, systemImage: "folder")
                    .lineLimit(1)
            }
            .onChange(of: isExpanded) { expanded in
                if expanded { node.loadChildrenIfNeeded() }
            }
            .contextMenu {
                Button(NSLocalizedString("Zoek in deze map…", comment: "Contextmenu")) {
                    workspace.findInFiles.searchRoot = node.url
                    workspace.visibleSidebarPanel = .searchResults
                }
                Button(NSLocalizedString("Toon in Finder", comment: "Contextmenu")) {
                    NSWorkspace.shared.activateFileViewerSelecting([node.url])
                }
                Button(NSLocalizedString("Verwijder uit zijbalk", comment: "Contextmenu")) {
                    workspace.removeExplorerRoot(node.url)
                }
            }
        } else {
            Label(node.name, systemImage: "doc.text")
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { workspace.open(url: node.url) }
                .contextMenu {
                    Button(NSLocalizedString("Openen", comment: "Contextmenu")) {
                        workspace.open(url: node.url)
                    }
                    Button(NSLocalizedString("Toon in Finder", comment: "Contextmenu")) {
                        NSWorkspace.shared.activateFileViewerSelecting([node.url])
                    }
                }
        }
    }
}

// MARK: - Function list

struct SymbolListPanel: View {

    @ObservedObject var workspace: WorkspaceModel
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField(NSLocalizedString("Filter", comment: "Invoerveld"), text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(6)
            Divider()
            if let document = workspace.activeDocument {
                let symbols = document.symbols.filter {
                    filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter)
                }
                if symbols.isEmpty {
                    Text(NSLocalizedString("Geen symbolen gevonden", comment: "Lege functielijst"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(symbols) { symbol in
                        HStack(spacing: 6) {
                            Image(systemName: symbol.kind.symbolName)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(symbol.name).lineLimit(1)
                            Spacer()
                            Text("\(symbol.line + 1)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.leading, CGFloat(min(symbol.indentationLevel, 12)) * 4)
                        .contentShape(Rectangle())
                        .onTapGesture { workspace.goToLine(symbol.line) }
                    }
                    .listStyle(.inset)
                }
            } else {
                Spacer()
            }
        }
    }
}

// MARK: - Search results

struct FindInFilesPanel: View {

    @ObservedObject var model: FindInFilesModel
    @ObservedObject var workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                TextField(NSLocalizedString("Zoeken in bestanden", comment: "Invoerveld"),
                          text: $model.query.pattern)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.start() }
                HStack {
                    Text(model.searchRoot?.lastPathComponent
                         ?? NSLocalizedString("Geen map", comment: "Zoeken in bestanden"))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(NSLocalizedString("Map…", comment: "Knop")) {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK { model.searchRoot = panel.url }
                    }
                }
                HStack {
                    TextField(NSLocalizedString("Filters, bv. *.swift", comment: "Invoerveld"),
                              text: $model.includePatterns)
                        .textFieldStyle(.roundedBorder)
                    Button(model.isSearching
                           ? NSLocalizedString("Stop", comment: "Knop")
                           : NSLocalizedString("Zoek", comment: "Knop")) {
                        model.isSearching ? model.cancel() : model.start()
                    }
                }
                HStack(spacing: 8) {
                    Toggle(NSLocalizedString("Aa", comment: "Hoofdlettergevoelig"),
                           isOn: $model.query.isCaseSensitive)
                    Toggle(NSLocalizedString(".*", comment: "Reguliere expressie"),
                           isOn: $model.query.isRegularExpression)
                    Spacer()
                }
                .toggleStyle(.checkbox)
                .font(.caption)
            }
            .padding(8)

            Divider()

            if !model.summaryText.isEmpty {
                Text(model.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }

            List {
                ForEach(model.hitsByFile, id: \.url) { group in
                    Section(group.url.lastPathComponent) {
                        ForEach(group.hits) { hit in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(hit.line + 1)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                Text(hit.lineText.trimmingCharacters(in: .whitespaces))
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { model.open(hit) }
                            .help(group.url.path)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - Plugin panels

/// Hosts the `NSView`s that plugins contribute, one tab per panel.
struct PluginPanelHost: View {

    @ObservedObject var environment: AppEnvironment
    @State private var selection: String?

    var body: some View {
        let panels = environment.pluginHost.panels
        VStack(spacing: 0) {
            if panels.isEmpty {
                Text(NSLocalizedString("Geen plugin-panelen actief", comment: "Leeg pluginpaneel"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Picker("", selection: Binding(get: { selection ?? panels[0].identifier },
                                              set: { selection = $0 })) {
                    ForEach(panels, id: \.identifier) { panel in
                        Text(panel.title).tag(panel.identifier)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(6)
                Divider()
                if let panel = panels.first(where: { $0.identifier == (selection ?? panels[0].identifier) }) {
                    PluginPanelContainer(descriptor: panel)
                        .id(panel.identifier)
                }
            }
        }
    }
}

struct PluginPanelContainer: NSViewRepresentable {
    let descriptor: PluginPanelDescriptor

    func makeNSView(context: Context) -> NSView {
        descriptor.makeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
