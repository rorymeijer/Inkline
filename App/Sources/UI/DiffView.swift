import AppKit
import SwiftUI
import InklineCore

/// Side-by-side compare of two files or two open tabs.
@MainActor
final class DiffModel: ObservableObject {
    @Published var leftTitle = ""
    @Published var rightTitle = ""
    @Published var result: DiffResult?
    @Published var options = DiffOptions()
    @Published var errorMessage: String?

    private var leftText = ""
    private var rightText = ""

    func compare(leftTitle: String, leftText: String, rightTitle: String, rightText: String) {
        self.leftTitle = leftTitle
        self.rightTitle = rightTitle
        self.leftText = leftText
        self.rightText = rightText
        recompute()
    }

    func compare(leftURL: URL, rightURL: URL) {
        do {
            let left = try FileLoader.load(contentsOf: leftURL)
            let right = try FileLoader.load(contentsOf: rightURL)
            compare(leftTitle: leftURL.lastPathComponent, leftText: left.text,
                    rightTitle: rightURL.lastPathComponent, rightText: right.text)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recompute() {
        result = DiffEngine.compare(leftText, rightText, options: options)
    }
}

struct DiffView: View {

    @ObservedObject var model: DiffModel
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.leftTitle).frame(maxWidth: .infinity, alignment: .leading)
                Text(model.rightTitle).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.headline)
            .padding(8)

            HStack(spacing: 12) {
                Toggle(NSLocalizedString("Negeer hoofdletters", comment: "Diff-optie"),
                       isOn: $model.options.ignoresCase)
                Toggle(NSLocalizedString("Negeer witruimte", comment: "Diff-optie"),
                       isOn: $model.options.ignoresWhitespace)
                Spacer()
                if let result = model.result {
                    Text(String(format: NSLocalizedString("+%d  −%d", comment: "Diff-telling"),
                                result.insertions, result.deletions))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 8)
            .onChange(of: model.options) { _ in model.recompute() }

            Divider()

            if let result = model.result {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                            DiffRowView(row: row, style: environment.style)
                        }
                    }
                }
            } else if let message = model.errorMessage {
                Text(message).foregroundStyle(.red).padding()
            } else {
                Text(NSLocalizedString("Kies twee bestanden om te vergelijken.", comment: "Lege diff"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 420)
    }
}

private struct DiffRowView: View {
    let row: DiffRow
    let style: ThemeStyle

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(row.leftLine.map { "\($0 + 1)" } ?? "")
                .frame(width: 44, alignment: .trailing)
            Text(row.rightLine.map { "\($0 + 1)" } ?? "")
                .frame(width: 44, alignment: .trailing)
            Text(marker)
                .frame(width: 12)
            Text(row.text.isEmpty ? " " : row.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(Color(nsColor: style.foregroundColor))
        .padding(.vertical, 1)
        .padding(.horizontal, 6)
        .background(background)
    }

    private var marker: String {
        switch row.operation {
        case .equal: return " "
        case .insert: return "+"
        case .delete: return "−"
        }
    }

    private var background: Color {
        switch row.operation {
        case .equal: return .clear
        case .insert: return Color(nsColor: style.diffInsertedColor)
        case .delete: return Color(nsColor: style.diffDeletedColor)
        }
    }
}
