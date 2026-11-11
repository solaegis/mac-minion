import Foundation
import MacMinionKit

/// Characters and Addons: where the explorer is, names, Compare, and Copy Settings (S-053 to S-060).
extension GameFolderModel {
    func explorerOpen(_ level: ExplorerLevel) { explorerPath.append(level) }

    func explorerBack() {
        if explorerPath.count > 1 { explorerPath.removeLast() }
    }

    /// Starts the explorer over at the Characters or Addons tab's top level.
    func explorerReset() {
        explorerPath = [.grid]
    }

    func characterName(_ id: String) -> String { names?.characters[id]?.name ?? SVName.unknownCharacter }

    /// "Masisi (8796093036412335)": the name people know, with the ID that tells two Masisis apart.
    func characterTitle(_ id: String) -> String { "\(characterName(id)) (\(id))" }

    /// Every SavedVariables file an installed addon or the game saves, by the name people know.
    var addonCardFiles: [String] {
        savedVariables.filter { file in
            switch file.owner { case .addon, .game: file.name.hasSuffix(".lua"); default: false }
        }
        .map { (file: $0.name, title: app.addonName($0.name)) }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        .map(\.file)
    }

    /// The readable form of a saved setting.
    func display(_ setting: SettingsMatrix.Setting) -> SVDisplay {
        SVReadable.display(setting.value, key: setting.key, at: Array(setting.path.dropLast()), names: names)
    }

    /// The character's own table in a file, from any of their settings' paths, to open in the Inspector.
    func characterTablePath(_ id: String, in addon: SettingsMatrix.Addon) -> [LuaKey] {
        guard let path = addon.characters[id]?.values.first?.path else { return [] }
        let name = characterName(id)
        guard let i = path.firstIndex(where: { $0.description == id || $0.description.split(separator: "^").first.map(String.init) == name }) else {
            return Array(path.dropLast())
        }
        return Array(path.prefix(through: i))
    }

    /// The two characters Compare shows, in its order.
    var comparedCharacters: (String, String)? {
        guard app.sidebar == .gameFolder, tab == .characters, case .compare(let a, let b)? = explorerPath.last else { return nil }
        return (a, b)
    }

    /// A character's name in Compare, with their megaserver when the other has the same name: "Masisi (NA)".
    func compareName(_ id: String, other: String) -> String {
        let name = characterName(id)
        guard name == characterName(other) else { return name }
        let server = roster?[id]?.server ?? matrix?.homes[id]?.server
        guard let server, server != "Default" else { return name }
        return "\(name) (\(SettingsMatrix.shortServer(server)))"
    }

    /// Where a setting of `from` goes for `to`, or nil when `to` keeps nothing in that addon's table to put it under.
    func copyTarget(file: String, key: String, from: String, to: String) -> [LuaKey]? {
        matrix?.target(file: file, key: key, from: from, to: to)
    }

    /// Every differing setting Copy All copies, from `from` to `to`, that has a place to go.
    func copyAllRows(from: String, to: String) -> [(file: String, key: String)] {
        guard let matrix = matrix else { return [] }
        return matrix.compare(from, to).flatMap { c in c.differing.map { (c.file, $0.key) } }
            .filter { copyTarget(file: $0.file, key: $0.key, from: from, to: to) != nil }
    }

    /// Writes `from`'s values for these settings into `to`'s place in each addon's file (S-060). ESO must be
    /// closed: it writes its own copy when it quits. Backs up first, once per pair of characters a run.
    func copySettings(_ rows: [(file: String, key: String)], from: String, to: String, undoManager: UndoManager? = nil) async {
        message = nil
        errorMessage = nil
        guard !app.gameIsRunning else {
            errorMessage = String(localized: "Quit Elder Scrolls Online first: it writes its own copy of these files when it quits.")
            return
        }
        guard let matrix = matrix else { return }
        let byFile = matrix.copyChanges(rows, from: from, to: to)
        guard !byFile.isEmpty else { return }
        let pair = [from, to].sorted().joined(separator: "|")
        if !copyBackedUp.contains(pair) {
            await app.backUp()
            if let backupError = app.backupError {
                errorMessage = String(localized: "Nothing was copied. \(backupError)")
                return
            }
            copyBackedUp.insert(pair)
        }
        let urls = Dictionary(savedVariables.map { ($0.name, $0.url) }, uniquingKeysWith: { a, _ in a })
        let edits = await SVEdit.apply(toFiles: Dictionary(byFile.compactMap { file, changes in urls[file].map { ($0, changes) } },
                                                           uniquingKeysWith: +))
        if let last = edits.failures.last {
            errorMessage = String(localized: "\(last.file) wasn't changed: \(last.why)")
        }
        registerFileUndo(before: edits.before, after: edits.after, name: String(localized: "Copy Settings"), undoManager: undoManager)
        let copied = edits.changed
        if copied > 0 {
            let settings = String(localized: "\(copied) settings")
            message = String(localized: "Backed up, then copied \(settings) from \(characterName(from)) to \(characterName(to)).")
        }
        // The matrix reads the files again, so Compare shows what's now the same.
        await scan()
        await load()
    }

    /// What each addon keeps about a character, largest first, with the place to open.
    func characterPlaces(_ bucket: SVUsage.Bucket) async -> [CharacterPlace] {
        let found = await findResults([SVTarget(.character, bucket.id)], perTarget: 2_000).first
        let tops = topFolders ?? [:]
        return bucket.byFile.map { entry in
            let base = String(entry.file.dropLast(4))
            let folder = base.hasPrefix("ZO_") ? "ZO_" : tops[base.lowercased()] ?? base
            // The shortest path is the character's own table, not something deep inside it.
            let path = found?.files.first { $0.file == entry.file }?.rows.map(\.path).min { $0.count < $1.count } ?? []
            return CharacterPlace(file: entry.file, addon: app.addonTitle(folder: folder), bytes: entry.bytes, path: path)
        }
    }
}
