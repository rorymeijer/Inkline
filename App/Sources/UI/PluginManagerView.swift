import AppKit
import SwiftUI
import InklinePluginAPI

/// The plugin manager: what is installed, what is on, and why something failed.
struct PluginManagerView: View {

    @ObservedObject var environment: AppEnvironment
    @State private var selection: String?

    var body: some View {
        HSplitView {
            List(environment.pluginDescriptors, selection: $selection) { descriptor in
                HStack {
                    Toggle("", isOn: Binding(
                        get: { descriptor.isEnabled },
                        set: { newValue in
                            do {
                                try environment.pluginManager.setEnabled(newValue,
                                                                         identifier: descriptor.manifest.identifier)
                            } catch {
                                environment.lastMessage = error.localizedDescription
                            }
                        }))
                    .labelsHidden()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(descriptor.manifest.name)
                        Text(descriptor.manifest.identifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if descriptor.loadError != nil {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                .tag(descriptor.manifest.identifier)
            }
            .frame(minWidth: 260)

            detail
                .frame(minWidth: 300)
        }
        .frame(minWidth: 640, minHeight: 380)
        .toolbar {
            ToolbarItem {
                Button {
                    environment.pluginManager.discover()
                } label: {
                    Label(NSLocalizedString("Vernieuwen", comment: "Knop"), systemImage: "arrow.clockwise")
                }
            }
            ToolbarItem {
                Button {
                    installPlugin()
                } label: {
                    Label(NSLocalizedString("Installeren…", comment: "Knop"), systemImage: "plus")
                }
            }
            ToolbarItem {
                Button {
                    NSWorkspace.shared.open(environment.userPluginsDirectory)
                } label: {
                    Label(NSLocalizedString("Map tonen", comment: "Knop"), systemImage: "folder")
                }
            }
        }
        .onAppear { environment.pluginManager.discover() }
    }

    @ViewBuilder
    private var detail: some View {
        if let identifier = selection,
           let descriptor = environment.pluginDescriptors.first(where: { $0.manifest.identifier == identifier }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(descriptor.manifest.name).font(.title2)
                    if let summary = descriptor.manifest.summary {
                        Text(summary)
                    }
                    LabeledContent(NSLocalizedString("Versie", comment: "Plugininfo"),
                                   value: descriptor.manifest.version)
                    LabeledContent(NSLocalizedString("Auteur", comment: "Plugininfo"),
                                   value: descriptor.manifest.author ?? "—")
                    LabeledContent(NSLocalizedString("API-versie", comment: "Plugininfo"),
                                   value: descriptor.manifest.apiVersion.description)
                    LabeledContent(NSLocalizedString("Status", comment: "Plugininfo"),
                                   value: descriptor.isLoaded
                                       ? NSLocalizedString("Geladen", comment: "Pluginstatus")
                                       : NSLocalizedString("Niet geladen", comment: "Pluginstatus"))
                    if !descriptor.manifest.capabilities.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Rechten", comment: "Plugininfo")).font(.headline)
                            ForEach(descriptor.manifest.capabilities, id: \.self) { capability in
                                Label(capability.rawValue, systemImage: "checkmark.seal")
                                    .font(.caption)
                            }
                        }
                    }
                    if let error = descriptor.loadError {
                        Text(error).foregroundStyle(.red).font(.callout)
                    }
                    Text(descriptor.url.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(NSLocalizedString("Kies een plugin", comment: "Lege pluginbeheerder"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func installPlugin() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = []
        panel.message = NSLocalizedString("Kies een .inklineplugin-bundel", comment: "Bericht in het open-venster")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let descriptor = try environment.pluginManager.install(from: url,
                                                                   into: environment.userPluginsDirectory)
            try environment.pluginManager.setEnabled(true, identifier: descriptor.manifest.identifier)
        } catch {
            environment.lastMessage = error.localizedDescription
        }
    }
}
