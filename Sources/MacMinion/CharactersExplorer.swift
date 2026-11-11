import AppKit
import MacMinionKit
import SwiftUI

/// Where the character and addon explorer is (S-053 to S-056), outermost first.
enum ExplorerLevel: Hashable {
    /// Every addon that keeps per-character settings, by every character.
    case grid
    case character(String)
    case addon(String)
    /// One character's settings in one addon.
    case characterAddon(id: String, file: String)
    /// One setting's values across characters.
    case setting(file: String, key: String)
    /// Two characters side by side (S-057). When `file` is set, only that addon's settings (S-066).
    case compare(String, String, file: String?)
    /// An account with its megaservers around it (S-061).
    case account(String)
    /// One account's characters on one megaserver.
    case server(account: String, server: String)
}

extension AppModel {
    /// Addons in the order people read them: by the name shown, not the file's. The matrix sorts by file
    /// (DolgubonsLazyWritCreator.lua), which puts "Lazy Writ Creator" out of place.
    func byName<T>(_ items: [T], file: (T) -> String) -> [T] {
        items.sorted { addonName(file($0)).localizedStandardCompare(addonName(file($1))) == .orderedAscending }
    }

    /// The addon's name as people know it: from ESOUI, its manifest, or the folder.
    func addonTitle(folder: String) -> String {
        if folder == "ZO_" { return String(localized: "The game") }
        if let addon = installed.first(where: { $0.record.dirs.contains(folder) }) { return addon.catalog.name }
        if let loose = unmatched.first(where: { $0.folder == folder }) { return loose.title }
        return folder
    }

    /// "Lazy Writ Creator" for DolgubonsLazyWritCreator.lua, as ESOUI names it.
    func addonName(_ file: String) -> String {
        let base = String(file.dropLast(4))
        return addonTitle(folder: base.hasPrefix("ZO_") ? "ZO_" : base)
    }
}

/// The Characters and Addons tabs: from every character and addon down to one setting, as pictures.
struct CharactersExplorer: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            Divider()
            Group {
                if let matrix = model.gameFolder.matrix {
                    switch model.gameFolder.explorerPath.last ?? .grid {
                    case .grid: SettingsGridView(model: model, matrix: matrix)
                    case .character(let id): CharacterConstellation(model: model, matrix: matrix, id: id)
                    case .addon(let file): AddonAcrossCharacters(model: model, matrix: matrix, file: file)
                    case .characterAddon(let id, let file): CharacterInAddon(model: model, matrix: matrix, id: id, file: file)
                    case .setting(let file, let key): SettingAcrossCharacters(model: model, matrix: matrix, file: file, key: key)
                    case .compare(let a, let b, let file): CompareCharacters(model: model, matrix: matrix, a: a, b: b, file: file)
                    case .account(let account): AccountConstellation(model: model, matrix: matrix, account: account)
                    case .server(let account, let server): ServerConstellation(model: model, matrix: matrix, account: account, server: server)
                    }
                } else {
                    InspectorLoadingView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await model.gameFolder.load() }
        .sheet(isPresented: Binding(get: { model.gameFolder.choosingComparison }, set: { model.gameFolder.choosingComparison = $0 })) {
            CompareChooser(model: model)
        }
    }

    private var pathBar: some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(model.gameFolder.explorerPath.enumerated()), id: \.offset) { i, level in
                if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                if i == model.gameFolder.explorerPath.count - 1 {
                    // Where you are, as plain text: a disabled accent button was too pale to read.
                    Text(title(level)).accessibilityAddTraits(.isHeader)
                } else {
                    Button(title(level)) { model.gameFolder.explorerPath = Array(model.gameFolder.explorerPath.prefix(i + 1)) }
                        .buttonStyle(.borderless)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.sm)
        .background(.bar)
    }

    private func title(_ level: ExplorerLevel) -> String {
        switch level {
        case .grid: String(localized: "All Characters")
        case .character(let id): model.gameFolder.characterName(id)
        case .addon(let file): model.addonName(file)
        case .characterAddon(_, let file): model.addonName(file)
        case .setting(_, let key): key
        case .compare(let a, let b, _): "\(model.gameFolder.compareName(a, other: b)) and \(model.gameFolder.compareName(b, other: a))"
        case .account(let account): account
        case .server(_, let server): server
        }
    }
}

// MARK: - Every character by every addon

