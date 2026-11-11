import AppKit
import MacMinionKit
import SwiftUI

/// An addon's saved settings as you'd read them (S-050): a grouped form with switches, color
/// swatches, item tags, dates, and gold. Read-only; every row can show its place in the tree.
struct ReadableSheetView: View {
    let model: AppModel
    @State private var sections: [SVReadable.Section] = []

    var body: some View {
        Form {
            // The table shown is keyed by constants: what its numbers are, as far as the source says.
            if let note = model.gameFolder.inspectorFocus.last.flatMap({ key in model.gameFolder.inspectorFile.flatMap { model.gameFolder.inspectorSourceNames[$0] }?.note(forTable: key) }) {
                Section {
                    Label(note, systemImage: "doc.text.magnifyingglass")
                        .foregroundStyle(.secondary)
                        .help("From the addon's source. The game assigns these numbers when it runs, so they can't be named here.")
                }
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        ReadableRow(model: model, row: row)
                            .contextMenu {
                                if case .table = row.display { Button("Open") { open(row) } }
                                Button("Show in Tree") { showInTree(row) }
                                Button("Copy Path") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(row.path.luaPath, forType: .string)
                                }
                            }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: Space.xs / 2) {
                        Text(section.title)
                        if let subtitle = section.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                        if let note = section.note {
                            Label(note, systemImage: "doc.text.magnifyingglass").font(.caption).foregroundStyle(.secondary)
                                .help("From the addon's source. The game assigns these numbers when it runs, so they can't be named here.")
                        }
                    }
                } footer: {
                    if section.more > 0 {
                        Text("\(section.more.formatted()) more. Switch to Tree to see them all.").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .overlay {
            if sections.isEmpty, !model.gameFolder.inspectorBusy {
                ContentUnavailableView("Nothing Saved Here", systemImage: "slider.horizontal.3",
                                       description: Text("This table has no settings to show."))
            }
        }
        .task(id: sheetKey) { await build() }
    }

    /// Rebuilt when the file, the table shown, or the names change.
    private var sheetKey: String {
        "\(model.gameFolder.inspectorFile ?? "")|\(model.gameFolder.inspectorFocus.map(\.description).joined(separator: "\u{1F}"))|\(model.gameFolder.names != nil)|\(model.gameFolder.inspectorSourceNames.count)"
    }

    private func build() async {
        let entries = model.gameFolder.inspectorRows.map { LuaEntry(key: $0.key, value: $0.value, span: $0.span) }
        let path = model.gameFolder.inspectorFocus, names = model.gameFolder.names
        let source = model.gameFolder.inspectorFile.flatMap { model.gameFolder.inspectorSourceNames[$0] }
        let title = model.gameFolder.inspectorFile.map { String($0.dropLast(4)) } ?? ""
        sections = await Task.detached { SVReadable.sheet(entries, at: path, title: title, names: names, source: source) }.value
    }

    private func open(_ row: SVReadable.Row) {
        model.gameFolder.inspectorFocus = row.path
        model.gameFolder.inspectorSelection = nil
    }

    private func showInTree(_ row: SVReadable.Row) {
        model.gameFolder.inspectorReadable = false
        model.gameFolder.inspectorFocus = Array(row.path.dropLast())
        model.gameFolder.inspectorSelection = SVNode(entry: .placeholder(row.key), parentPath: model.gameFolder.inspectorFocus).id
    }
}

private struct ReadableRow: View {
    let model: AppModel
    let row: SVReadable.Row

    var body: some View {
        LabeledContent {
            value
        } label: {
            if let source = row.source {
                VStack(alignment: .leading, spacing: Space.xs / 2) {
                    Text(source.isGuess && source.title != nil ? "\(row.label)?" : row.label)
                    // The key as saved, and the tooltip or comment from the source.
                    Text([row.key.description, source.detail, source.source == .ai ? String(localized: "AI guess") : source.isGuess ? String(localized: "guess") : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .help(SourceNameText.help(source))
            } else {
                Text(row.label).help(row.key.description)
            }
        }
    }

    private var value: some View {
        SettingValueView(display: row.display, label: row.label) {
            model.gameFolder.inspectorFocus = row.path
            model.gameFolder.inspectorSelection = nil
        }
    }
}

/// Text, then its icon: "12 settings ›".
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.xs) { configuration.title; configuration.icon.font(.caption) }
    }
}

/// A saved value as people read it: a switch, a color swatch, an item tag, a date, gold, or a name.
/// Shared by Settings and the character and addon explorer, so values look the same everywhere.
struct SettingValueView: View {
    let display: SVDisplay
    /// What the value is for, read aloud with a switch.
    let label: String
    /// Opens a table value; nil shows its size without a button.
    var openTable: (() -> Void)?

    var body: some View {
        switch display {
        case .toggle(let on):
            // Read-only: text and a symbol, not a switch people will try to click.
            Label(on ? "On" : "Off", systemImage: on ? "checkmark" : "minus")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .accessibilityLabel(label)
                .accessibilityValue(on ? "On" : "Off")
        case .color(let r, let g, let b, let a):
            HStack(spacing: Space.sm) {
                Text(Self.hex(r, g, b)).monospaced().foregroundStyle(.secondary)
                // The addon's saved color itself, so this is the one place a literal color belongs.
                RoundedRectangle(cornerRadius: Radius.cell)
                    .fill(Color(red: r, green: g, blue: b, opacity: a)) // hig: ok data color
                    .overlay(RoundedRectangle(cornerRadius: Radius.cell).strokeBorder(.separator))
                    .frame(width: 32, height: 20)
            }
        case .item(let title, let detail):
            HStack(spacing: Space.sm) {
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Text(title)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, Space.xs / 2)
                    .background(Palette.accentWash, in: RoundedRectangle(cornerRadius: Radius.chip))
                    .foregroundStyle(Palette.accentText)
            }
        case .date(let date):
            Text(date.formatted(date: .abbreviated, time: .shortened))
        case .gold(let amount):
            Text("\(amount.formatted(.number.precision(.fractionLength(0...2)))) gold").monospacedDigit()
        case .name(let name):
            HStack(spacing: Space.xs) {
                if name.title == SVName.unknownCharacter {
                    Image(systemName: "person.fill.questionmark").foregroundStyle(.secondary)
                    Text(name.title).foregroundStyle(.secondary)
                } else {
                    Text(name.title).foregroundStyle(Palette.accentText)
                }
                if let id = name.id, !name.title.contains(id) {
                    Text(id).font(.caption.monospacedDigit()).foregroundStyle(.tertiary).lineLimit(1)
                }
                Text("· \(name.kind.rawValue)").foregroundStyle(.secondary)
            }
            .help("From \(name.source)")
        case .number(let text):
            Text(text).monospacedDigit()
        case .text(let text):
            Text(text).lineLimit(2).textSelection(.enabled)
        case .table(let count, let isList):
            let words = "\(count.formatted()) \(isList ? (count == 1 ? "item" : "items") : (count == 1 ? "setting" : "settings"))"
            if let openTable {
                Button(action: openTable) {
                    Label(words, systemImage: "chevron.right").labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(.borderless)
                .help("Show what's inside")
            } else {
                Text(words).foregroundStyle(.secondary)
            }
        }
    }

    static func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
