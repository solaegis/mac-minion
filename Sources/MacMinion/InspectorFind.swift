import AppKit
import MacMinionKit
import SwiftUI

/// The find field above the Inspector. Return finds; Escape clears.
struct FindField: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        TextField("Find a character, item, or ID", text: Bindable(model.gameFolder).inspectorQuery)
            .textFieldStyle(.roundedBorder)
            .frame(width: 260)
            .focused($focused)
            .onSubmit { Task { await model.gameFolder.find(model.gameFolder.inspectorQuery) } }
            .onExitCommand { model.gameFolder.clearFind() }
            .onChange(of: model.gameFolder.inspectorFindRequested) { if model.gameFolder.inspectorFindRequested { focused = true; model.gameFolder.inspectorFindRequested = false } }
            .help("Find every place an ID appears, by name or ID, in all SavedVariables files (Command-F)")
    }
}

/// Results of a find: each ID with its places, grouped by file. Double-click one to open it in the tree.
struct FindResultsView: View {
    let model: AppModel
    @State private var selection: SVFindRow.ID?

    var body: some View {
        let results = model.gameFolder.inspectorResults ?? []
        List(selection: $selection) {
            ForEach(results) { result in
                Section {
                    ForEach(result.files) { file in
                        Text(file.file).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(file.rows) { row in
                            FindRowView(model: model, row: row).tag(row.id)
                        }
                    }
                } header: {
                    HStack {
                        Text(result.title).font(.headline)
                        Button("Connections") { Task { await model.gameFolder.showConnections(result.target) } }
                            .buttonStyle(.borderless)
                            .help("Show what's connected to this, as a map")
                        Spacer()
                        Text(summary(result)).foregroundStyle(.secondary)
                    }
                    .readableRow()
                }
            }
        }
        .contextMenu(forSelectionType: SVFindRow.ID.self) { ids in
            if let row = row(ids.first) {
                Button("Show in Tree") { Task { await model.gameFolder.reveal(row) } }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(row.path.luaPath, forType: .string)
                }
            }
        } primaryAction: { ids in
            if let row = row(ids.first) { Task { await model.gameFolder.reveal(row) } }
        }
        .overlay {
            if let message = model.gameFolder.inspectorFindMessage {
                ContentUnavailableView("No Matches", systemImage: "magnifyingglass", description: Text(message))
            }
        }
    }

    private func row(_ id: SVFindRow.ID?) -> SVFindRow? {
        model.gameFolder.inspectorResults?.lazy.flatMap(\.files).flatMap(\.rows).first { $0.id == id }
    }

    private func summary(_ result: SVFindResult) -> String {
        let places = String(localized: "\(result.total) places")
        let files = String(localized: "\(result.files.count) files")
        return result.shown < result.total ? String(localized: "\(places), first \(result.shown.formatted()) shown")
            : String(localized: "\(places) in \(files)")
    }
}

private struct FindRowView: View {
    let model: AppModel
    let row: SVFindRow

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs / 2) {
            Text(path).lineLimit(1).truncationMode(.head)
            Text(row.value).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    /// The path with names in place of IDs: "PCHAT_OPTS › NA Megaserver › @SOLAEGIS › Masisi".
    private var path: String {
        row.path.enumerated().map { i, key in
            let parent = Array(row.path.prefix(i))
            if let name = model.gameFolder.names?.name(forKey: key, at: parent), name.kind == .character, name.title != SVName.unknownCharacter {
                return name.title
            }
            return key.description
        }.joined(separator: " › ")
    }
}