/// Addons (rows) by characters (columns): shaded by how many settings, outlined where a character is
/// set up differently. Click a cell, an addon, or a character to go there.
private struct SettingsGridView: View {
    let model: AppModel
    let matrix: SettingsMatrix
    @State private var hovered: String?

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("\(matrix.addons.count) addons keep settings for each of your \(matrix.characterIDs.count) characters. Darker squares hold more settings; outlined ones have settings set differently from your other characters.")
                    .font(.callout)
                    .gridProbe("explorer-intro", area: "explorer")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 640, alignment: .leading)
                Grid(alignment: .leading, horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                    // Account, then megaserver, over the characters they hold.
                    GridRow {
                        Color.clear.frame(width: 200, height: 1)
                        ForEach(Array(matrix.accounts.enumerated()), id: \.element.id) { i, account in
                            if i > 0 { divider(strong: true) }
                            span(account.account, characters: account.characters.count, dividers: account.servers.count - 1,
                                 font: .callout.weight(.semibold),
                                 help: String(localized: "Show \(account.account) with its megaservers")) {
                                model.gameFolder.explorerOpen(.account(account.account))
                            }
                        }
                    }
                    GridRow {
                        Color.clear.frame(width: 200, height: 1)
                        ForEach(Array(matrix.accounts.enumerated()), id: \.element.id) { i, account in
                            if i > 0 { divider(strong: true) }
                            ForEach(Array(account.servers.enumerated()), id: \.element.id) { j, server in
                                if j > 0 { divider(strong: false) }
                                span(SettingsMatrix.shortServer(server.server), characters: server.characters.count, dividers: 0,
                                     font: .caption, help: String(localized: "Show the characters of \(account.account) on \(server.server)")) {
                                    model.gameFolder.explorerOpen(.account(account.account))
                                    model.gameFolder.explorerOpen(.server(account: account.account, server: server.server))
                                }
                            }
                        }
                    }
                    GridRow(alignment: .bottom) {
                        Color.clear.frame(width: 200, height: 1)
                        // No divider lines in this row: the slanted names lean over the next column and would cross them.
                        columns(lines: false) { id in
                            Button { model.gameFolder.explorerOpen(.character(id)) } label: {
                                Text(model.gameFolder.characterName(id))
                                    .font(.caption)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .rotationEffect(.degrees(-60), anchor: .bottomLeading)
                                    .frame(width: 32, height: 112, alignment: .bottomLeading)
                                    .foregroundStyle(hovered == id ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.secondary))
                            }
                            .buttonStyle(.plain)
                            .help("\(model.gameFolder.characterTitle(id)): show their settings across addons")
                        }
                    }
                    ForEach(model.byName(matrix.addons, file: \.file)) { addon in
                        let most = max(1, addon.characters.values.map(\.count).max() ?? 1)
                        GridRow {
                            Button { model.gameFolder.explorerOpen(.addon(addon.file)) } label: {
                                Text(model.addonName(addon.file)).lineLimit(1).frame(width: 200, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .help("Show \(model.addonName(addon.file))'s settings across characters")
                            columns { id in
                                GridCell(cell: matrix.cell(addon.file, id), most: most)
                                    .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
                                    .onTapGesture { if matrix.cell(addon.file, id) != nil { model.gameFolder.explorerOpen(.characterAddon(id: id, file: addon.file)) } }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { if matrix.cell(addon.file, id) != nil { model.gameFolder.explorerOpen(.characterAddon(id: id, file: addon.file)) } }
                                    .help(help(addon.file, id))
                            }
                        }
                    }
                }
                ExplorerLegend()
            }
            .padding(Space.margin)
            .gridArea("explorer")
            // A document: start at the top left, however small the grid.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .defaultScrollAnchor(.topLeading)
    }

    /// One cell per character, with a divider column between megaservers (a stronger one between accounts).
    private func columns<Cell: View>(lines: Bool = true, @ViewBuilder _ cell: @escaping (String) -> Cell) -> some View {
        ForEach(Array(matrix.accounts.enumerated()), id: \.element.id) { i, account in
            if i > 0 { divider(strong: true).opacity(lines ? 1 : 0) }
            ForEach(Array(account.servers.enumerated()), id: \.element.id) { j, server in
                if j > 0 { divider(strong: false).opacity(lines ? 1 : 0) }
                ForEach(server.characters, id: \.self) { cell($0) }
            }
        }
    }

    /// A line down the row between two groups, reaching into the rows' spacing so it reads as one line.
    private func divider(strong: Bool) -> some View {
        Rectangle()
            .fill(strong ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.separator))
            .frame(width: strong ? 2 : 1)
            .padding(.vertical, -Space.xs / 2)
            .frame(width: Self.dividerWidth)
            .gridCellUnsizedAxes(.vertical)
    }

    private static let dividerWidth = Space.sm

    /// A heading over a group's columns, underlined to show which columns it covers.
    /// An account or megaserver over its characters' columns; clicking it opens its graph.
    private func span(_ title: String, characters: Int, dividers: Int, font: Font, help: String,
                      action: @escaping () -> Void) -> some View {
        let columns = characters + dividers
        return Button(action: action) {
            Text(title)
                .font(font)
                .foregroundStyle(hovered == title ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.bottom, Space.xs)
                .frame(width: CGFloat(characters) * 32 + CGFloat(dividers) * Self.dividerWidth + CGFloat(columns - 1) * Space.xs,
                       alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? title : (hovered == title ? nil : hovered) }
        .gridCellColumns(columns)
        .help(help)
    }

    private func help(_ file: String, _ id: String) -> String {
        guard let cell = matrix.cell(file, id) else { return String(localized: "\(model.addonName(file)) keeps nothing for \(model.gameFolder.characterTitle(id))") }
        return String(localized: "\(model.gameFolder.characterTitle(id)) in \(model.addonName(file)): \(String(localized: "\(cell.settings) settings"))")
            + (cell.odd > 0 ? String(localized: ", \(cell.odd) set differently from your other characters") : "")
    }
}

