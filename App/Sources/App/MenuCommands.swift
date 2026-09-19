import AppKit
import SwiftUI
import InklineCore
import InklineSyntax

/// The menu bar. Standard shortcuts everywhere they exist on macOS; the rest
/// follows the Notepad++ muscle memory where it does not clash (⌘L for "ga naar
/// regel", ⌘D for dupliceren, F3-achtige ⌘G voor volgende treffer).
struct InklineCommands: Commands {

    @ObservedObject var environment: AppEnvironment

    private var workspace: WorkspaceModel? { environment.activeWorkspace }

    var body: some Commands {
        // MARK: File
        CommandGroup(replacing: .newItem) {
            Button(NSLocalizedString("Nieuw bestand", comment: "Menu")) { workspace?.newDocument() }
                .keyboardShortcut("n")
            Button(NSLocalizedString("Openen…", comment: "Menu")) { workspace?.openPanel() }
                .keyboardShortcut("o")
            Button(NSLocalizedString("Map openen…", comment: "Menu")) { workspace?.openFolderPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button(NSLocalizedString("Bewaren", comment: "Menu")) { workspace?.save() }
                .keyboardShortcut("s")
            Button(NSLocalizedString("Bewaren als…", comment: "Menu")) { workspace?.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button(NSLocalizedString("Alles bewaren", comment: "Menu")) { workspace?.saveAll() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Divider()
            Button(NSLocalizedString("Terug naar bewaarde versie", comment: "Menu")) {
                workspace?.revertActiveDocument()
            }
            Divider()
            Button(NSLocalizedString("Tabblad sluiten", comment: "Menu")) { workspace?.closeActiveDocument() }
                .keyboardShortcut("w")
            Button(NSLocalizedString("Andere tabbladen sluiten", comment: "Menu")) {
                workspace?.closeOtherDocuments()
            }
            Divider()
            sessionMenu
        }

        // MARK: Edit
        CommandGroup(after: .pasteItem) {
            Divider()
            Button(NSLocalizedString("Regel of selectie dupliceren", comment: "Menu")) {
                workspace?.duplicateSelection()
            }
            .keyboardShortcut("d")
            Button(NSLocalizedString("Regel verwijderen", comment: "Menu")) { workspace?.deleteCurrentLine() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button(NSLocalizedString("Regel omhoog", comment: "Menu")) { workspace?.moveLines(up: true) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .control])
            Button(NSLocalizedString("Regel omlaag", comment: "Menu")) { workspace?.moveLines(up: false) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .control])

            Divider()

            Menu(NSLocalizedString("Hoofdlettergebruik", comment: "Menu")) {
                Button(NSLocalizedString("HOOFDLETTERS", comment: "Menu")) { workspace?.uppercaseSelection() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Button(NSLocalizedString("kleine letters", comment: "Menu")) { workspace?.lowercaseSelection() }
                    .keyboardShortcut("u", modifiers: [.command, .option])
                Button(NSLocalizedString("Begin Hoofdletters", comment: "Menu")) { workspace?.titleCaseSelection() }
                Button(NSLocalizedString("Zinshoofdletters", comment: "Menu")) { workspace?.sentenceCaseSelection() }
                Button(NSLocalizedString("Omkeren", comment: "Menu")) { workspace?.invertCaseSelection() }
            }

            Menu(NSLocalizedString("Regelbewerkingen", comment: "Menu")) {
                Button(NSLocalizedString("Sorteren (oplopend)", comment: "Menu")) { workspace?.sortLines(ascending: true) }
                Button(NSLocalizedString("Sorteren (aflopend)", comment: "Menu")) { workspace?.sortLines(ascending: false) }
                Button(NSLocalizedString("Sorteren (numeriek)", comment: "Menu")) {
                    workspace?.sortLines(ascending: true, numeric: true)
                }
                Divider()
                Button(NSLocalizedString("Volgorde omkeren", comment: "Menu")) { workspace?.reverseLines() }
                Button(NSLocalizedString("Dubbele regels verwijderen", comment: "Menu")) { workspace?.removeDuplicateLines() }
                Button(NSLocalizedString("Lege regels verwijderen", comment: "Menu")) { workspace?.removeEmptyLines() }
                Button(NSLocalizedString("Witruimte aan regeleinden verwijderen", comment: "Menu")) {
                    workspace?.trimTrailingWhitespace()
                }
                Divider()
                Button(NSLocalizedString("Regels samenvoegen", comment: "Menu")) { workspace?.joinLines() }
                Button(NSLocalizedString("Regels afbreken op kolom 80", comment: "Menu")) {
                    workspace?.splitLines(at: 80)
                }
            }

            Menu(NSLocalizedString("Converteren", comment: "Menu")) {
                Button("Base64 →") { workspace?.base64EncodeSelection() }
                Button("Base64 ←") { workspace?.base64DecodeSelection() }
                Divider()
                Button("URL →") { workspace?.urlEncodeSelection() }
                Button("URL ←") { workspace?.urlDecodeSelection() }
                Divider()
                Button("HTML →") { workspace?.htmlEncodeSelection() }
                Button("HTML ←") { workspace?.htmlDecodeSelection() }
                Divider()
                Button(NSLocalizedString("Tabs naar spaties", comment: "Menu")) { workspace?.convertTabsToSpaces() }
                Button(NSLocalizedString("Spaties naar tabs", comment: "Menu")) { workspace?.convertSpacesToTabs() }
            }

            Menu(NSLocalizedString("Kolomeditor", comment: "Menu")) {
                Button(NSLocalizedString("Tekst invoegen…", comment: "Menu")) { promptForColumnText() }
                Button(NSLocalizedString("Getallenreeks invoegen…", comment: "Menu")) { promptForColumnNumbers() }
            }

            Divider()

            Button(NSLocalizedString("Inspringen", comment: "Menu")) { workspace?.indentSelection() }
                .keyboardShortcut("]")
            Button(NSLocalizedString("Uitspringen", comment: "Menu")) { workspace?.outdentSelection() }
                .keyboardShortcut("[")
            Button(NSLocalizedString("Commentaar aan/uit", comment: "Menu")) { workspace?.toggleLineComment() }
                .keyboardShortcut("/")
            Button(NSLocalizedString("Blokcommentaar aan/uit", comment: "Menu")) { workspace?.toggleBlockComment() }
                .keyboardShortcut("/", modifiers: [.command, .option])
        }

        // MARK: Search
        CommandMenu(NSLocalizedString("Zoeken", comment: "Menutitel")) {
            Button(NSLocalizedString("Zoeken…", comment: "Menu")) { workspace?.find.show() }
                .keyboardShortcut("f")
            Button(NSLocalizedString("Zoeken en vervangen…", comment: "Menu")) { workspace?.find.show(replacing: true) }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button(NSLocalizedString("Volgende", comment: "Menu")) { workspace?.find.findNext() }
                .keyboardShortcut("g")
            Button(NSLocalizedString("Vorige", comment: "Menu")) { workspace?.find.findNext(direction: .backward) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button(NSLocalizedString("Zoek naar selectie", comment: "Menu")) { workspace?.find.useSelectionForFind() }
                .keyboardShortcut("e")
            Divider()
            Button(NSLocalizedString("Zoeken in bestanden…", comment: "Menu")) {
                workspace?.visibleSidebarPanel = .searchResults
                workspace?.isSidebarVisible = true
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Button(NSLocalizedString("Ga naar regel…", comment: "Menu")) { promptForLineNumber() }
                .keyboardShortcut("l")
            Button(NSLocalizedString("Ga naar bijbehorend haakje", comment: "Menu")) { workspace?.goToMatchingBracket() }
                .keyboardShortcut("b", modifiers: [.command, .control])
            Divider()
            Button(NSLocalizedString("Bladwijzer aan/uit", comment: "Menu")) { workspace?.toggleBookmarkOnCurrentLine() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button(NSLocalizedString("Volgende bladwijzer", comment: "Menu")) { workspace?.goToNextBookmark() }
                .keyboardShortcut("m", modifiers: [.command, .option])
            Button(NSLocalizedString("Alle bladwijzers wissen", comment: "Menu")) { workspace?.clearBookmarks() }
        }

        // MARK: View
        CommandGroup(after: .toolbar) {
            Button(NSLocalizedString("Zijbalk tonen/verbergen", comment: "Menu")) {
                workspace?.isSidebarVisible.toggle()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
            Button(NSLocalizedString("Splitsen naast elkaar", comment: "Menu")) {
                workspace?.splitPane(orientation: .horizontal)
            }
            .keyboardShortcut("\\", modifiers: [.command, .option])
            Button(NSLocalizedString("Splitsen onder elkaar", comment: "Menu")) {
                workspace?.splitPane(orientation: .vertical)
            }
            Button(NSLocalizedString("Splitsing opheffen", comment: "Menu")) { workspace?.closeSplit() }
            Toggle(NSLocalizedString("Gesynchroniseerd scrollen", comment: "Menu"),
                   isOn: Binding(get: { workspace?.synchronizedScrolling ?? false },
                                 set: { workspace?.synchronizedScrolling = $0 }))
            Button(NSLocalizedString("Document naar andere paneel", comment: "Menu")) {
                workspace?.moveActiveDocumentToOtherPane()
            }
            Divider()
            Button(NSLocalizedString("Vergroten", comment: "Menu")) { environment.adjustFontSize(by: 1) }
                .keyboardShortcut("+")
            Button(NSLocalizedString("Verkleinen", comment: "Menu")) { environment.adjustFontSize(by: -1) }
                .keyboardShortcut("-")
            Button(NSLocalizedString("Werkelijke grootte", comment: "Menu")) { environment.resetFontSize() }
                .keyboardShortcut("0")
            Divider()
            Toggle(NSLocalizedString("Regels afbreken", comment: "Menu"),
                   isOn: settingBinding(\.wrapsLines))
            Toggle(NSLocalizedString("Regelnummers", comment: "Menu"),
                   isOn: settingBinding(\.showsLineNumbers))
            Toggle(NSLocalizedString("Inspringhulplijnen", comment: "Menu"),
                   isOn: settingBinding(\.showsIndentGuides))
            Divider()
            Button(NSLocalizedString("Alles invouwen", comment: "Menu")) { collapseAll() }
            Button(NSLocalizedString("Alles uitvouwen", comment: "Menu")) { expandAll() }
            Divider()
            Button(NSLocalizedString("Vergelijken met bestand…", comment: "Menu")) {
                workspace?.compareActiveDocumentWithFile()
            }
        }

        // MARK: Encoding, language, macros, plugins
        CommandMenu(NSLocalizedString("Codering", comment: "Menutitel")) {
            Menu(NSLocalizedString("Converteren naar", comment: "Menu")) {
                ForEach(TextEncoding.menuOrder, id: \.self) { encoding in
                    Button(encoding.displayName) { workspace?.setEncoding(encoding, reinterpret: false) }
                }
            }
            Menu(NSLocalizedString("Opnieuw openen met", comment: "Menu")) {
                ForEach(TextEncoding.menuOrder, id: \.self) { encoding in
                    Button(encoding.displayName) { workspace?.setEncoding(encoding, reinterpret: true) }
                }
            }
            Divider()
            ForEach(LineEnding.allCases, id: \.self) { ending in
                Button(ending.longDisplayName) { workspace?.setLineEnding(ending) }
            }
        }

        CommandMenu(NSLocalizedString("Taal", comment: "Menutitel")) {
            ForEach(environment.languageRegistry.groupedByInitial()) { group in
                Menu(group.id) {
                    ForEach(group.languages) { language in
                        Button(language.name) { workspace?.setLanguage(language) }
                    }
                }
            }
            Divider()
            Button(NSLocalizedString("Map met taaldefinities tonen", comment: "Menu")) {
                NSWorkspace.shared.open(environment.userLanguagesDirectory)
            }
        }

        CommandMenu(NSLocalizedString("Macro", comment: "Menutitel")) {
            Button(environment.isRecordingMacro
                   ? NSLocalizedString("Opname stoppen", comment: "Menu")
                   : NSLocalizedString("Opname starten", comment: "Menu")) {
                if environment.isRecordingMacro {
                    workspace?.stopMacroRecording()
                } else {
                    workspace?.startMacroRecording()
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Button(NSLocalizedString("Laatste macro afspelen", comment: "Menu")) { workspace?.playLastMacro() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button(NSLocalizedString("Afspelen tot einde bestand", comment: "Menu")) {
                workspace?.playLastMacro(repeatMode: .untilEndOfDocument)
            }
            Divider()
            ForEach(environment.macroStore.macros) { macro in
                Button(macro.name) { workspace?.playMacro(macro) }
            }
            Divider()
            Button(NSLocalizedString("Macro's beheren…", comment: "Menu")) { showMacroManager() }
        }

        CommandMenu(NSLocalizedString("Plugins", comment: "Menutitel")) {
            ForEach(environment.pluginHost.menuItems, id: \.commandIdentifier) { item in
                Button(item.title) {
                    let context = CommandContext(document: workspace?.activeDocument?.document)
                    try? environment.commandRegistry.perform(CommandIdentifier(item.commandIdentifier),
                                                             context: context)
                }
            }
            Divider()
            Button(NSLocalizedString("Plugins beheren…", comment: "Menu")) { showPluginManager() }
            Button(NSLocalizedString("Map met plugins tonen", comment: "Menu")) {
                NSWorkspace.shared.open(environment.userPluginsDirectory)
            }
        }

        // MARK: Help / app menu
        CommandGroup(replacing: .appInfo) {
            Button(NSLocalizedString("Over Inkline", comment: "Menu")) { showAbout() }
        }
        CommandGroup(after: .appInfo) {
            Button(NSLocalizedString("Zoeken naar updates…", comment: "Menu")) {
                environment.updater.checkForUpdates()
            }
            .disabled(!environment.updater.canCheckForUpdates)
        }
    }

    // MARK: Helpers

    private var sessionMenu: some View {
        Menu(NSLocalizedString("Sessies", comment: "Menu")) {
            Button(NSLocalizedString("Sessie bewaren…", comment: "Menu")) { promptForSessionName() }
            ForEach(environment.sessionStore.availableSessionNames(), id: \.self) { name in
                Button(name) { workspace?.loadNamedSession(name) }
            }
        }
    }

    private func settingBinding(_ keyPath: WritableKeyPath<EditorSettings, Bool>) -> Binding<Bool> {
        Binding(get: { environment.settings[keyPath: keyPath] },
                set: { newValue in
                    var settings = environment.settings
                    settings[keyPath: keyPath] = newValue
                    environment.settingsStore.settings = settings
                })
    }

    private func collapseAll() {
        workspace?.activeDocument?.collapseAllFolds()
    }

    private func expandAll() {
        workspace?.activeDocument?.expandAllFolds()
    }

    private func promptForLineNumber() {
        guard let answer = TextPrompt.run(title: NSLocalizedString("Ga naar regel", comment: "Venstertitel"),
                                          message: NSLocalizedString("Regelnummer:", comment: "Label"),
                                          defaultValue: ""),
              let line = Int(answer), line > 0 else { return }
        workspace?.goToLine(line - 1)
    }

    private func promptForSessionName() {
        guard let name = TextPrompt.run(title: NSLocalizedString("Sessie bewaren", comment: "Venstertitel"),
                                        message: NSLocalizedString("Naam van de sessie:", comment: "Label"),
                                        defaultValue: ""), !name.isEmpty else { return }
        workspace?.saveNamedSession(name)
    }

    private func promptForColumnText() {
        guard let text = TextPrompt.run(title: NSLocalizedString("Kolomeditor", comment: "Venstertitel"),
                                        message: NSLocalizedString("Tekst om in te voegen:", comment: "Label"),
                                        defaultValue: "") else { return }
        workspace?.insertColumnText(text)
    }

    private func promptForColumnNumbers() {
        guard let startText = TextPrompt.run(title: NSLocalizedString("Getallenreeks", comment: "Venstertitel"),
                                             message: NSLocalizedString("Beginwaarde:", comment: "Label"),
                                             defaultValue: "1"),
              let start = Int(startText),
              let stepText = TextPrompt.run(title: NSLocalizedString("Getallenreeks", comment: "Venstertitel"),
                                            message: NSLocalizedString("Stapgrootte:", comment: "Label"),
                                            defaultValue: "1"),
              let step = Int(stepText) else { return }
        workspace?.insertColumnNumbers(start: start, increment: step, format: .decimal, minimumDigits: 1)
    }

    private func showMacroManager() {
        guard let workspace else { return }
        AuxiliaryWindow.show(identifier: "macros",
                             title: NSLocalizedString("Macro's", comment: "Venstertitel"),
                             size: NSSize(width: 640, height: 420)) {
            MacroManagerView(environment: environment, workspace: workspace)
        }
    }

    private func showPluginManager() {
        AuxiliaryWindow.show(identifier: "plugins",
                             title: NSLocalizedString("Plugins", comment: "Venstertitel"),
                             size: NSSize(width: 700, height: 440)) {
            PluginManagerView(environment: environment)
        }
    }

    private func showAbout() {
        AuxiliaryWindow.show(identifier: "about",
                             title: NSLocalizedString("Over Inkline", comment: "Venstertitel"),
                             size: NSSize(width: 360, height: 420)) {
            AboutView(environment: environment)
        }
    }
}

/// A one-field prompt. `NSAlert` with an accessory text field is the shortest
/// path to a modal question on macOS, and it inherits VoiceOver support.
@MainActor
enum TextPrompt {
    static func run(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Knop"))
        alert.addButton(withTitle: NSLocalizedString("Annuleer", comment: "Knop"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}
