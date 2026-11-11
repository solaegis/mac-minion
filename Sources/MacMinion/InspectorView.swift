import AppKit
import MacMinionKit
import SwiftUI

/// How a name from an addon's source reads: where it came from, and whether it's a guess.
nonisolated enum SourceNameText {
    static func help(_ name: SVSourceName) -> String {
        var text = String(localized: "From \(name.source.description)")
        if name.source == .ai { text += ". " + String(localized: "A guess: check it against the addon's settings") }
        else if name.isGuess { text += ". " + String(localized: "A guess: matched by the key's name, so it may describe another table's key") }
        if let detail = name.detail { text += ": \(detail)" }
        return text
    }
}

/// How values read in the Value column.
nonisolated enum InspectorValue {
    static func plain(_ value: LuaValue) -> String? {
        switch value {
        case .string(let s): s
        case .integer(let n): String(n)
        case .number(let n): n.formatted(.number.precision(.significantDigits(1...10)))
        case .bool(let b): b ? "true" : "false"
        case .nil: "nil"
        case .table: nil
        }
    }

    static func preview(_ value: LuaValue) -> String {
        switch value {
        case .table(let t): t.count == 1 ? "1 entry" : "\(t.count.formatted()) entries"
        case .string(let s): "“\(s.count > 300 ? String(s.prefix(300)) + "…" : s)”"
        default: plain(value) ?? ""
        }
    }
}

