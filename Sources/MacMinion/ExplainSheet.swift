import MacMinionKit
import SwiftUI

/// Explain Setting (S-075): what the addon's source says a saved key is, the values it takes, the lines
/// that use it, and on request a few sentences from AI. Nothing here sends a saved value.
struct ExplainSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: ExplainTarget

    var body: some View {
        let folder = model.gameFolder
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(.title2.bold())
                Text("\(model.addonName(target.file)) · \((target.parent + [target.key]).luaPath)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            if let explanation = folder.explanation {
                Form {
                    facts(explanation)
                    if !explanation.lines.isEmpty {
                        Section("Lines of the Addon's Source That Use It") {
                            Text(explanation.lines.joined(separator: "\n"))
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    aiSection(explanation)
                }
                .formStyle(.grouped)
                .fitsContent(max: 520)
            } else {
                ProgressView("Reading the addon's source…").frame(maxWidth: .infinity)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xxl)
        .frame(width: 560)
        .noInitialFocus()
        .onExitCommand { dismiss() }
    }

    private var title: String { model.gameFolder.explanation?.name?.title ?? SVReadable.label(target.key) }

    @ViewBuilder
    private func facts(_ e: SVExplanation) -> some View {
        Section("From the Addon's Source") {
            if e.isEmpty {
                Text("The addon's source doesn't say anything about this key.").foregroundStyle(.secondary)
            }
            if let name = e.name {
                LabeledContent("Name") {
                    Text(name.title.map { name.isGuess ? "\($0)?" : $0 } ?? "—")
                }
                .help(SourceNameText.help(name))
                if let detail = name.detail { LabeledContent("Description") { Text(detail).multilineTextAlignment(.trailing) } }
            }
            if let control = e.control {
                if control.type != "ai", control.type != "constants" { LabeledContent("Control", value: control.type.capitalized) }
                if let values = e.values {
                    LabeledContent(control.guessedChoices == true ? String(localized: "Values (AI guess)") : String(localized: "Values")) {
                        Text(values).multilineTextAlignment(.trailing)
                    }
                }
                if let d = control.defaultValue { LabeledContent("Default", value: d) }
                if let unit = control.unit { LabeledContent("Unit (AI guess)", value: unit) }
                if let kind = control.idKind { LabeledContent("Holds (AI guess)", value: String(localized: "\(kind) IDs")) }
                if let meaning = control.indexMeaning { LabeledContent("Each Position (AI guess)", value: meaning) }
            }
        }
    }

    @ViewBuilder
    private func aiSection(_ e: SVExplanation) -> some View {
        let folder = model.gameFolder
        Section {
            if !folder.explanationAI.isEmpty {
                Text(folder.explanationAI).textSelection(.enabled)
            }
            if let error = folder.explainError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.caution)
            }
            HStack {
                Button(folder.explanationAI.isEmpty ? "Explain with AI" : "Explain Again", systemImage: "sparkles") {
                    Task { await folder.explainWithAI() }
                }
                .disabled(!model.prefs.aiEnabled || folder.explainingWithAI || e.isEmpty)
                if folder.explainingWithAI { ProgressView().controlSize(.small) }
            }
        } footer: {
            Text(model.prefs.aiEnabled
                 ? String(localized: "Sends \(model.aiSource) what's above, never your saved values. Its answer is a guess.")
                 : String(localized: "Turn on AI in Settings to ask for an explanation."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
