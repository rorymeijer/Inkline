import AppKit
import SwiftUI
import InklineCore
import InklineSyntax

/// Line/column, selection size, language, encoding, line ending, file size and
/// INS/OVR — each one a control, not just a label, because that is where people
/// look for those settings.
struct StatusBarView: View {

    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var environment: AppEnvironment
    @State private var goToLineText = ""
    @State private var showsGoToLine = false

    private var document: EditorDocument? { workspace.activeDocument }

    var body: some View {
        HStack(spacing: 12) {
            positionLabel
            Divider().frame(height: 14)
            selectionLabel
            Spacer()
            if environment.isRecordingMacro {
                Label(NSLocalizedString("Macro-opname", comment: "Statusbalk"), systemImage: "record.circle")
                    .foregroundStyle(.red)
                    .font(.system(size: 11))
            }
            fileSizeLabel
            languageMenu
            encodingMenu
            lineEndingMenu
            indentationMenu
            overwriteLabel
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(Color(nsColor: environment.style.gutterBackgroundColor))
        .popover(isPresented: $showsGoToLine) {
            goToLinePopover
        }
    }

    // MARK: Pieces

    private var positionLabel: some View {
        Button {
            showsGoToLine = true
        } label: {
            if let document {
                let position = document.position(at: document.selection.head)
                Text(String(format: NSLocalizedString("Rg %d, Kol %d", comment: "Statusbalk: regel en kolom"),
                            position.line + 1, position.column + 1))
            } else {
                Text("—")
            }
        }
        .buttonStyle(.plain)
        .help(NSLocalizedString("Ga naar regel…", comment: "Tooltip"))
    }

    private var selectionLabel: some View {
        Group {
            if let document {
                let statistics = document.document.statistics()
                if statistics.selectedCharacters > 0 {
                    Text(String(format: NSLocalizedString("%d tekens, %d regels geselecteerd",
                                                          comment: "Statusbalk: selectie"),
                                statistics.selectedCharacters, statistics.selectedLines))
                } else if document.selectedRangeCount > 1 {
                    Text(String(format: NSLocalizedString("%d cursors", comment: "Statusbalk: multi-cursor"),
                                document.selectedRangeCount))
                } else {
                    Text(String(format: NSLocalizedString("%d tekens, %d regels", comment: "Statusbalk: document"),
                                statistics.characters, statistics.lines))
                }
            } else {
                Text("")
            }
        }
        .foregroundStyle(.secondary)
    }

    private var fileSizeLabel: some View {
        Group {
            if let bytes = document?.document.byteCountOnDisk {
                Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(environment.languageRegistry.groupedByInitial(), id: \.0) { group in
                Menu(group.0) {
                    ForEach(group.1) { language in
                        Button(language.name) { workspace.setLanguage(language) }
                    }
                }
            }
        } label: {
            Text(document?.language.name ?? "—")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(NSLocalizedString("Taal voor syntaxkleuring", comment: "Tooltip"))
    }

    private var encodingMenu: some View {
        Menu {
            Section(NSLocalizedString("Converteren naar", comment: "Menukop")) {
                ForEach(TextEncoding.menuOrder, id: \.self) { encoding in
                    Button(encoding.displayName) { workspace.setEncoding(encoding, reinterpret: false) }
                }
            }
            Section(NSLocalizedString("Opnieuw openen met", comment: "Menukop")) {
                ForEach(TextEncoding.menuOrder, id: \.self) { encoding in
                    Button(encoding.displayName) { workspace.setEncoding(encoding, reinterpret: true) }
                }
            }
        } label: {
            Text(document?.document.encoding.displayName ?? "—")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(NSLocalizedString("Tekencodering", comment: "Tooltip"))
    }

    private var lineEndingMenu: some View {
        Menu {
            ForEach(LineEnding.allCases, id: \.self) { ending in
                Button(ending.longDisplayName) { workspace.setLineEnding(ending) }
            }
        } label: {
            Text(document?.document.lineEnding.displayName ?? "—")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(NSLocalizedString("Regeleindes", comment: "Tooltip"))
    }

    private var indentationMenu: some View {
        Menu {
            Button(NSLocalizedString("Tabs gebruiken", comment: "Inspringmenu")) {
                guard let current = document?.document.indentation else { return }
                workspace.setIndentation(IndentationSettings(usesTabs: true,
                                                             indentWidth: current.indentWidth,
                                                             tabWidth: current.tabWidth))
            }
            Button(NSLocalizedString("Spaties gebruiken", comment: "Inspringmenu")) {
                guard let current = document?.document.indentation else { return }
                workspace.setIndentation(IndentationSettings(usesTabs: false,
                                                             indentWidth: current.indentWidth,
                                                             tabWidth: current.tabWidth))
            }
            Divider()
            ForEach([2, 3, 4, 8], id: \.self) { width in
                Button(String(format: NSLocalizedString("Breedte %d", comment: "Inspringmenu"), width)) {
                    guard let current = document?.document.indentation else { return }
                    workspace.setIndentation(IndentationSettings(usesTabs: current.usesTabs,
                                                                 indentWidth: width,
                                                                 tabWidth: width))
                }
            }
        } label: {
            if let indentation = document?.document.indentation {
                Text(indentation.usesTabs
                     ? String(format: NSLocalizedString("Tabs %d", comment: "Statusbalk"), indentation.tabWidth)
                     : String(format: NSLocalizedString("Spaties %d", comment: "Statusbalk"), indentation.indentWidth))
            } else {
                Text("—")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var overwriteLabel: some View {
        Button {
            guard let document else { return }
            document.isOverwriteMode.toggle()
        } label: {
            Text(document?.isOverwriteMode == true ? "OVR" : "INS")
                .foregroundStyle(document?.isOverwriteMode == true ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(NSLocalizedString("Invoegen of overschrijven", comment: "Tooltip"))
    }

    private var goToLinePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Ga naar regel", comment: "Titel van het ga-naar-regel-venster"))
                .font(.headline)
            TextField(NSLocalizedString("Regelnummer", comment: "Invoerveld"), text: $goToLineText)
                .frame(width: 160)
                .onSubmit(performGoToLine)
            HStack {
                Spacer()
                Button(NSLocalizedString("Ga", comment: "Knop"), action: performGoToLine)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    private func performGoToLine() {
        guard let line = Int(goToLineText), line > 0 else { return }
        workspace.goToLine(line - 1)
        showsGoToLine = false
    }
}
