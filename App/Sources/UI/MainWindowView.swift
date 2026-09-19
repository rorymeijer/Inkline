import AppKit
import UniformTypeIdentifiers
import SwiftUI
import InklineCore
import InklineSyntax

/// The window: sidebar, one or two editor panes, the find bar and the status
/// bar. Everything else is a sheet or a separate window.
struct MainWindowView: View {

    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if workspace.isSidebarVisible {
                    SidebarView(workspace: workspace, environment: environment)
                        .frame(minWidth: 200, idealWidth: 260, maxWidth: 420)
                    Divider()
                }
                editorArea
            }
            Divider()
            StatusBarView(workspace: workspace, environment: environment)
        }
        .frame(minWidth: 780, minHeight: 480)
        .background(Color(nsColor: environment.style.backgroundColor))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .alert(item: $workspace.alert) { alert in
            Alert(title: Text(alert.title),
                  message: Text(alert.message),
                  dismissButton: .default(Text(NSLocalizedString("OK", comment: "Knop"))))
        }
    }

    private var editorArea: some View {
        VStack(spacing: 0) {
            if workspace.find.isVisible {
                FindBarView(find: workspace.find, workspace: workspace)
                Divider()
            }
            panes
        }
    }

    @ViewBuilder
    private var panes: some View {
        switch workspace.splitOrientation {
        case .none:
            paneView(workspace.panes[0])
        case .horizontal:
            HSplitView {
                ForEach(workspace.panes) { pane in
                    paneView(pane)
                }
            }
        case .vertical:
            VSplitView {
                ForEach(workspace.panes) { pane in
                    paneView(pane)
                }
            }
        }
    }

    private func paneView(_ pane: EditorPane) -> some View {
        PaneView(pane: pane, workspace: workspace, environment: environment)
            .onTapGesture { workspace.activePaneID = pane.id }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            handled = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                       isDirectory.boolValue {
                        workspace.addExplorerRoot(url)
                    } else {
                        workspace.open(url: url)
                    }
                }
            }
        }
        return handled
    }
}

/// One editor pane: its tab bar and the text view of the active tab.
struct PaneView: View {

    @ObservedObject var pane: EditorPane
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(pane: pane, workspace: workspace, environment: environment)
            Divider()
            if let id = pane.activeDocumentID, let document = workspace.document(id: id) {
                EditorView(document: document,
                           workspace: workspace,
                           environment: environment,
                           paneID: pane.id)
                    .id(document.id)
            } else {
                EmptyStateView(workspace: workspace)
            }
        }
        .overlay(alignment: .top) {
            if workspace.activePaneID == pane.id, workspace.panes.count > 1 {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
    }
}

/// What you see with no tabs open: the tagline and the three things people do
/// first.
struct EmptyStateView: View {

    @ObservedObject var workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Elke taal. Elk bestand. Meteen open.")
                .font(.title3)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(NSLocalizedString("Nieuw bestand", comment: "Knop in het lege venster")) {
                    workspace.newDocument()
                }
                Button(NSLocalizedString("Bestand openen…", comment: "Knop in het lege venster")) {
                    workspace.openPanel()
                }
                Button(NSLocalizedString("Map openen…", comment: "Knop in het lege venster")) {
                    workspace.openFolderPanel()
                }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
