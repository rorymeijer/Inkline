import SwiftUI
import InklineCore

/// The find bar. Deliberately a bar and not a sheet: search is something you do
/// while reading the document, not instead of it.
struct FindBarView: View {

    @ObservedObject var find: FindModel
    @ObservedObject var workspace: WorkspaceModel
    @FocusState private var focusedField: Field?

    private enum Field { case search, replace }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                searchField
                navigationButtons
                optionToggles
                Spacer()
                matchLabel
                Button {
                    find.hide()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(Text(NSLocalizedString("Zoekbalk sluiten", comment: "VoiceOver")))
            }
            if find.showsReplaceField {
                HStack(spacing: 8) {
                    TextField(NSLocalizedString("Vervangen door", comment: "Invoerveld"), text: $find.replacement)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                        .focused($focusedField, equals: .replace)
                    Button(NSLocalizedString("Vervang", comment: "Knop")) { find.replaceCurrent() }
                    Button(NSLocalizedString("Alles vervangen", comment: "Knop")) { find.replaceAllInActiveDocument() }
                    Button(NSLocalizedString("In alle tabbladen", comment: "Knop")) { find.replaceAllInOpenDocuments() }
                    Spacer()
                }
            }
            if let message = find.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .onAppear { focusedField = .search }
    }

    private var searchField: some View {
        TextField(NSLocalizedString("Zoeken", comment: "Invoerveld"), text: $find.query.pattern)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 320)
            .focused($focusedField, equals: .search)
            .onChange(of: find.query.pattern) { _ in find.queryDidChange() }
            .onSubmit { find.findNext() }
    }

    private var navigationButtons: some View {
        HStack(spacing: 2) {
            Button {
                find.findNext(direction: .backward)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help(NSLocalizedString("Vorige treffer", comment: "Tooltip"))

            Button {
                find.findNext(direction: .forward)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help(NSLocalizedString("Volgende treffer", comment: "Tooltip"))

            Button {
                find.selectAllMatches()
            } label: {
                Image(systemName: "text.cursor")
            }
            .help(NSLocalizedString("Selecteer alle treffers", comment: "Tooltip"))
        }
    }

    private var optionToggles: some View {
        HStack(spacing: 4) {
            toggle("Aa", isOn: $find.query.isCaseSensitive,
                   help: NSLocalizedString("Hoofdlettergevoelig", comment: "Tooltip"))
            toggle("ab|", isOn: $find.query.matchesWholeWords,
                   help: NSLocalizedString("Heel woord", comment: "Tooltip"))
            toggle(".*", isOn: $find.query.isRegularExpression,
                   help: NSLocalizedString("Reguliere expressie", comment: "Tooltip"))
            toggle("\\n", isOn: $find.query.usesEscapeSequences,
                   help: NSLocalizedString("Escape-tekens (\\n, \\t)", comment: "Tooltip"))
            toggle("↻", isOn: $find.query.wrapsAround,
                   help: NSLocalizedString("Doorzoeken vanaf begin", comment: "Tooltip"))
        }
    }

    private func toggle(_ label: String, isOn: Binding<Bool>, help: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            find.queryDidChange()
        } label: {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(isOn.wrappedValue ? Color.accentColor.opacity(0.25) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(isOn.wrappedValue ? [.isSelected] : [])
    }

    private var matchLabel: some View {
        Group {
            if find.query.isEmpty {
                EmptyView()
            } else if find.matchCount == 0 {
                Text(NSLocalizedString("Geen treffers", comment: "Zoekstatus")).foregroundStyle(.secondary)
            } else if let index = find.currentMatchIndex {
                Text(String(format: NSLocalizedString("%d van %d", comment: "Zoekstatus"),
                            index + 1, find.matchCount))
                    .foregroundStyle(.secondary)
            } else {
                Text(String(format: NSLocalizedString("%d treffers", comment: "Zoekstatus"), find.matchCount))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
    }
}
