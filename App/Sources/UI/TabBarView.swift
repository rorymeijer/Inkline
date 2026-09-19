import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The tab strip: reorderable, closable, with the unsaved-changes dot that
/// turns into a close button on hover — the macOS convention.
struct TabBarView: View {

    @ObservedObject var pane: EditorPane
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var environment: AppEnvironment
    @State private var draggedDocumentID: UUID?

    /// Moves the dragged tab in front of `target`. Returns whether the drop was
    /// handled, which is what SwiftUI wants back.
    private func move(_ dragged: UUID?, before target: UUID) -> Bool {
        guard let dragged, dragged != target,
              let from = pane.documentIDs.firstIndex(of: dragged),
              let to = pane.documentIDs.firstIndex(of: target) else { return false }
        workspace.moveTab(in: pane, from: IndexSet(integer: from), to: to > from ? to + 1 : to)
        draggedDocumentID = nil
        return true
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(workspace.documents(in: pane)) { document in
                    TabItemView(document: document,
                                isActive: pane.activeDocumentID == document.id,
                                onSelect: {
                                    pane.activeDocumentID = document.id
                                    workspace.activePaneID = pane.id
                                },
                                onClose: { workspace.closeDocument(id: document.id) })
                        // Slepen om tabbladen te herordenen.
                        .onDrag {
                            draggedDocumentID = document.id
                            return NSItemProvider(object: document.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], isTargeted: nil) { _ in
                            move(draggedDocumentID, before: document.id)
                        }
                        .contextMenu {
                            Button(NSLocalizedString("Sluiten", comment: "Tabmenu")) {
                                workspace.closeDocument(id: document.id)
                            }
                            Button(NSLocalizedString("Andere sluiten", comment: "Tabmenu")) {
                                pane.activeDocumentID = document.id
                                workspace.closeOtherDocuments()
                            }
                            Divider()
                            Button(NSLocalizedString("Toon in Finder", comment: "Tabmenu")) {
                                guard let url = document.fileURL else { return }
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            .disabled(document.fileURL == nil)
                            Button(NSLocalizedString("Kopieer pad", comment: "Tabmenu")) {
                                guard let url = document.fileURL else { return }
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url.path, forType: .string)
                            }
                            .disabled(document.fileURL == nil)
                        }
                }
                Button {
                    workspace.newDocument()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("Nieuw tabblad", comment: "Tooltip"))
                Spacer(minLength: 0)
            }
        }
        .frame(height: 30)
        .background(Color(nsColor: environment.style.gutterBackgroundColor))
    }
}

private struct TabItemView: View {

    @ObservedObject var document: EditorDocument
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onClose) {
                Image(systemName: isHovering ? "xmark.circle.fill" : (document.isDirty ? "circle.fill" : "xmark"))
                    .font(.system(size: document.isDirty && !isHovering ? 7 : 9))
                    .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                    .opacity(document.isDirty || isHovering ? 1 : 0)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString("Tabblad sluiten", comment: "VoiceOver")))

            Text(document.displayName)
                .lineLimit(1)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(isActive ? Color.primary.opacity(0.08) : Color.clear)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .help(document.fileURL?.path ?? document.displayName)
        .accessibilityLabel(Text(document.displayName))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
