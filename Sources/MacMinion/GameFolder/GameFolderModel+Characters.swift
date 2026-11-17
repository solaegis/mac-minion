import Foundation
import MacMinionKit

/// Characters and Addons: where the explorer is, names, Compare, and Copy Settings (S-053 to S-060).
extension GameFolderModel {
    func explorerOpen(_ level: ExplorerLevel) {
        clearCloneSelectionIfLeavingCompare(to: level)
        explorerPath.append(level)
    }

    func explorerBack() {
        if explorerPath.count > 1 {
            explorerPath.removeLast()
            if comparedCharacters == nil { clearCloneSelection() }
        }
    }

    /// Starts the explorer over at the Characters or Addons tab's top level.
    func explorerReset() {
        clearCloneSelection()
        explorerPath = [.grid]
    }

    /// Back on the Characters tab after the Inspector or another tab: where you were, trimmed to the deepest
    /// level that still exists after a rescan (a character or addon file can go away).
    func explorerResume() {
        guard let matrix else { return }
        let ids = Set(matrix.characterIDs), files = Set(matrix.addons.map(\.file))
        func exists(_ level: ExplorerLevel) -> Bool {
            switch level {
            case .grid: true
            case .character(let id): ids.contains(id)
            case .addon(let file): files.contains(file)
            case .characterAddon(let id, let file): ids.contains(id) && files.contains(file)
            case .setting(let file, _): files.contains(file)
            case .compare(let a, let b, let file): ids.contains(a) && ids.contains(b) && (file.map(files.contains) ?? true)
            case .account(let account): matrix.accounts.contains { $0.account == account }
            case .server(let account, let server):
                matrix.accounts.first { $0.account == account }?.servers.contains { $0.server == server } == true
            }
        }
        let kept = Array(explorerPath.prefix { exists($0) })
        guard kept != explorerPath else { return }
        if comparedCharacters != nil { clearCloneSelection() }
        explorerPath = kept.isEmpty ? [.grid] : kept
    }

    func clearCloneSelection() {
        cloneSources = [:]
        cloneConfirmPending = false
    }

    private func clearCloneSelectionIfLeavingCompare(to level: ExplorerLevel) {
        if case .compare = level { return }
        if case .compare = explorerPath.last { clearCloneSelection() }
    }

