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

    /// The section on screen: the one chosen, or the first.
    var readableShownSection: SVReadable.Section? {
        let sections = readableSections
        return sections.first { $0.id == readableSection } ?? sections.first
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
        let built = await Task.detached {
            SVReadable.grouped(SVReadable.sheet(Self.entries(in: doc, at: path), at: path, title: title, names: names, source: source,
                                                  locations: locations))
        }.value
        guard generation == readableGeneration else { return }
        if readableGroups != built { readableGroups = built }
        readableBuiltFor = place
        let ids = built.flatMap(\.sections).map(\.id)
        if let remembered = readableRemembered[place], ids.contains(remembered) {
            if readableSection != remembered { readableSection = remembered }
        } else if readableSection.map(ids.contains) != true {
            readableSection = ids.first
        }
    }

    /// Shows the section after (1) or before (-1) the one on screen.
    func readableStep(_ by: Int) {
        let ids = readableSections.map(\.id)
        guard let at = ids.firstIndex(of: readableShownSection?.id ?? ""), ids.indices.contains(at + by) else { return }
        readableSection = ids[at + by]
    }

    func canReadableStep(_ by: Int) -> Bool {
        let ids = readableSections.map(\.id)
        guard readableReady, let at = ids.firstIndex(of: readableShownSection?.id ?? "") else { return false }
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
