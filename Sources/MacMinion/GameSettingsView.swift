import AppKit
import MacMinionKit
import SwiftUI

/// Files > Game Settings: UserSettings.txt, AddOnSettings.txt, and MachineSettings.txt as forms, each field
/// edited the way its value reads (S-062). Edits are a draft until Save.
struct GameSettingsView: View {
    @Environment(AppModel.self) private var model
    /// The window's, so Edit › Undo puts back what Save wrote.
    @Environment(\.undoManager) private var undoManager
    // The filter stays in this bar, not the toolbar (rule 36): a second `.searchable` beside Installed's puts two
    // search fields in the toolbar for a moment when pages switch, and NSToolbar throws (see BrowsePage).
    @State private var search = ""

    var body: some View {
        @Bindable var model = model
        let kind = model.gameFolder.gameSettingsKind
        VStack(spacing: 0) {
            HStack(spacing: Space.md) {
                Picker("File", selection: Bindable(model.gameFolder).gameSettingsKind) {
                    ForEach(GameSettingsFile.Kind.allCases) { Text($0.fileName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .gridProbe("game-settings-kind", area: "game-settings-bar", edge: nil)
                TextField("Filter settings", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Spacer(minLength: Space.md)
                let edits = model.gameFolder.gameSettingsEdits(kind)
                if edits > 0 {
                    Text(String(localized: "\(edits) settings")).font(.callout).foregroundStyle(.secondary)
                }
                Button("Revert") { model.gameFolder.revertGameSettings(kind) }
                    .disabled(edits == 0)
                    .help("Drop the edits to this file (Option-Command-Z)")
                Button("Save") { Task { await model.gameFolder.saveGameSettings(kind, undoManager: undoManager) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(edits == 0 || model.gameIsRunning || model.backupBusy != nil)
                    .help(model.gameIsRunning ? String(localized: "Quit Elder Scrolls Online first")
                          : String(localized: "Back up, then write the edits to \(kind.fileName) (Command-S)"))
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.sm)
            .background(.bar)
            .gridArea("game-settings-bar")
            Divider()
            if let file = model.gameFolder.gameSettings[kind] {
                form(file)
            } else {
                ContentUnavailableView(String(localized: "No \(kind.fileName)"), systemImage: "doc.text",
                                       description: Text("The game writes this file the first time it runs on this Mac."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { model.gameFolder.loadGameSettings() }
    }

    private func form(_ file: GameSettingsFile) -> some View {
        let fields = file.fields.filter { search.isEmpty || $0.key.localizedCaseInsensitiveContains(search) || ($0.section ?? "").localizedCaseInsensitiveContains(search) }
        // Top-level settings first, then each character's addons in file order.
        var sections: [String?] = [nil]
        for field in fields where !sections.contains(field.section) { sections.append(field.section) }
        return Form {
            ForEach(sections, id: \.self) { section in
                // A character's addons by name; the top-level settings keep the file's order.
                let inSection = fields.filter { $0.section == section }
                let rows = section == nil ? inSection : inSection.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                if !rows.isEmpty {
                    Section(sectionTitle(section, kind: file.kind)) {
                        ForEach(rows) { field in
                            GameSettingRow(model: model, kind: file.kind, field: field)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .overlay {
            if fields.isEmpty, !search.isEmpty { ContentUnavailableView.search(text: search) }
        }
    }

    private func sectionTitle(_ section: String?, kind: GameSettingsFile.Kind) -> String {
        guard let section else { return kind == .addOns ? String(localized: "Every Character") : kind.fileName }
        if section == "Default" { return String(localized: "Default (characters without their own list)") }
        // "NA Megaserver-Masisi" reads as "Masisi · NA Megaserver".
        if let dash = section.firstIndex(of: "-"), section[..<dash].hasSuffix("Megaserver") || section[..<dash] == "PTS" {
            return "\(section[section.index(after: dash)...]) · \(section[..<dash])"
        }
        return section
    }
}

/// One setting: its key, the editor its type calls for, and a mark when it's edited.
private struct GameSettingRow: View {
    let model: AppModel
    let kind: GameSettingsFile.Kind
    let field: GameSettingsFile.Field

    private var value: String { model.gameFolder.gameSettingValue(field, in: kind) }
    private var edited: Bool { value != field.value }
    /// Curated tip for this row; Form cells ignore `.help` on the outer `LabeledContent`, so it goes on the label and editor.
    private var tip: String? { GameSettingsFile.help(for: field, kind: kind) }

    var body: some View {
        LabeledContent {
            HStack(spacing: Space.sm) {
                editor
                    .modifier(OptionalHelp(tip))
                if edited {
                    Button("Undo Edit", systemImage: "arrow.uturn.backward") { model.gameFolder.setGameSetting(field, in: kind, to: field.value) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(String(localized: "Back to \(field.value)"))
                }
            }
        } label: {
            HStack(spacing: Space.xs) {
                if edited { Circle().fill(Palette.accent).frame(width: Space.sm, height: Space.sm).accessibilityLabel("Edited") }
                Text(field.key).textSelection(.enabled)
            }
            .modifier(OptionalHelp(tip))
        }
        .contextMenu {
            if edited { Button("Undo Edit") { model.gameFolder.setGameSetting(field, in: kind, to: field.value) } }
            Button("Copy Key") { copy(field.key) }
            Button("Copy Value") { copy(value) }
        }
    }

    private func set(_ new: String) { model.gameFolder.setGameSetting(field, in: kind, to: new) }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @ViewBuilder
    private var editor: some View {
        switch field.type {
        case .toggle:
            Toggle(field.key, isOn: Binding(get: { value == "1" }, set: { set($0 ? "1" : "0") }))
                .labelsHidden()
                .toggleStyle(.switch)
        case .integer:
            TextField(field.key, value: Binding(get: { Int(value) ?? 0 }, set: { set(String($0)) }), format: .number.grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 120)
        case .decimal:
            // The game writes decimals with eight places ("0.85000002").
            TextField(field.key, value: Binding(get: { Double(value) ?? 0 }, set: { set(String(format: "%.8f", $0)) }),
                      format: .number.grouping(.never).precision(.fractionLength(0...8)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 120)
        case .color:
            ColorPicker(field.key, selection: Binding(get: { Self.color(argb: value) }, set: { set(Self.argb($0)) }), supportsOpacity: true)
                .labelsHidden()
        case .size:
            let parts = value.split(separator: "x").map { Int($0) ?? 0 }
            let w = parts.first ?? 0, h = parts.count > 1 ? parts[1] : 0
            HStack(spacing: Space.xs) {
                TextField("Width", value: Binding(get: { w }, set: { set("\($0)x\(h)") }), format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing).frame(width: 72)
                Text(verbatim: "×").foregroundStyle(.secondary)
                TextField("Height", value: Binding(get: { h }, set: { set("\(w)x\($0)") }), format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing).frame(width: 72)
            }
            .labelsHidden()
        case .choice(let options):
            Picker(field.key, selection: Binding(get: { value }, set: { set($0) })) {
                ForEach(options, id: \.value) { Text($0.title).tag($0.value) }
            }
            .labelsHidden()
            .fixedSize()
        case .text:
            TextField(field.key, text: Binding(get: { value }, set: { set($0) }))
                .labelsHidden()
                .frame(maxWidth: 280)
        }
    }

    /// AARRGGBB, as the game writes colors.
    static func color(argb: String) -> Color {
        guard let n = UInt32(argb, radix: 16) else { return .clear }
        func c(_ shift: UInt32) -> Double { Double((n >> shift) & 0xFF) / 255 }
        return Color(.sRGB, red: c(16), green: c(8), blue: c(0), opacity: c(24)) // hig: ok data color: the game's own ARGB value
    }

    static func argb(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black // hig: ok fallback for a color value, not drawn
        func b(_ x: CGFloat) -> Int { Int((x * 255).rounded()) }
        return String(format: "%02x%02x%02x%02x", b(ns.alphaComponent), b(ns.redComponent), b(ns.greenComponent), b(ns.blueComponent))
    }
}

/// Applies `.help` only when MacMinion has a curated tip (Form cells need it on the control, not the row chrome).
private struct OptionalHelp: ViewModifier {
    let tip: String?
    init(_ tip: String?) { self.tip = tip }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let tip {
            content.help(tip)
        } else {
            content
        }
    }
}
