import Foundation
import MacMinionKit

/// Settings as you'd read them (S-050): the table shown as sections, one on screen at a time.
extension GameFolderModel {
    /// The file and table the Inspector shows, as one string.
    var readablePlace: String {
        "\(inspectorFile ?? "")|\(SVNode.id(inspectorFocus))"
    }

    /// Changes when the sections must be built again: another file or table, new names, or new places for characters.
    var readableBuildKey: String {
        "\(readablePlace)|\(names != nil)|\(inspectorSourceNamesRevision)|\(roster?.count ?? -1)|\(matrix?.homes.count ?? -1)"
    }

    /// False while the sections on hand belong to another file or table.
    var readableReady: Bool { readableBuiltFor == readablePlace }

    var readableSections: [SVReadable.Section] { readableGroups.flatMap(\.sections) }

    /// Every outline row, in the order shown.
    var readableRows: [SVReadable.OutlineRow] { readableOutline.flatMap(\.rows) }

    /// The outline row on screen: the one chosen, or the first.
    var readableShownRow: SVReadable.OutlineRow? {
        let rows = readableRows
        return rows.first { $0.id == readableSection } ?? rows.first
    }

    /// The section on screen: the chosen row's, or the first.
    var readableShownSection: SVReadable.Section? {
        let sections = readableSections
        guard let row = readableShownRow else { return sections.first }
        return sections.first { $0.id == row.sectionID } ?? sections.first
    }

    /// "Shared with EU Masisi": the other characters a Default table keyed by name belongs to, seen from the row shown.
    var readableSharedNote: String? {
        guard let section = readableShownSection, !section.sharedWith.isEmpty else { return nil }
        let here = readableShownRow?.megaserver
        let others = section.sharedWith.keys.filter { $0 != here }.sorted().map(SettingsMatrix.shortServer)
        guard !others.isEmpty else { return nil }
        return String(localized: "Shared with \(others.formatted(.list(type: .and))) \(section.rowTitle)")
    }

    /// Builds the sections for the table shown, off the main thread. New names replace the sections
    /// in place and keep the section on screen.
    func buildReadable() async {
        readableGeneration += 1
        let generation = readableGeneration
        let place = readablePlace
        let doc = inspectorDocument, path = inspectorFocus, names = names, locations = characterLocations
        let source = inspectorFile.flatMap { inspectorSourceNames[$0] }
        let title = inspectorFile.map { String($0.dropLast(4)) } ?? ""
        let (built, outline) = await Task.detached {
            let sections = SVReadable.sheet(Self.entries(in: doc, at: path), at: path, title: title, names: names, source: source,
                                            locations: locations)
            return (SVReadable.grouped(sections), SVReadable.outline(sections))
        }.value
        guard generation == readableGeneration else { return }
        if readableGroups != built { readableGroups = built }
        if readableOutline != outline { readableOutline = outline }
        readableBuiltFor = place
        let ids = outline.flatMap(\.rows).map(\.id)
        if let remembered = readableRemembered[place], ids.contains(remembered) {
            if readableSection != remembered { readableSection = remembered }
        } else if readableSection.map(ids.contains) != true {
            readableSection = ids.first
        }
    }

    /// Shows the section after (1) or before (-1) the one on screen.
    /// Rows Next and Previous Section step through: those in open folders, in the order shown.
    private var readableVisibleRows: [SVReadable.OutlineRow] {
        readableOutline.flatMap { account in
            account.loose + account.folders.filter { !readableCollapsed.contains($0.id) }.flatMap(\.rows)
        }
    }

    func readableStep(_ by: Int) {
        let ids = readableVisibleRows.map(\.id)
        guard let at = ids.firstIndex(of: readableShownRow?.id ?? ""), ids.indices.contains(at + by) else { return }
        readableSection = ids[at + by]
    }

    func canReadableStep(_ by: Int) -> Bool {
        let ids = readableVisibleRows.map(\.id)
        guard readableReady, let at = ids.firstIndex(of: readableShownRow?.id ?? "") else { return false }
        return ids.indices.contains(at + by)
    }

    /// Entries of the table at `path`, sorted like the tree's rows.
    nonisolated static func entries(in doc: SVDocument?, at path: [LuaKey]) -> [LuaEntry] {
        guard let doc else { return [] }
        let raw: [LuaEntry]
        if path.isEmpty {
            raw = doc.variables
        } else {
            var value = doc.variables.first { $0.key == path[0] }?.value
            for key in path.dropFirst() {
                value = value?.table?[key]
            }
            raw = value?.table?.entries ?? []
        }
        return raw.sorted { LuaKey.displayOrder($0.key, $1.key) }
    }
}
