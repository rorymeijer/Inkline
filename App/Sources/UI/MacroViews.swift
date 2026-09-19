import AppKit
import SwiftUI
import InklineCore

/// Macro manager: the recorded steps, names, shortcuts and playback options.
struct MacroManagerView: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject var workspace: WorkspaceModel
    @State private var selection: UUID?
    @State private var repeatCount = 1
    @State private var macros: [Macro] = []

    var body: some View {
        HSplitView {
            List(macros, selection: $selection) { macro in
                VStack(alignment: .leading, spacing: 2) {
                    Text(macro.name)
                    Text(String(format: NSLocalizedString("%d stappen", comment: "Macro-info"),
                                macro.actions.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(macro.id)
            }
            .frame(minWidth: 220)

            detail.frame(minWidth: 320)
        }
        .frame(minWidth: 620, minHeight: 360)
        .onAppear { macros = environment.macroStore.macros }
        .onReceive(NotificationCenter.default.publisher(for: .inklineMacrosChanged)) { _ in
            macros = environment.macroStore.macros
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let macro = macros.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 10) {
                TextField(NSLocalizedString("Naam", comment: "Invoerveld"),
                          text: Binding(get: { macro.name },
                                        set: { newValue in
                                            var updated = macro
                                            updated.name = newValue
                                            environment.macroStore.update(updated)
                                            macros = environment.macroStore.macros
                                        }))
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text(NSLocalizedString("Sneltoets", comment: "Label"))
                    TextField("⌘⌃…", text: Binding(get: { macro.keyEquivalent ?? "" },
                                                   set: { newValue in
                                                       var updated = macro
                                                       updated.keyEquivalent = newValue.isEmpty ? nil : String(newValue.prefix(1))
                                                       updated.modifierDescription = "cmd,ctrl"
                                                       environment.macroStore.update(updated)
                                                       macros = environment.macroStore.macros
                                                   }))
                        .frame(width: 60)
                    Text(NSLocalizedString("(met ⌘⌃)", comment: "Toelichting bij sneltoets"))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Divider()

                Text(NSLocalizedString("Stappen", comment: "Kop")).font(.headline)
                List(macro.actions.indices, id: \.self) { index in
                    HStack {
                        Text("\(index + 1).").foregroundStyle(.tertiary).frame(width: 24, alignment: .trailing)
                        Text(macro.actions[index].displayDescription).font(.system(size: 11))
                    }
                }
                .frame(minHeight: 140)

                HStack {
                    Stepper(value: $repeatCount, in: 1...9999) {
                        Text(String(format: NSLocalizedString("%d× afspelen", comment: "Macro herhalen"),
                                    repeatCount))
                    }
                    Spacer()
                    Button(NSLocalizedString("Tot einde bestand", comment: "Knop")) {
                        workspace.playMacro(macro, repeatMode: .untilEndOfDocument)
                    }
                    Button(NSLocalizedString("Afspelen", comment: "Knop")) {
                        workspace.playMacro(macro, repeatMode: .times(repeatCount))
                    }
                    .keyboardShortcut(.defaultAction)
                }

                Button(role: .destructive) {
                    environment.macroStore.remove(id: macro.id)
                    macros = environment.macroStore.macros
                    selection = nil
                } label: {
                    Label(NSLocalizedString("Verwijderen", comment: "Knop"), systemImage: "trash")
                }
            }
            .padding()
        } else {
            Text(NSLocalizedString("Kies een macro", comment: "Lege macrobeheerder"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension Notification.Name {
    static let inklineMacrosChanged = Notification.Name("nl.rorymeijer.inkline.macrosChanged")
}