/// One SavedVariables file as a tree: its files on the left, the tree with names on the right.
struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HSplitView {
            List(model.gameFolder.inspectorFiles, selection: Binding(
                get: { model.gameFolder.inspectorFile },
                set: { name in if let name, name != model.gameFolder.inspectorFile { Task { await model.gameFolder.inspect(name) } } })) { file in
                HStack {
                    Text(file.name).lineLimit(1)
                    Spacer()
                    Text(file.bytes.formatted(.byteCount(style: .file))).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .tag(file.name)
                .contextMenu {
                    Button("Open in Editor") { model.gameFolder.openInEditor([file.url]) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let filter = model.gameFolder.inspectorAddonFilter {
                    AddonFilterBar(title: String(localized: "Files for \(filter.name)"), clear: String(localized: "Show All Files"),
                                   area: "inspector-filter",
                                   escape: model.gameFolder.inspectorResults == nil && model.gameFolder.inspectorConnections == nil) { model.gameFolder.inspectorAddonFilter = nil }
                }
            }
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 360, maxHeight: .infinity)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if let hood = model.gameFolder.inspectorConnections {
                        HStack(spacing: Space.sm) {
                            Button("Back", systemImage: "chevron.left") { Task { await model.gameFolder.connectionsGoBack() } }
                                .disabled(model.gameFolder.connectionsBack.isEmpty)
                                .help("Go back to the last thing you followed")
                            Text("Connections: \(model.gameFolder.connectionTitle(hood.target))").font(.headline).lineLimit(1)
                        }
                        .padding(.leading, Space.margin)
                        Spacer()
                        Button("Done") { model.gameFolder.closeConnections() }
                            .keyboardShortcut(.cancelAction)
                            .help("Close the map and go back to the tree (Escape)")
                            .padding(.trailing, Space.sm)
                    } else if model.gameFolder.inspectorResults == nil, model.gameFolder.inspectorFile != nil { PathBar() } else { Spacer() }
                    if model.gameFolder.inspectorResults != nil, model.gameFolder.inspectorConnections == nil {
                        Button("Done") { model.gameFolder.clearFind() }
                            .keyboardShortcut(.cancelAction)
                            .help("Close the results and go back to the tree (Escape)")
                            .padding(.trailing, Space.sm)
                    }
                    if model.gameFolder.inspectorResults == nil, model.gameFolder.inspectorConnections == nil, model.gameFolder.inspectorFile != nil {
                        Group {
                            if model.gameFolder.aiNamingBusy {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Name with AI", systemImage: "sparkles") { Task { await model.gameFolder.nameKeysWithAI() } }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .disabled(!model.prefs.aiEnabled)
                                    .help(model.prefs.aiEnabled
                                          ? String(localized: "Ask \(model.aiSource) to name this table's keys from the addon's source. Sends key names and source lines, never your saved values (Option-Command-N)")
                                          : String(localized: "Turn on AI in Settings to name keys from the addon's source"))
                            }
                        }
                        .padding(.trailing, Space.sm)
                        Picker("Show", selection: Bindable(model.gameFolder).inspectorReadable) {
                            Text("Settings").tag(true)
                            Text("Tree").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .help("Show settings as you'd read them, or every key and value (Control-Command-T)")
                        .padding(.trailing, Space.sm)
                    }
                    FindField().padding(.trailing, Space.margin)
                }
                .padding(.vertical, model.gameFolder.inspectorResults == nil && model.gameFolder.inspectorConnections == nil && model.gameFolder.inspectorFile != nil ? 0 : Space.sm)
                .background(.bar)
                Divider()
                if model.gameFolder.inspectorConnections != nil {
                    ConnectionsView(model: model)
                } else if model.gameFolder.inspectorResults != nil {
                    FindResultsView(model: model)
                } else if model.gameFolder.inspectorFile == nil {
                    ContentUnavailableView("Choose a File", systemImage: "list.bullet.indent",
                                           description: Text("Pick a SavedVariables file to see what it stores, with names for the characters, items, and places in it."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if let error = model.gameFolder.inspectorDocument?.error, model.gameFolder.inspectorFocus.isEmpty {
                        Label(error.endedEarly ? String(localized: "This file ends early: \(error.description). Everything before it is below.")
                              : String(localized: "This file has a mistake: \(error.description). Everything before it is below."),
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.negative)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.margin)
                            .padding(.vertical, Space.sm)
                            .background(.bar)
                    }
                    if model.gameFolder.inspectorReadable { ReadableSheetView(model: model) } else { InspectorTable() }
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        // HSplitView sizes to its panes' ideal height, which leaves both squeezed at the bottom of the window.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: Bindable(model.gameFolder).inspectorRaw) { RawSheet(node: $0) }
        .task { await model.gameFolder.load() }
    }
}

/// Where the shown table sits: the file, then each key, with names. Click one to go up to it.
private struct PathBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                Button("Back", systemImage: "chevron.left") { model.gameFolder.inspectorEnclosing() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(model.gameFolder.inspectorFocus.isEmpty)
                    .help("Go back to the table around this one (Command-[)")
                crumb(model.gameFolder.inspectorFile ?? "", depth: 0, symbol: "doc")
                ForEach(Array(model.gameFolder.inspectorFocus.enumerated()), id: \.offset) { i, key in
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    crumb(title(key, parent: Array(model.gameFolder.inspectorFocus.prefix(i))), depth: i + 1, symbol: nil)
                }
                if model.gameFolder.inspectorBusy { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.sm)
        }
        .background(.bar)
    }

    private func crumb(_ title: String, depth: Int, symbol: String?) -> some View {
        Button {
            model.gameFolder.inspectorFocus = Array(model.gameFolder.inspectorFocus.prefix(depth))
        } label: {
            if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
        }
        .buttonStyle(.borderless)
        .disabled(depth == model.gameFolder.inspectorFocus.count)
        .help(depth == model.gameFolder.inspectorFocus.count ? String(localized: "The table shown below") : String(localized: "Go up to this table"))
    }

    private func title(_ key: LuaKey, parent: [LuaKey]) -> String {
        let node = SVNode(entry: .placeholder(key), parentPath: parent)
        if let name = model.gameFolder.names?.name(forKey: key, at: parent) {
            // Character crumbs use the name only; the ID stays in the tree and value cells.
            if name.kind == .character { return name.title }
            // "@SOLAEGIS (yours)" rather than repeating the account's own name.
            return "\(key) (\(name.title == key.description ? name.detail ?? name.kind.rawValue : name.title))"
        }
        if let level = node.level { return "\(key) (\(level.title))" }
        if let title = model.gameFolder.inspectorSourceName(key, at: parent)?.title { return "\(key) (\(title))" }
        return key.description
    }
}

private struct InspectorTable: View {
    @Environment(AppModel.self) private var model

    /// "8796…2335" so a character ID fits beside its name.
    static func shortID(_ id: String) -> String {
        guard id.count > 10 else { return id }
        return "\(id.prefix(4))…\(id.suffix(4))"
    }

    var body: some View {
        @Bindable var model = model
        Table(model.gameFolder.inspectorRows, children: \.children, selection: Bindable(model.gameFolder).inspectorSelection) {
            TableColumn("Key") { node in
                HStack(spacing: Space.sm) {
                    if let name = model.gameFolder.names?.name(forKey: node.key, at: node.parentPath), name.kind == .character {
                        if name.title == SVName.unknownCharacter {
                            Image(systemName: "person.fill.questionmark").foregroundStyle(.secondary)
                            Text(name.title).lineLimit(1).foregroundStyle(.secondary)
                        } else {
                            Text(name.title).lineLimit(1)
                        }
                        Text(Self.shortID(node.key.description))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    } else {
                        Text(node.key.description).lineLimit(1)
                        if let level = node.level, model.gameFolder.names?.name(forKey: node.key, at: node.parentPath) == nil {
                            Text(level.title).foregroundStyle(.secondary)
                        } else if let source = model.gameFolder.inspectorSourceName(node.key, at: node.parentPath), let title = source.title {
                            Text(source.isGuess ? "\(title)?" : title)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                                .help(SourceNameText.help(source))
                        }
                    }
                }
            }
            .width(min: 160, ideal: 260)
            TableColumn("Value") { node in ValueCell(model: model, node: node) }
                .width(min: 200, ideal: 420)
            TableColumn("Size") { node in
                Text(node.bytes.formatted(.byteCount(style: .file))).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 64, ideal: 80)
        }
        // Empty filler rows looked like a loading skeleton once past the real keys.
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: SVNode.ID.self) { ids in
            if let id = ids.first, let node = model.gameFolder.inspectorNode(id) {
                if node.children != nil { Button("Open Table") { model.gameFolder.inspectorOpen(node) } }
                if SVTarget.of(key: node.key, at: node.parentPath) != nil
                    || model.gameFolder.names.flatMap({ SVTarget.of(value: node.value, key: node.key, at: node.parentPath, names: $0) }) != nil {
                    Button("Find Everywhere") { Task { await model.gameFolder.findEverywhere(node) } }
                    if let target = model.gameFolder.target(of: node) {
                        Button("Show Connections") { Task { await model.gameFolder.showConnections(target) } }
                    }
                }
                Button("Copy Path") { model.gameFolder.inspectorSelection = id; model.gameFolder.copyInspectorPath() }
                Button("Copy Value") { model.gameFolder.inspectorSelection = id; model.gameFolder.copyInspectorValue() }
                Button("Show Raw…") { model.gameFolder.inspectorRaw = node }
                if let url = model.gameFolder.inspectorName(node)?.uesp {
                    Divider()
                    Button("Look Up on UESP") { NSWorkspace.shared.open(url) }
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, let node = model.gameFolder.inspectorNode(id) { model.gameFolder.inspectorOpen(node) }
        }
        .overlay {
            if model.gameFolder.inspectorRows.isEmpty, !model.gameFolder.inspectorBusy {
                ContentUnavailableView("Nothing Saved", systemImage: "tray",
                                       description: Text("This file has no variables. The game writes them when it quits."))
            }
        }
    }
}

/// The value, and a name for it or its key when one is known. Takes the model directly:
/// table cells can be rebuilt (on an appearance change) without the window's environment.
private struct ValueCell: View {
    let model: AppModel
    let node: SVNode

    var body: some View {
        let name = model.gameFolder.inspectorName(node)
        HStack(spacing: Space.sm) {
            Text(InspectorValue.preview(node.value))
                .lineLimit(1)
                .foregroundStyle(node.value.table == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            if let name {
                if name.title == SVName.unknownCharacter {
                    Label(name.label, systemImage: "person.fill.questionmark")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .help("From \(name.source)")
                } else {
                    Text(name.label)
                        .lineLimit(1)
                        .foregroundStyle(Palette.accentText)
                        .help("From \(name.source)")
                }
            }
        }
    }
}

private struct RawSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let node: SVNode

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(node.path.luaPath).font(.headline).textSelection(.enabled).lineLimit(2)
            ScrollView([.vertical, .horizontal]) {
                Text(model.gameFolder.inspectorRawText(node))
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fitsContent(max: 480)
            HStack {
                Text("\(node.bytes.formatted(.byteCount(style: .file))) as written in \(model.gameFolder.inspectorFile ?? "the file")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xxl)
        .frame(width: 640)
        .noInitialFocus()
        .onExitCommand { dismiss() }
    }
}

/// The Inspector menu: every action on the selected row, with shortcuts.
struct InspectorCommands: View {
    let model: AppModel

    var body: some View {
        let inspecting = model.sidebar == .gameFolder && model.gameFolder.tab == .inspector && model.gameFolder.inspectorFile != nil
        let node = inspecting ? model.gameFolder.inspectorSelectedNode : nil
        Button("Open Table") { model.gameFolder.inspectorOpen() }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(node?.children == nil)
        Button("Enclosing Table") { model.gameFolder.inspectorEnclosing() }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(!inspecting || model.gameFolder.inspectorFocus.isEmpty)
        Divider()
        Button("Copy Path") { model.gameFolder.copyInspectorPath() }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(node == nil)
        Button("Copy Value") { model.gameFolder.copyInspectorValue() }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(node == nil)
        Button("Show Raw…") { model.gameFolder.inspectorRaw = node }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(node == nil)
        Button("Look Up on UESP") { model.gameFolder.lookUpOnUESP() }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(node.flatMap { model.gameFolder.inspectorName($0)?.uesp } == nil)
        Button("Name Keys with AI") { Task { await model.gameFolder.nameKeysWithAI() } }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(!inspecting || !model.prefs.aiEnabled || model.gameFolder.aiNamingBusy)
        Button("Open in Editor") { model.gameFolder.openInEditor([model.gameFolder.inspectorFileURL].compactMap { $0 }) }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(!inspecting)
        Button(model.gameFolder.inspectorReadable ? String(localized: "Show as Tree") : String(localized: "Show as Settings")) { model.gameFolder.inspectorReadable.toggle() }
            .keyboardShortcut("t", modifiers: [.command, .control])
            .disabled(!inspecting)
        let exploring = model.sidebar == .gameFolder && model.gameFolder.tab == .characters
        Button("Back") { exploring ? model.gameFolder.explorerBack() : model.gameFolder.inspectorEnclosing() }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(exploring ? model.gameFolder.explorerPath.count <= 1
                      : !(inspecting && model.gameFolder.inspectorResults == nil && model.gameFolder.inspectorConnections == nil && !model.gameFolder.inspectorFocus.isEmpty))
        // Game Folder's tabs, in toolbar order: Control-Command-1 to 4.
        Button("Go to Characters") { model.open(.gameFolder); model.gameFolder.tab = .characters; model.gameFolder.explorerReset() }
            .keyboardShortcut("1", modifiers: [.command, .control])
        Button("Go to Inspector") { model.open(.gameFolder); model.gameFolder.tab = .inspector }
            .keyboardShortcut("2", modifiers: [.command, .control])
        Button("Go to Problems") { model.open(.gameFolder); model.gameFolder.tab = .problems }
            .keyboardShortcut("3", modifiers: [.command, .control])
        Button("Go to Game Settings") { model.open(.gameFolder); model.gameFolder.tab = .gameSettings }
            .keyboardShortcut("4", modifiers: [.command, .control])
        Button("Compare Characters…") { model.open(.gameFolder); model.gameFolder.tab = .characters; model.gameFolder.choosingComparison = true }
            .keyboardShortcut("c", modifiers: [.command, .control])
            .disabled(model.gameFolder.matrix == nil)
        // Files > Game Settings (S-062).
        let settingsKind = model.sidebar == .gameFolder && model.gameFolder.tab == .gameSettings ? model.gameFolder.gameSettingsKind : nil
        Button("Save Game Settings") {
            if let settingsKind { Task { await model.gameFolder.saveGameSettings(settingsKind, undoManager: NSApp.keyWindow?.undoManager) } }
        }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(settingsKind.map { model.gameFolder.gameSettingsEdits($0) == 0 } ?? true || model.gameIsRunning)
        Button("Revert Game Settings") { if let settingsKind { model.gameFolder.revertGameSettings(settingsKind) } }
            .keyboardShortcut("z", modifiers: [.command, .option])
            .disabled(settingsKind.map { model.gameFolder.gameSettingsEdits($0) == 0 } ?? true)
        let compared = model.gameFolder.comparedCharacters
        let comparedFile = model.gameFolder.comparedFile
        Button("Clone Left Character…") { model.gameFolder.cloneSource = compared?.0 }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option, .control])
            .disabled(compared.map { model.gameFolder.copyAllRows(from: $0.0, to: $0.1, file: comparedFile).isEmpty } ?? true || model.gameIsRunning)
        Button("Clone Right Character…") { model.gameFolder.cloneSource = compared?.1 }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option, .control])
            .disabled(compared.map { model.gameFolder.copyAllRows(from: $0.1, to: $0.0, file: comparedFile).isEmpty } ?? true || model.gameIsRunning)
        let finding = model.gameFolder.selectedFinding
        Button(finding?.action.map { model.gameFolder.title(for: $0) } ?? String(localized: "Fix Problem")) {
            if let finding, let action = finding.action { model.gameFolder.run(action, in: finding) }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(finding?.action.map(model.gameFolder.isDisabled) ?? true)
        Button(finding.map { model.gameFolder.problemsExpanded.contains($0.id) } == true ? "Hide Problem Details" : "Show Problem Details") {
            if let finding { model.gameFolder.toggleDetails(finding.id) }
        }
        .keyboardShortcut("i", modifiers: .command) // hig: ok no Format menu; Command-I is Get Info-like here
        .disabled(finding?.problems.isEmpty ?? true)
        Button("Show Problem in Inspector") {
            if let problem = finding?.problems.first { Task { await model.gameFolder.openProblem(problem) } }
        }
        .keyboardShortcut(.return, modifiers: [.command, .option])
        .disabled(finding?.problems.isEmpty ?? true)
        Button("Clean Up All Not in Use…") { model.gameFolder.askToCleanUp(model.gameFolder.fileProblems) }
            .keyboardShortcut(.delete, modifiers: [.command, .option])
            .disabled(model.gameFolder.fileProblems.isEmpty || model.gameIsRunning || model.backupBusy != nil)
        Divider()
        Button("Find…") { model.open(.gameFolder); model.gameFolder.tab = .inspector; model.gameFolder.inspectorFindRequested = true }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(model.sidebar != .gameFolder)
        Button("Find Everywhere") { Task { await model.gameFolder.findEverywhere() } }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(node == nil)
        Button("Show Connections") { if let node, let target = model.gameFolder.target(of: node) { Task { await model.gameFolder.showConnections(target) } } }
            .keyboardShortcut("k", modifiers: [.command, .option])
            .disabled(node.flatMap { model.gameFolder.target(of: $0) } == nil)
    }
}

/// Shown while SavedVariables are read: what it's doing now, and how far along.
struct InspectorLoadingView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: Space.sm) {
            ProgressView(value: model.gameFolder.progress?.fraction ?? 0) {
                Text("Reading Your SavedVariables")
            } currentValueLabel: {
                Text(model.gameFolder.progress?.step ?? "Starting…")
            }
            Text("This takes a moment with many characters and addons.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