private struct GridCell: View {
    let cell: (settings: Int, odd: Int)?
    let most: Int

    var body: some View {
        ZStack {
            if let cell {
                RoundedRectangle(cornerRadius: Radius.cell)
                    .fill(Palette.accent.opacity(0.18 + 0.6 * Double(cell.settings) / Double(most)))
                if cell.odd > 0 {
                    RoundedRectangle(cornerRadius: Radius.cell).strokeBorder(Palette.counterpart, lineWidth: 2)
                    Text("\(cell.odd)").font(.caption2.weight(.bold)).foregroundStyle(Palette.onAccent)
                }
            } else {
                RoundedRectangle(cornerRadius: Radius.cell).strokeBorder(.separator)
            }
        }
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }
}

private struct ExplorerLegend: View {
    var body: some View {
        HStack(spacing: Space.lg) {
            item(String(localized: "Keeps settings for this character")) { RoundedRectangle(cornerRadius: Radius.bar).fill(Palette.accent.opacity(0.7)) }
            item(String(localized: "Some set differently")) { RoundedRectangle(cornerRadius: Radius.bar).strokeBorder(Palette.counterpart, lineWidth: 2) }
            item(String(localized: "Nothing saved")) { RoundedRectangle(cornerRadius: Radius.bar).strokeBorder(.separator) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func item(_ text: String, @ViewBuilder swatch: () -> some View) -> some View {
        Label { Text(text) } icon: { swatch().frame(width: 12, height: 12) }
    }
}

// MARK: - Addons as cards

// MARK: - One character

/// A character in the middle, the addons that keep their settings around them, badged where they're
/// set up differently; beside it, what's different and which addons keep settings only for them.
private struct CharacterConstellation: View {
    let model: AppModel
    let matrix: SettingsMatrix
    let id: String

    var body: some View {
        let addons = model.byName(matrix.addons.filter { $0.characters[id] != nil }, file: \.file)
        HStack(spacing: 0) {
            ZStack {
                ConnectionSpokes(
                    count: addons.count,
                    colors: addons.map { $0.oddOnesOut(id).isEmpty ? Palette.accent : Palette.counterpart },
                    widths: addons.map { $0.oddOnesOut(id).isEmpty ? 2 : 3 }
                )
                RadialLayout {
                    CenterNode(title: model.gameFolder.characterName(id), kind: characterHubLine(model, id),
                               id: id, symbol: "person.fill")
                    ForEach(addons) { addon in
                        let odd = addon.oddOnesOut(id).count
                        Button { model.gameFolder.explorerOpen(.characterAddon(id: id, file: addon.file)) } label: {
                            NodeLabel(title: model.addonName(addon.file),
                                      detail: odd > 0 ? String(localized: "\(addon.characters[id]?.count ?? 0) settings · \(odd) different") : String(localized: "\(addon.characters[id]?.count ?? 0) settings"),
                                      color: odd > 0 ? Palette.counterpart : Palette.accent,
                                      symbol: "puzzlepiece.extension.fill")
                        }
                        .buttonStyle(.plain)
                        .help("Show \(model.gameFolder.characterName(id))'s settings in \(model.addonName(addon.file))")
                    }
                }
            }
            .padding(Space.xl)
            Divider()
            sidePanel(addons)
                .frame(width: 320)
        }
    }

    private func sidePanel(_ addons: [SettingsMatrix.Addon]) -> some View {
        let odd = addons.flatMap { addon in addon.oddOnesOut(id).map { (addon: addon, item: $0) } }
        let only = matrix.onlyHere(id)
        let problems = model.gameFolder.findings(aboutCharacter: id, in: model.gameFolder.healthFindings)
        return List {
            if !problems.isEmpty {
                Section("Problems") {
                    ForEach(problems) { finding in
                        Button { model.gameFolder.showFinding(finding.id) } label: {
                            Label(finding.title, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Palette.accentText)
                        }
                        .buttonStyle(.plain)
                        .help("Show this on Problems")
                    }
                }
            }
            Section("Set Differently from Your Other Characters") {
                if odd.isEmpty { Text("Nothing: set up like your other characters.").foregroundStyle(.secondary) }
                ForEach(Array(odd.enumerated()), id: \.offset) { _, entry in
                    Button { model.gameFolder.explorerOpen(.setting(file: entry.addon.file, key: entry.item.key)) } label: {
                        VStack(alignment: .leading, spacing: Space.xs / 2) {
                            Text("\(model.addonName(entry.addon.file)) · \(entry.item.key)").lineLimit(1)
                            HStack(spacing: Space.xs) {
                                SettingValueView(display: model.gameFolder.display(entry.item.setting), label: entry.item.key)
                                Text("usually").foregroundStyle(.secondary)
                                SettingValueView(display: model.gameFolder.display(entry.item.usual), label: entry.item.key)
                            }
                            .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if !only.isEmpty {
                Section("Only This Character Has Settings In") {
                    ForEach(only, id: \.self) { file in Text(model.addonName(file)) }
                }
            }
            Section {
                Menu("Compare With…") {
                    CharacterMenuItems(matrix: matrix, excluding: id) { other in
                        Button(model.gameFolder.characterTitle(other)) { model.gameFolder.explorerOpen(.compare(id, other, file: nil)) }
                    }
                }
                .help("See every setting where this character and another differ")
                Button("Show Connections") { Task { await model.gameFolder.showConnections(SVTarget(.character, id)) } }
                Button("Find Everywhere") { Task { await model.gameFolder.findEverywhere(SVTarget(.character, id)) } }
            }
        }
    }
}

/// "NA · Nightblade 50", from a character ID.
@MainActor func characterLine(_ model: AppModel, _ id: String) -> String {
    if let bucket = model.gameFolder.usage?.characters.first(where: { $0.id == id }) { return characterLine(model, bucket) }
    return model.gameFolder.roster?[id]?.server ?? "character"
}

/// Class and level on their own line, so the hub can be read at a glance.
@MainActor func characterHubLine(_ model: AppModel, _ id: String) -> String {
    let parts = characterLine(model, id)
        .split(separator: "·")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    if parts.count >= 3 { return "\(parts[1])\n\(parts[0]) · \(parts[2])" }
    return parts.joined(separator: "\n")
}

// MARK: - One addon

/// An addon's settings across characters: what's shared, what's the same on every character, and the
/// settings set differently, each as a bar of its values.
private struct AddonAcrossCharacters: View {
    let model: AppModel
    let matrix: SettingsMatrix
    let file: String

    var body: some View {
        if let addon = matrix.addon(file) {
            let differing = addon.differing, same = addon.same, partial = addon.partial
            List {
                Section {
                    HStack(spacing: Space.xxl) {
                        stat(addon.characters.count, String(localized: "characters with settings"))
                        stat(addon.shared, String(localized: "shared by every character"))
                        stat(same.count, String(localized: "the same on every character"))
                        stat(partial.count, String(localized: "only on some"))
                        stat(differing.count, String(localized: "set differently"), highlight: !differing.isEmpty)
                    }
                    .padding(.vertical, Space.sm)
                }
                Section("Set Differently") {
                    if differing.isEmpty { Text("Every character has the same settings.").foregroundStyle(.secondary) }
                    ForEach(differing, id: \.self) { key in
                        Button { model.gameFolder.explorerOpen(.setting(file: file, key: key)) } label: {
                            ValueBar(model: model, label: key, groups: addon.values(of: key), total: addon.characters.count)
                        }
                        .buttonStyle(.plain)
                        .help("Show who has which value")
                    }
                }
                Section("The Same on Every Character") {
                    if same.isEmpty { Text("No setting is shared by every character.").foregroundStyle(.secondary) }
                    ForEach(same, id: \.self) { key in
                        if let setting = addon.values(of: key).first?.setting {
                            LabeledContent(key) { SettingValueView(display: model.gameFolder.display(setting), label: key) }
                        }
                    }
                }
                if !partial.isEmpty {
                    Section("Only on Some Characters") {
                        ForEach(partial, id: \.self) { key in
                            if let group = addon.values(of: key).first {
                                LabeledContent {
                                    SettingValueView(display: model.gameFolder.display(group.setting), label: key)
                                } label: {
                                    Text(key)
                                    Text(group.characters.map(model.gameFolder.characterName).joined(separator: ", ")).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func stat(_ n: Int, _ label: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(n.formatted()).font(.title2.weight(.semibold)).foregroundStyle(highlight ? AnyShapeStyle(Palette.counterpart) : AnyShapeStyle(.primary))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A setting's values as one bar, split by how many characters have each, with the values under it.
private struct ValueBar: View {
    let model: AppModel
    let label: String
    let groups: [SettingsMatrix.ValueGroup]
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label)
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { i, group in
                        Rectangle()
                            .fill(i == 0 ? Palette.accentFill : Palette.counterpart.opacity(0.35 + 0.5 / Double(i + 1)))
                            .frame(width: max(2, geo.size.width * CGFloat(group.characters.count) / CGFloat(max(total, 1)) - 1))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: Radius.bar))
            HStack(spacing: Space.md) {
                ForEach(Array(groups.prefix(4).enumerated()), id: \.offset) { _, group in
                    HStack(spacing: Space.xs) {
                        SettingValueView(display: model.gameFolder.display(group.setting), label: label)
                        Text("· \(group.characters.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.caption)
                }
                if groups.count > 4 { Text("and \(groups.count - 4) more").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, Space.xs)
        .contentShape(Rectangle())
    }
}

// MARK: - One character in one addon

private struct CharacterInAddon: View {
    let model: AppModel
    let matrix: SettingsMatrix
    let id: String
    let file: String

    var body: some View {
        if let addon = matrix.addon(file), let mine = addon.characters[id] {
            let odd = Dictionary(uniqueKeysWithValues: addon.oddOnesOut(id).map { ($0.key, $0.usual) })
            Form {
                Section {
                    ForEach(mine.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { key in
                        if let setting = mine[key] {
                            Button { model.gameFolder.explorerOpen(.setting(file: file, key: key)) } label: {
                                LabeledContent {
                                    VStack(alignment: .trailing, spacing: Space.xs / 2) {
                                        SettingValueView(display: model.gameFolder.display(setting), label: key)
                                        if let usual = odd[key] {
                                            HStack(spacing: Space.xs) {
                                                Text("usually").foregroundStyle(.secondary)
                                                SettingValueView(display: model.gameFolder.display(usual), label: key)
                                            }
                                            .font(.caption)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: Space.sm) {
                                        if odd[key] != nil {
                                            Image(systemName: "circle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(Palette.counterpart)
                                                .accessibilityLabel("Set differently")
                                        }
                                        Text(key)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Show who has which value")
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: Space.xs / 2) {
                        Text("\(model.gameFolder.characterName(id)) in \(model.addonName(file))")
                        Text("\(mine.count) settings, \(odd.count) set differently from your other characters. Click one to compare.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Menu("Compare With…") {
                        CharacterMenuItems(matrix: matrix, excluding: id, only: Set(addon.characters.keys)) { other in
                            Button(model.gameFolder.characterTitle(other)) {
                                model.gameFolder.explorerOpen(.compare(id, other, file: file))
                            }
                        }
                    }
                    .help("See every setting where this character and another differ in this addon")
                    .disabled(addon.characters.keys.filter { $0 != id }.isEmpty)
                    Button("Show in Inspector") {
                        Task { await model.gameFolder.reveal(file: file, path: model.gameFolder.characterTablePath(id, in: addon)) }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - One setting across characters

/// Each value of a setting, as a bar of how many characters have it, with those characters underneath.
private struct SettingAcrossCharacters: View {
    let model: AppModel
    let matrix: SettingsMatrix
    let file: String
    let key: String

    var body: some View {
        if let addon = matrix.addon(file) {
            let groups = addon.values(of: key)
            let total = max(1, groups.reduce(0) { $0 + $1.characters.count })
            // Characters in the grid's order: account, then megaserver, then name.
            let order = Dictionary(uniqueKeysWithValues: matrix.characterIDs.enumerated().map { ($1, $0) })
            List {
                Section {
                    Text("\(key) in \(model.addonName(file)): \(groups.count == 1 ? "the same for all \(total) characters" : "\(groups.count) values across \(total) characters").")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(groups.enumerated()), id: \.offset) { i, group in
                    Section {
                        HStack(spacing: Space.md) {
                            SettingValueView(display: model.gameFolder.display(group.setting), label: key)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: Radius.bar)
                                    .fill(i == 0 ? Palette.accentFill : Palette.counterpartFill)
                                    .frame(width: max(4, geo.size.width * CGFloat(group.characters.count) / CGFloat(total)))
                            }
                            .frame(height: 12)
                            Text("\(group.characters.count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Space.sm, alignment: .leading)],
                                  alignment: .leading, spacing: Space.sm) {
                            ForEach(group.characters.sorted { (order[$0] ?? 0) < (order[$1] ?? 0) }, id: \.self) { id in
                                Button { model.gameFolder.explorerOpen(.character(id)) } label: {
                                    HStack(spacing: Space.xs) {
                                        Initials(name: model.gameFolder.characterName(id))
                                        Text(model.gameFolder.characterName(id)).lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help("\(model.gameFolder.characterTitle(id)): show their settings across addons")
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct Initials: View {
    let name: String
    var color: Color = Palette.accentText
    var wash: Color = Palette.accentWash

    var body: some View {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
        Text(String((words.count > 1 ? [words[0], words[words.count - 1]] : words).compactMap(\.first)).uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
            .background(wash, in: Circle())
    }
}

// MARK: - Accounts and megaservers (S-061)

/// An account in the middle with the megaservers it has characters on around it. Click one for its characters.
private struct AccountConstellation: View {
    let model: AppModel
    let matrix: SettingsMatrix
    let account: String

    var body: some View {
        let servers = matrix.accounts.first { $0.account == account }?.servers ?? []
        let characters = servers.reduce(0) { $0 + $1.characters.count }
        ZStack {
            ConnectionSpokes(count: servers.count, colors: servers.map { _ in Palette.accent }, widths: servers.map { _ in 2 })
            RadialLayout {
                CenterNode(title: account, kind: String(localized: "Account\n\(String(localized: "\(characters) characters"))"),
                           symbol: "person.2.fill")
                ForEach(servers) { server in
                    Button { model.gameFolder.explorerOpen(.server(account: account, server: server.server)) } label: {
                        NodeLabel(title: server.server, detail: String(localized: "\(server.characters.count) characters"),
                                  color: Palette.accent, symbol: "globe")
                    }
                    .buttonStyle(.plain)
                    .help("Show the characters of \(account) on \(server.server)")
                }
            }
        }
        .padding(Space.xl)
        .overlay {
            if servers.isEmpty {
                ContentUnavailableView("No Characters", systemImage: "person.2",
                                       description: Text("No addon keeps settings for a character on this account."))
            }
        }
    }
}

/// One account's characters on one megaserver, around it. Click one for their addons.
private struct ServerConstellation: View {
    let model: AppModel
    let matrix: SettingsMatrix
    let account: String
    let server: String

    var body: some View {
        let ids = matrix.accounts.first { $0.account == account }?.servers.first { $0.server == server }?.characters ?? []
        ZStack {
            ConnectionSpokes(count: ids.count, colors: ids.map { _ in Palette.accent }, widths: ids.map { _ in 2 })
            RadialLayout {
                CenterNode(title: server, kind: "\(account)\n\(String(localized: "\(ids.count) characters"))", symbol: "globe")
                ForEach(ids, id: \.self) { id in
                    Button { model.gameFolder.explorerOpen(.character(id)) } label: {
                        NodeLabel(title: model.gameFolder.characterName(id), detail: characterLine(model, id), color: Palette.accent, symbol: "person.fill")
                    }
                    .buttonStyle(.plain)
                    .help("\(model.gameFolder.characterTitle(id)): show their settings across addons")
                }
            }
        }
        .padding(Space.xl)
        .overlay {
            if ids.isEmpty {
                ContentUnavailableView("No Characters", systemImage: "person",
                                       description: Text("No addon keeps settings for a character of this account on this megaserver."))
            }
        }
    }
}

// MARK: - Two characters

/// Two characters side by side, each in their own color: every setting, across every addon (or one addon when
/// `file` is set), where they differ, then the settings only one of them has. A button with a character's name
/// gives their value to the other.
private struct CompareCharacters: View {
    let model: AppModel
    let matrix: SettingsMatrix
    let a: String
    let b: String
    /// When set, only this addon's SavedVariables file (S-066).
    var file: String? = nil
    @State private var onlyDifferences = true
    /// The window's, so Edit › Undo puts back what a copy wrote.
    @Environment(\.undoManager) private var undoManager

    private func other(_ id: String) -> String { id == a ? b : a }
    private func name(_ id: String) -> String { model.gameFolder.compareName(id, other: other(id)) }
    private func color(_ id: String) -> Color { id == a ? Palette.accentText : Palette.counterpart }
    private func wash(_ id: String) -> Color { id == a ? Palette.accentWash : Palette.counterpartWash }
    private func copyAll(from: String, to: String) -> [(file: String, key: String)] {
        model.gameFolder.copyAllRows(from: from, to: to, file: file)
    }

    var body: some View {
        let all = matrix.compare(a, b)
        let scoped = file.map { f in all.filter { $0.file == f } } ?? all
        let comparisons = model.byName(scoped, file: \.file)
        let differing = comparisons.reduce(0) { $0 + $1.differing.count }
        List {
            Section {
                HStack(alignment: .top, spacing: 0) {
                    Color.clear.frame(width: 240 + Space.lg, height: 1)
                    person(a)
                    person(b)
                }
                // The summary, with the title of the column the Clone All buttons sit in, like each addon's heading.
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(summary(differing: differing, addonCount: comparisons.filter { !$0.differing.isEmpty }.count))
                        .foregroundStyle(.secondary)
                        .frame(width: Self.buttonsOffset, alignment: .leading)
                    Text("Clone all from")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    Toggle("Only differences", isOn: $onlyDifferences)
                        .toggleStyle(.checkbox)
                        .help("Hide settings that only one character has, and keep the side-by-side differences")
                        .frame(width: Self.buttonsOffset, alignment: .leading)
                    HStack(spacing: Space.sm) {
                        cloneButton(a)
                        cloneButton(b)
                    }
                }
            }
            ForEach(comparisons.filter { !$0.differing.isEmpty }) { c in
                Section {
                    ForEach(c.differing, id: \.key) { row in
                        HStack(spacing: 0) {
                            Button { model.gameFolder.explorerOpen(.setting(file: c.file, key: row.key)) } label: {
                                Text(row.key).frame(width: 240, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Show who has which value")
                            .padding(.trailing, Space.lg)
                            cell(a, SettingValueView(display: model.gameFolder.display(row.a), label: row.key))
                            cell(b, SettingValueView(display: model.gameFolder.display(row.b), label: row.key))
                            HStack(spacing: Space.sm) {
                                copyButton(file: c.file, key: row.key, from: a)
                                copyButton(file: c.file, key: row.key, from: b)
                            }
                            .padding(.leading, Space.md)
                        }
                    }
                } header: {
                    // The addon over the names, and over the buttons what they do.
                    HStack(spacing: 0) {
                        Text(model.addonName(c.file)).frame(width: Self.buttonsOffset, alignment: .leading)
                        Text("Clone row from")
                    }
                }
            }
            if !onlyDifferences {
                only(a, comparisons.flatMap { c in c.onlyA.map { (c.file, $0.key, $0.setting) } })
                only(b, comparisons.flatMap { c in c.onlyB.map { (c.file, $0.key, $0.setting) } })
            }
        }
        .frame(maxWidth: 1040, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { model.gameFolder.cloneSource != nil }, set: { if !$0 { model.gameFolder.cloneSource = nil } })) {
            if let source = model.gameFolder.cloneSource {
                Button("Back Up and Copy") {
                    let rows = copyAll(from: source, to: other(source))
                    Task { await model.gameFolder.copySettings(rows, from: source, to: other(source), undoManager: undoManager) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let source = model.gameFolder.cloneSource {
                if let file {
                    Text("The values of \(name(other(source))) are replaced in \(model.addonName(file)). MacMinion backs up first; restore the backup to undo.")
                } else {
                    Text("The values of \(name(other(source))) are replaced in each addon's SavedVariables file. MacMinion backs up first; restore the backup to undo.")
                }
            }
        }
    }

    private func summary(differing: Int, addonCount: Int) -> String {
        if differing == 0 {
            if let file { return String(localized: "These two are set up the same in \(model.addonName(file)).") }
            return String(localized: "These two are set up the same in every addon they share.")
        }
        if let file {
            return String(localized: "\(String(localized: "\(differing) settings differ")) in \(model.addonName(file)).")
        }
        return String(localized: "\(String(localized: "\(differing) settings differ")) across \(addonCount) addons.")
    }

    private var confirmTitle: String {
        guard let source = model.gameFolder.cloneSource else { return "" }
        let count = copyAll(from: source, to: other(source)).count
        return String(localized: "Copy \(String(localized: "\(count) settings")) from \(name(source)) to \(name(other(source)))?")
    }

    /// Where the name buttons start: the setting's name, then two value cells (each with its padding).
    static let buttonsOffset: CGFloat = 240 + Space.lg + 2 * (200 + 3 * Space.sm) + Space.md

    /// One character's value in their column's color.
    private func cell(_ id: String, _ value: some View) -> some View {
        value
            .frame(width: 200, alignment: .leading)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .background(wash(id), in: .rect(cornerRadius: Radius.small))
            .padding(.trailing, Space.sm)
    }

    /// "Clone Masisi (NA)…": every difference from this character to the other, after a question.
    private func cloneButton(_ id: String) -> some View {
        let rows = copyAll(from: id, to: other(id))
        // The same small button as on each row; it asks before it clones.
        return Button(name(id)) { model.gameFolder.cloneSource = id }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(color(id))
            .disabled(rows.isEmpty || model.gameIsRunning || model.backupBusy != nil)
            .help(model.gameIsRunning ? String(localized: "Quit Elder Scrolls Online first")
                  : String(localized: "Give \(name(other(id))) every value of \(name(id)) that differs (\(id == a ? "Control-Option-Command-Left Arrow" : "Control-Option-Command-Right Arrow"))"))
    }

    /// A button with a character's name, in their color: gives their value of this setting to the other.
    /// Off where the other keeps nothing in that addon to put it under.
    private func copyButton(file: String, key: String, from: String) -> some View {
        let to = other(from)
        let place = model.gameFolder.copyTarget(file: file, key: key, from: from, to: to)
        return Button(name(from)) {
            Task { await model.gameFolder.copySettings([(file, key)], from: from, to: to, undoManager: undoManager) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(color(from))
        .disabled(place == nil || model.gameIsRunning || model.backupBusy != nil)
        .help(place == nil ? String(localized: "\(name(to)) keeps nothing in this addon to put it under")
              : model.gameIsRunning ? String(localized: "Quit Elder Scrolls Online first")
              : String(localized: "Copy the value of \(name(from)) to \(name(to))"))
    }

    private func person(_ id: String) -> some View {
        Button { model.gameFolder.explorerOpen(.character(id)) } label: {
            HStack(spacing: Space.sm) {
                Initials(name: model.gameFolder.characterName(id), color: color(id), wash: wash(id))
                VStack(alignment: .leading, spacing: 0) {
                    Text(name(id)).font(.headline).foregroundStyle(color(id))
                    Text(characterLine(model, id)).font(.caption).foregroundStyle(.secondary)
                    Text(id).font(.caption.monospacedDigit()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .frame(width: 200, alignment: .leading)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .background(wash(id), in: .rect(cornerRadius: Radius.small))
            .padding(.trailing, Space.sm)
        }
        .buttonStyle(.plain)
        .help("\(model.gameFolder.characterTitle(id)): show their settings across addons")
    }

    @ViewBuilder
    private func only(_ id: String, _ rows: [(String, String, SettingsMatrix.Setting)]) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    LabeledContent {
                        HStack(spacing: Space.lg) {
                            SettingValueView(display: model.gameFolder.display(row.2), label: row.1)
                            copyButton(file: row.0, key: row.1, from: id)
                        }
                    } label: {
                        Text(row.1)
                        Text(model.addonName(row.0))
                    }
                }
            } header: {
                Text("Only \(name(id)) Has").foregroundStyle(color(id))
            }
        }
    }
}

/// Picks two characters to compare, from the menu bar.
private struct CompareChooser: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var a = ""
    @State private var b = ""

    var body: some View {
        let ids = model.gameFolder.matrix?.characterIDs ?? []
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Compare Two Characters").font(.title2.bold())
            Form {
                picker(String(localized: "First"), $a, ids)
                picker(String(localized: "Second"), $b, ids)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Compare") {
                    model.gameFolder.tab = .characters
                    model.gameFolder.explorerPath = [.grid, .compare(a, b, file: nil)]
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(a.isEmpty || b.isEmpty || a == b)
            }
        }
        .padding(Space.xxl)
        .frame(width: 440)
        .fitsContent()
        .noInitialFocus()
        .onAppear {
            a = ids.first ?? ""
            b = ids.dropFirst().first ?? ""
        }
    }

    @ViewBuilder
    private func picker(_ title: String, _ selection: Binding<String>, _ ids: [String]) -> some View {
        if let matrix = model.gameFolder.matrix {
            Picker(title, selection: selection) {
                CharacterMenuItems(matrix: matrix) { Text(model.gameFolder.characterTitle($0)).tag($0) }
            }
        }
    }
}

/// Characters for a menu or picker, in sections by account and megaserver.
private struct CharacterMenuItems<Item: View>: View {
    let matrix: SettingsMatrix
    var excluding: String?
    /// When set, only these character IDs (e.g. who have settings in one addon).
    var only: Set<String>? = nil
    @ViewBuilder let item: (String) -> Item

    var body: some View {
        ForEach(matrix.accounts) { account in
            ForEach(account.servers) { server in
                let ids = server.characters.filter { $0 != excluding && (only?.contains($0) ?? true) }
                if !ids.isEmpty {
                    Section("\(account.account) · \(SettingsMatrix.shortServer(server.server))") {
                        ForEach(ids, id: \.self) { item($0) }
                    }
                }
            }
        }
    }
}
