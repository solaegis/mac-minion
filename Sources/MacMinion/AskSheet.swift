import MacMinionKit
import SwiftUI

/// Ask About Your Game Folder (S-076): a question in plain words, answered by the configured AI from
/// what MacMinion read, looked up through tools. Saved values go only after you allow it this session.
struct AskSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var folder = model.gameFolder
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Ask About Your Game Folder").font(.title2.bold())
            HStack(spacing: Space.sm) {
                TextField("Which characters have Auto craft off?", text: $folder.askQuestion, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await folder.ask() } }
                Button("Ask", systemImage: "sparkles") { Task { await folder.ask() } }
                    .disabled(folder.askBusy || folder.askQuestion.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !folder.askSteps.isEmpty || folder.askBusy {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(Array(folder.askSteps.enumerated()), id: \.offset) { _, step in
                        Label(step, systemImage: "magnifyingglass").font(.callout).foregroundStyle(.secondary)
                    }
                    if folder.askBusy { ProgressView().controlSize(.small) }
                }
            }
            if !folder.askAnswer.isEmpty {
                ScrollView {
                    Text(folder.askAnswer)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fitsContent(max: 360)
            }
            if let error = folder.askError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.caution)
            }
            HStack {
                Text("\(model.aiSource) looks things up in what MacMinion read. Its answer can be wrong.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xxl)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .noInitialFocus()
        .onExitCommand { dismiss() }
        // The permission question, over this sheet while it's open.
        .sheet(item: Binding(get: { model.valuesRequest }, set: { if $0 == nil { model.answerValuesRequest(false) } })) {
            ValuesPermissionSheet(request: $0)
        }
    }
}
