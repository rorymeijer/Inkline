import AppKit
import SwiftUI
import InklineCore
import InklineSyntax

/// Preferences, split the way people look for them: text, editing, saving,
/// appearance and updates.
struct SettingsView: View {

    @ObservedObject var environment: AppEnvironment

    var body: some View {
        TabView {
            EditorSettingsTab(environment: environment)
                .tabItem { Label(NSLocalizedString("Editor", comment: "Instellingentab"), systemImage: "text.cursor") }
            AppearanceSettingsTab(environment: environment)
                .tabItem { Label(NSLocalizedString("Weergave", comment: "Instellingentab"), systemImage: "paintpalette") }
            SavingSettingsTab(environment: environment)
                .tabItem { Label(NSLocalizedString("Bewaren", comment: "Instellingentab"), systemImage: "externaldrive") }
            UpdateSettingsTab(environment: environment)
                .tabItem { Label(NSLocalizedString("Updates", comment: "Instellingentab"), systemImage: "arrow.down.circle") }
        }
        .frame(width: 520, height: 400)
    }
}

private struct EditorSettingsTab: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        Form {
            Section {
                Stepper(value: binding(\.fontSize), in: 8...48, step: 1) {
                    Text(String(format: NSLocalizedString("Lettergrootte: %.0f pt", comment: "Instelling"),
                                environment.settings.fontSize))
                }
                Button(NSLocalizedString("Lettertype kiezen…", comment: "Knop")) {
                    NSFontManager.shared.orderFrontFontPanel(nil)
                }
                Toggle(NSLocalizedString("Regelnummers tonen", comment: "Instelling"), isOn: binding(\.showsLineNumbers))
                Toggle(NSLocalizedString("Inspringhulplijnen tonen", comment: "Instelling"), isOn: binding(\.showsIndentGuides))
                Toggle(NSLocalizedString("Huidige regel markeren", comment: "Instelling"), isOn: binding(\.highlightsCurrentLine))
                Toggle(NSLocalizedString("Regels afbreken", comment: "Instelling"), isOn: binding(\.wrapsLines))
                Toggle(NSLocalizedString("Vouwbalk tonen", comment: "Instelling"), isOn: binding(\.showsFoldingRibbon))
            }
            Section {
                Toggle(NSLocalizedString("Automatisch inspringen", comment: "Instelling"), isOn: binding(\.autoIndents))
                Toggle(NSLocalizedString("Haakjes automatisch sluiten", comment: "Instelling"), isOn: binding(\.autoClosesBrackets))
                Toggle(NSLocalizedString("Aanhalingstekens automatisch sluiten", comment: "Instelling"), isOn: binding(\.autoClosesQuotes))
                Toggle(NSLocalizedString("Bijbehorend haakje markeren", comment: "Instelling"), isOn: binding(\.highlightsMatchingBracket))
                Toggle(NSLocalizedString("Woordaanvulling", comment: "Instelling"), isOn: binding(\.completionEnabled))
            }
            Section {
                Toggle(NSLocalizedString("Tabs gebruiken in plaats van spaties", comment: "Instelling"),
                       isOn: Binding(get: { environment.settings.indentation.usesTabs },
                                     set: { newValue in
                                         var settings = environment.settings
                                         settings.indentation.usesTabs = newValue
                                         environment.settingsStore.settings = settings
                                     }))
                Stepper(value: Binding(get: { environment.settings.indentation.indentWidth },
                                       set: { newValue in
                                           var settings = environment.settings
                                           settings.indentation = IndentationSettings(usesTabs: settings.indentation.usesTabs,
                                                                                      indentWidth: newValue,
                                                                                      tabWidth: newValue)
                                           environment.settingsStore.settings = settings
                                       }), in: 1...16) {
                    Text(String(format: NSLocalizedString("Inspringbreedte: %d", comment: "Instelling"),
                                environment.settings.indentation.indentWidth))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<EditorSettings, Value>) -> Binding<Value> {
        Binding(get: { environment.settings[keyPath: keyPath] },
                set: { newValue in
                    var settings = environment.settings
                    settings[keyPath: keyPath] = newValue
                    environment.settingsStore.settings = settings
                })
    }
}

private struct AppearanceSettingsTab: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        Form {
            Toggle(NSLocalizedString("Systeemuiterlijk volgen", comment: "Instelling"),
                   isOn: Binding(get: { environment.settings.followsSystemAppearance },
                                 set: { newValue in
                                     var settings = environment.settings
                                     settings.followsSystemAppearance = newValue
                                     environment.settingsStore.settings = settings
                                 }))
            Picker(NSLocalizedString("Licht thema", comment: "Instelling"),
                   selection: Binding(get: { environment.settings.lightThemeIdentifier },
                                      set: { environment.selectTheme(identifier: $0) })) {
                ForEach(environment.themeRegistry.themes(for: .light)) { theme in
                    Text(theme.name).tag(theme.identifier)
                }
            }
            Picker(NSLocalizedString("Donker thema", comment: "Instelling"),
                   selection: Binding(get: { environment.settings.darkThemeIdentifier },
                                      set: { environment.selectTheme(identifier: $0) })) {
                ForEach(environment.themeRegistry.themes(for: .dark)) { theme in
                    Text(theme.name).tag(theme.identifier)
                }
            }
            Button(NSLocalizedString("Map met thema’s tonen", comment: "Knop")) {
                NSWorkspace.shared.open(environment.userThemesDirectory)
            }
            Button(NSLocalizedString("Map met taaldefinities tonen", comment: "Knop")) {
                NSWorkspace.shared.open(environment.userLanguagesDirectory)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SavingSettingsTab: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        Form {
            Toggle(NSLocalizedString("Witruimte aan regeleinden verwijderen bij bewaren", comment: "Instelling"),
                   isOn: Binding(get: { environment.settings.saveOptions.trimTrailingWhitespace },
                                 set: { newValue in
                                     var settings = environment.settings
                                     settings.saveOptions.trimTrailingWhitespace = newValue
                                     environment.settingsStore.settings = settings
                                 }))
            Toggle(NSLocalizedString("Afsluiten met een lege regel", comment: "Instelling"),
                   isOn: Binding(get: { environment.settings.saveOptions.ensureTrailingNewline },
                                 set: { newValue in
                                     var settings = environment.settings
                                     settings.saveOptions.ensureTrailingNewline = newValue
                                     environment.settingsStore.settings = settings
                                 }))
            Toggle(NSLocalizedString("Sessie herstellen bij starten", comment: "Instelling"),
                   isOn: Binding(get: { environment.settings.restoresSessionOnLaunch },
                                 set: { newValue in
                                     var settings = environment.settings
                                     settings.restoresSessionOnLaunch = newValue
                                     environment.settingsStore.settings = settings
                                 }))
            Picker(NSLocalizedString("Standaardcodering", comment: "Instelling"),
                   selection: Binding(get: { environment.settings.defaultEncoding },
                                      set: { newValue in
                                          var settings = environment.settings
                                          settings.defaultEncoding = newValue
                                          environment.settingsStore.settings = settings
                                      })) {
                ForEach(TextEncoding.menuOrder, id: \.self) { encoding in
                    Text(encoding.displayName).tag(encoding)
                }
            }
            Picker(NSLocalizedString("Standaard regeleinde", comment: "Instelling"),
                   selection: Binding(get: { environment.settings.defaultLineEnding },
                                      set: { newValue in
                                          var settings = environment.settings
                                          settings.defaultLineEnding = newValue
                                          environment.settingsStore.settings = settings
                                      })) {
                ForEach(LineEnding.allCases, id: \.self) { ending in
                    Text(ending.longDisplayName).tag(ending)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdateSettingsTab: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        Form {
            Toggle(NSLocalizedString("Automatisch op updates controleren", comment: "Instelling"),
                   isOn: Binding(get: { environment.settings.checksForUpdatesAutomatically },
                                 set: { newValue in
                                     var settings = environment.settings
                                     settings.checksForUpdatesAutomatically = newValue
                                     environment.settingsStore.settings = settings
                                     environment.updater.automaticallyChecksForUpdates = newValue
                                 }))
            Toggle(NSLocalizedString("Updates automatisch downloaden", comment: "Instelling"),
                   isOn: Binding(get: { environment.settings.downloadsUpdatesAutomatically },
                                 set: { newValue in
                                     var settings = environment.settings
                                     settings.downloadsUpdatesAutomatically = newValue
                                     environment.updater.automaticallyDownloadsUpdates = newValue
                                 }))
            Button(NSLocalizedString("Nu op updates controleren…", comment: "Knop")) {
                environment.updater.checkForUpdates()
            }
            .disabled(!environment.updater.canCheckForUpdates)
            Text(environment.updater.statusDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

/// About: the tagline, the version and where everything lives on disk.
struct AboutView: View {
    @ObservedObject var environment: AppEnvironment

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Inkline").font(.largeTitle.bold())
            Text("Elke taal. Elk bestand. Meteen open.").font(.title3)
            Text("Licht, snel, uitbreidbaar.").foregroundStyle(.secondary)
            Text(String(format: NSLocalizedString("Versie %@", comment: "Over-venster"), version))
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider().padding(.vertical, 4)
            Button(NSLocalizedString("Toon ondersteuningsmap", comment: "Knop")) {
                NSWorkspace.shared.open(environment.supportDirectory)
            }
            Text("© Rory Meijer")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 360)
    }
}
