import AppKit
import InklineCore
import InklineSyntax

/// Registers Inkline's own commands in the shared `CommandRegistry`.
///
/// Menus, macros (`MacroAction.command`) and plugins all resolve commands
/// through this registry, so a keyboard shortcut, a recorded macro and a plugin
/// calling the same identifier take exactly the same code path.
@MainActor
enum BuiltInCommands {

    static func register(in environment: AppEnvironment) {
        let registry = environment.commandRegistry

        func command(_ identifier: String,
                     _ title: String,
                     _ category: CommandCategory,
                     _ body: @escaping (WorkspaceModel) -> Void) -> EditorCommand {
            EditorCommand(id: CommandIdentifier(identifier),
                          title: title,
                          category: category,
                          isEnabled: { _ in environment.activeWorkspace?.activeDocument != nil },
                          handler: { _ in
                              guard let workspace = environment.activeWorkspace else { return }
                              body(workspace)
                          })
        }

        registry.register(contentsOf: [
            // File
            command("nl.rorymeijer.inkline.file.save",
                    NSLocalizedString("Bewaren", comment: "Commando"), .file) { $0.save() },
            command("nl.rorymeijer.inkline.file.saveAll",
                    NSLocalizedString("Alles bewaren", comment: "Commando"), .file) { $0.saveAll() },
            command("nl.rorymeijer.inkline.file.revert",
                    NSLocalizedString("Terug naar bewaarde versie", comment: "Commando"), .file) { $0.revertActiveDocument() },

            // Case
            command("nl.rorymeijer.inkline.edit.uppercase",
                    NSLocalizedString("Hoofdletters", comment: "Commando"), .edit) { $0.uppercaseSelection() },
            command("nl.rorymeijer.inkline.edit.lowercase",
                    NSLocalizedString("Kleine letters", comment: "Commando"), .edit) { $0.lowercaseSelection() },
            command("nl.rorymeijer.inkline.edit.titlecase",
                    NSLocalizedString("Begin Hoofdletters", comment: "Commando"), .edit) { $0.titleCaseSelection() },
            command("nl.rorymeijer.inkline.edit.sentencecase",
                    NSLocalizedString("Zinshoofdletters", comment: "Commando"), .edit) { $0.sentenceCaseSelection() },
            command("nl.rorymeijer.inkline.edit.invertcase",
                    NSLocalizedString("Hoofdlettergebruik omkeren", comment: "Commando"), .edit) { $0.invertCaseSelection() },

            // Lines
            command("nl.rorymeijer.inkline.edit.sortAscending",
                    NSLocalizedString("Regels sorteren (oplopend)", comment: "Commando"), .edit) { $0.sortLines(ascending: true) },
            command("nl.rorymeijer.inkline.edit.sortDescending",
                    NSLocalizedString("Regels sorteren (aflopend)", comment: "Commando"), .edit) { $0.sortLines(ascending: false) },
            command("nl.rorymeijer.inkline.edit.sortNumeric",
                    NSLocalizedString("Regels sorteren (numeriek)", comment: "Commando"), .edit) { $0.sortLines(ascending: true, numeric: true) },
            command("nl.rorymeijer.inkline.edit.reverseLines",
                    NSLocalizedString("Regelvolgorde omkeren", comment: "Commando"), .edit) { $0.reverseLines() },
            command("nl.rorymeijer.inkline.edit.removeDuplicates",
                    NSLocalizedString("Dubbele regels verwijderen", comment: "Commando"), .edit) { $0.removeDuplicateLines() },
            command("nl.rorymeijer.inkline.edit.removeEmptyLines",
                    NSLocalizedString("Lege regels verwijderen", comment: "Commando"), .edit) { $0.removeEmptyLines() },
            command("nl.rorymeijer.inkline.edit.trimTrailing",
                    NSLocalizedString("Witruimte aan regeleinden verwijderen", comment: "Commando"), .edit) { $0.trimTrailingWhitespace() },
            command("nl.rorymeijer.inkline.edit.joinLines",
                    NSLocalizedString("Regels samenvoegen", comment: "Commando"), .edit) { $0.joinLines() },
            command("nl.rorymeijer.inkline.edit.duplicate",
                    NSLocalizedString("Regel of selectie dupliceren", comment: "Commando"), .edit) { $0.duplicateSelection() },
            command("nl.rorymeijer.inkline.edit.deleteLine",
                    NSLocalizedString("Regel verwijderen", comment: "Commando"), .edit) { $0.deleteCurrentLine() },
            command("nl.rorymeijer.inkline.edit.moveLineUp",
                    NSLocalizedString("Regel omhoog verplaatsen", comment: "Commando"), .edit) { $0.moveLines(up: true) },
            command("nl.rorymeijer.inkline.edit.moveLineDown",
                    NSLocalizedString("Regel omlaag verplaatsen", comment: "Commando"), .edit) { $0.moveLines(up: false) },

            // Encoding helpers
            command("nl.rorymeijer.inkline.edit.base64Encode",
                    NSLocalizedString("Base64 coderen", comment: "Commando"), .edit) { $0.base64EncodeSelection() },
            command("nl.rorymeijer.inkline.edit.base64Decode",
                    NSLocalizedString("Base64 decoderen", comment: "Commando"), .edit) { $0.base64DecodeSelection() },
            command("nl.rorymeijer.inkline.edit.urlEncode",
                    NSLocalizedString("URL coderen", comment: "Commando"), .edit) { $0.urlEncodeSelection() },
            command("nl.rorymeijer.inkline.edit.urlDecode",
                    NSLocalizedString("URL decoderen", comment: "Commando"), .edit) { $0.urlDecodeSelection() },
            command("nl.rorymeijer.inkline.edit.htmlEncode",
                    NSLocalizedString("HTML coderen", comment: "Commando"), .edit) { $0.htmlEncodeSelection() },
            command("nl.rorymeijer.inkline.edit.htmlDecode",
                    NSLocalizedString("HTML decoderen", comment: "Commando"), .edit) { $0.htmlDecodeSelection() },

            // Indentation
            command("nl.rorymeijer.inkline.edit.indent",
                    NSLocalizedString("Inspringen", comment: "Commando"), .edit) { $0.indentSelection() },
            command("nl.rorymeijer.inkline.edit.outdent",
                    NSLocalizedString("Uitspringen", comment: "Commando"), .edit) { $0.outdentSelection() },
            command("nl.rorymeijer.inkline.edit.tabsToSpaces",
                    NSLocalizedString("Tabs naar spaties", comment: "Commando"), .edit) { $0.convertTabsToSpaces() },
            command("nl.rorymeijer.inkline.edit.spacesToTabs",
                    NSLocalizedString("Spaties naar tabs", comment: "Commando"), .edit) { $0.convertSpacesToTabs() },
            command("nl.rorymeijer.inkline.edit.toggleLineComment",
                    NSLocalizedString("Regelcommentaar aan/uit", comment: "Commando"), .edit) { $0.toggleLineComment() },
            command("nl.rorymeijer.inkline.edit.toggleBlockComment",
                    NSLocalizedString("Blokcommentaar aan/uit", comment: "Commando"), .edit) { $0.toggleBlockComment() },

            // Search & navigation
            command("nl.rorymeijer.inkline.search.find",
                    NSLocalizedString("Zoeken…", comment: "Commando"), .search) { $0.find.show() },
            command("nl.rorymeijer.inkline.search.replace",
                    NSLocalizedString("Zoeken en vervangen…", comment: "Commando"), .search) { $0.find.show(replacing: true) },
            command("nl.rorymeijer.inkline.search.findNext",
                    NSLocalizedString("Volgende zoeken", comment: "Commando"), .search) { $0.find.findNext() },
            command("nl.rorymeijer.inkline.search.findPrevious",
                    NSLocalizedString("Vorige zoeken", comment: "Commando"), .search) { $0.find.findNext(direction: .backward) },
            command("nl.rorymeijer.inkline.search.toggleBookmark",
                    NSLocalizedString("Bladwijzer aan/uit", comment: "Commando"), .search) { $0.toggleBookmarkOnCurrentLine() },
            command("nl.rorymeijer.inkline.search.nextBookmark",
                    NSLocalizedString("Volgende bladwijzer", comment: "Commando"), .search) { $0.goToNextBookmark() },
            command("nl.rorymeijer.inkline.search.previousBookmark",
                    NSLocalizedString("Vorige bladwijzer", comment: "Commando"), .search) { $0.goToNextBookmark(forward: false) },
            command("nl.rorymeijer.inkline.search.matchingBracket",
                    NSLocalizedString("Ga naar bijbehorend haakje", comment: "Commando"), .search) { $0.goToMatchingBracket() }
        ])
    }
}