    /// Every character's account and megaserver: the companion's roster, the tables keyed by their ID, then the ID.
    var characterLocations: CharacterLocations { CharacterLocations(roster: roster, homes: matrix?.homes ?? [:]) }

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
        let parent = Array(setting.path.dropLast())
        return SVReadable.display(setting.value, key: setting.key, at: parent, names: names,
                                  control: sourceNames(for: setting)?.control(for: setting.key, at: parent))
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
        guard app.sidebar == .gameFolder, tab == .characters, case .compare(let a, let b, _)? = explorerPath.last else { return nil }
        return (a, b)
    }

    /// The addon file scoped Compare is limited to, or nil for every addon (S-066).
    var comparedFile: String? {
        guard app.sidebar == .gameFolder, tab == .characters, case .compare(_, _, let file)? = explorerPath.last else { return nil }
        return file
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
    /// When `file` is set, only that addon's differences (S-066).
    func copyAllRows(from: String, to: String, file: String? = nil) -> [(file: String, key: String)] {
        guard let matrix = matrix else { return [] }
        let shown = matrix.compare(from, to).filter { c in
            app.prefs.showAllAddons || c.file == file
                || (!c.isGame && matrix.addon(c.file).map { $0.profile(from) == .own || $0.profile(to) == .own } == true)
        }
        let comparisons = file.map { f in shown.filter { $0.file == f } } ?? shown
        return comparisons.flatMap { c in c.differing.map { (c.file, $0.key) } }
            .filter { copyTarget(file: $0.file, key: $0.key, from: from, to: to) != nil }
    }

    /// Selected Compare radios as clone ops between the two compared characters.
    func selectedCloneOps() -> [SettingsMatrix.CloneOp] {
        guard let (a, b) = comparedCharacters else { return [] }
        return cloneSources.compactMap { row, from in
            let to = from == a ? b : a
            guard from == a || from == b else { return nil }
            return SettingsMatrix.CloneOp(file: row.file, key: row.key, from: from, to: to)
        }
    }

    /// How many selected ops would remove a key on the destination.
    func selectedCloneDeletions() -> Int {
        guard let matrix else { return 0 }
        return selectedCloneOps().filter { $0.file != AddOnChoices.fileName && matrix.cloneOpDeletes($0) }.count
    }

    /// Writes `from`'s values for these settings into `to`'s place in each addon's file (S-060). ESO must be
    /// closed: it writes its own copy when it quits. Backs up first, once per pair of characters a run.
    func copySettings(_ rows: [(file: String, key: String)], from: String, to: String) async {
        let ops = rows.map { SettingsMatrix.CloneOp(file: $0.file, key: $0.key, from: from, to: to) }
        await applyCloneOps(ops)
    }

    /// Applies Compare Clone ops after one backup (S-060): settings rows go to SavedVariables, addon rows
    /// (`AddOnSettings.txt`) turn addons on or off for the other character (S-069). One Edit › Undo takes all back.
    func applyCloneOps(_ ops: [SettingsMatrix.CloneOp]) async {
        message = nil
        errorMessage = nil
        guard !app.gameIsRunning else {
            errorMessage = String(localized: "Quit Elder Scrolls Online first: it writes its own copy of these files when it quits.")
            return
        }
        let svOps = ops.filter { $0.file != AddOnChoices.fileName }
        let byFile = svOps.isEmpty ? [:] : matrix?.cloneChanges(svOps) ?? [:]
        let addOnChanges = addOnChanges(ops.filter { $0.file == AddOnChoices.fileName })
        guard !byFile.isEmpty || !addOnChanges.isEmpty else { return }
        if !addOnChanges.isEmpty, gameSettingsEdits(.addOns) > 0 {
            errorMessage = String(localized: "Nothing was cloned. Save or revert your edits to AddOnSettings.txt on Game Settings first.")
            return
        }
        let characters = Set(ops.flatMap { [$0.from, $0.to] })
        let pair = characters.sorted().joined(separator: "|")
        if !copyBackedUp.contains(pair) {
            await app.backUp()
            if let backupError = app.backupError {
                errorMessage = String(localized: "Nothing was copied. \(backupError)")
                return
            }
            copyBackedUp.insert(pair)
        }
        var before: [URL: Data] = [:], after: [URL: Data] = [:]
        var parts: [String] = []
        var deleted = 0
        if !byFile.isEmpty {
            let urls = Dictionary(savedVariables.map { ($0.name, $0.url) }, uniquingKeysWith: { a, _ in a })
            let edits = await SVEdit.apply(toFiles: Dictionary(byFile.compactMap { file, changes in urls[file].map { ($0, changes) } },
                                                               uniquingKeysWith: +))
            if let last = edits.failures.last {
                errorMessage = String(localized: "\(last.file) wasn't changed: \(last.why)")
            }
            before.merge(edits.before) { a, _ in a }
            after.merge(edits.after) { _, b in b }
            if edits.changed > 0 {
                parts.append(String(localized: "\(edits.changed) settings"))
                deleted = byFile.values.flatMap { $0 }.filter(\.removes).count
            }
        }
        if !addOnChanges.isEmpty {
            let url = app.gameFolderURL.appending(path: AddOnChoices.fileName)
            do {
                let old = try Data(contentsOf: url)
                let new = GameSettingsFile.parse(old, kind: .addOns).settingAddOns(addOnChanges)
                try new.write(to: url, options: .atomic)
                before[url] = old
                after[url] = new
                parts.append(String(localized: "\(addOnChanges.values.reduce(0) { $0 + $1.count }) addon choices"))
            } catch {
                errorMessage = String(localized: "\(AddOnChoices.fileName) wasn't changed: \(error.localizedDescription)")
            }
            loadGameSettings()
        }
        registerFileUndo(before: before, after: after, name: String(localized: "Copy Settings"))
        if !parts.isEmpty {
            let settings = parts.formatted(.list(type: .and))
            if deleted > 0 {
                let removals = String(localized: "\(deleted) keys removed")
                message = String(localized: "Backed up, then cloned \(settings) (\(removals)).")
            } else {
                message = String(localized: "Backed up, then cloned \(settings).")
            }
        }
        clearCloneSelection()
        // The matrix reads the files again, so Compare shows what's now the same.
        await scan()
        await load()
    }

    // MARK: Addon choices (S-069)

    /// Which addons each character loads, from AddOnSettings.txt as last read.
    var addOnChoices: AddOnChoices? { gameSettings[.addOns].map(AddOnChoices.init) }

    /// The block in AddOnSettings.txt that's this character's ("NA Megaserver-Masisi"), or nil when their
    /// megaserver or name isn't known.
    func addOnHeader(_ id: String) -> String? {
        let name = characterName(id)
        guard name != SVName.unknownCharacter, !name.isEmpty, let server = characterLocations.location(id).megaserver else { return nil }
        return AddOnChoices.header(server: server, name: name)
    }

    /// What a character's list says about an addon: on, off, or nil when it doesn't name it.
    func addOnValue(_ id: String, addon: String) -> Bool? {
        guard let header = addOnHeader(id) else { return nil }
        return addOnChoices?.effective(for: header).choices[addon]
    }

    /// The character has no block of their own, so `#Default` decides what they load.
    func addOnsFromDefault(_ id: String) -> Bool {
        guard let header = addOnHeader(id) else { return false }
        return addOnChoices?.effective(for: header).fromDefault ?? false
    }

    /// Every addon either character's list names, or nil when either one's list can't be found.
    func addOnRows(_ a: String, _ b: String) -> [AddOnChoices.Row]? {
        guard let choices = addOnChoices, let ha = addOnHeader(a), let hb = addOnHeader(b) else { return nil }
        return choices.compare(ha, hb)
    }

    /// `from` names the addon and `to` loads it differently, so cloning it changes something.
    func canCloneAddOn(_ addon: String, from: String, to: String) -> Bool {
        guard let value = addOnValue(from, addon: addon), addOnHeader(to) != nil else { return false }
        return addOnValue(to, addon: addon) != value
    }

    /// What Clone writes to AddOnSettings.txt for these rows, by the destination's block header.
    func addOnChanges(_ ops: [SettingsMatrix.CloneOp]) -> [String: [String: Bool]] {
        var out: [String: [String: Bool]] = [:]
        for op in ops where canCloneAddOn(op.key, from: op.from, to: op.to) {
            guard let to = addOnHeader(op.to), let on = addOnValue(op.from, addon: op.key) else { continue }
            out[to, default: [:]][op.key] = on
        }
        return out
    }

    /// Opens Compare with `from` picked as the source on every addon row that differs, so Clone copies
    /// their whole list of addons to `to`.
    func copyAddOnChoices(from: String, to: String) {
        loadGameSettings()
        explorerOpen(.compare(to, from, file: nil))
        for row in addOnRows(to, from) ?? [] where canCloneAddOn(row.addon, from: from, to: to) {
            cloneSources[CloneRowID(file: AddOnChoices.fileName, key: row.addon)] = from
        }
    }

    /// What each addon keeps about a character, largest first, with the place to open.
    func characterPlaces(_ bucket: SVUsage.Bucket) async -> [CharacterPlace] {
        // A name bucket ("@acct|NA Megaserver|Masisi^Mf") is found by its key, then kept to its own account and megaserver.
        let named = SVUsage.nameKeyParts(bucket.id)
        let found = await findResults([SVTarget(.character, named?.key ?? bucket.id)], perTarget: 2_000).first
        let tops = topFolders ?? [:]
        return bucket.byFile.map { entry in
            let base = String(entry.file.dropLast(4))
            let folder = base.hasPrefix("ZO_") ? "ZO_" : tops[base.lowercased()] ?? base
            // The shortest path is the character's own table, not something deep inside it.
            let rows = found?.files.first { $0.file == entry.file }?.rows.map(\.path).filter { path in
                guard let named else { return true }
                return path.count > 2 && path[1].description == named.profile && path[2].description == named.account
            }
            let path = rows?.min { $0.count < $1.count } ?? []
            return CharacterPlace(file: entry.file, addon: app.addonTitle(folder: folder), bytes: entry.bytes, path: path)
        }
    }
}
