import AppKit
import MacMinionKit

extension SelfTest {
    /// Backups in Minion's format, restore, and pruning (S-026).
    static func backups(_ model: AppModel) async {
        // S-026 Backups in Minion's format
        check("Minion's backups are listed: a dated one and the first one", model.backups.map(\.kind) == [.snapshot, .initial])
        await model.backUp()
        let today = model.backups.first
        check("Back Up Now writes today's zip and addon list", today?.name == MinionBackup.dayFormat.string(from: .now)
              && today?.addonIDs.count == model.installed.count && model.backups.count == 3, model.backupError ?? "")
        let harvestVars = model.gameFolderURL.appending(path: "SavedVariables/HarvestMap.lua")
        let original = try? String(contentsOf: harvestVars, encoding: .utf8)
        try? "HarvestMap_SavedVars = { broken }".write(to: harvestVars, atomically: true, encoding: .utf8)
        if let today { await model.restore(today, options: .init(files: true, reinstallMissing: false, removeOthers: false)) }
        check("Restore brings SavedVariables back", (try? String(contentsOf: harvestVars, encoding: .utf8)) == original, model.backupError ?? "")
        check("Restore first saves what was there", FileManager.default.fileExists(atPath: model.restoreSafetyFolder.path))
        model.simulatesRunningGame = true
        try? "HarvestMap_SavedVars = { broken }".write(to: harvestVars, atomically: true, encoding: .utf8)
        if let today { await model.restore(today, options: .init(files: true, reinstallMissing: false, removeOthers: false)) }
        check("Restore refuses while ESO runs", model.backupError != nil
              && (try? String(contentsOf: harvestVars, encoding: .utf8)) == "HarvestMap_SavedVars = { broken }")
        model.simulatesRunningGame = false
        let safetyCopies = { (try? FileManager.default.contentsOfDirectory(atPath: model.restoreSafetyFolder.path))?.count ?? 0 }
        let copiesBefore = safetyCopies()
        if let today { await model.restore(today, options: .init(files: true, reinstallMissing: false, removeOthers: false)) }
        check("a second restore the same day keeps the first one's safety copy", safetyCopies() == copiesBefore + 1, "\(safetyCopies())")
        if let dustman = model.installed(97) { await model.remove(dustman) }
        await model.install(695)
        if let today { await model.restore(today, options: .init(files: false, reinstallMissing: true, removeOthers: true)) }
        check("Restore installs addons missing from the backup's list", model.installed(97) != nil, model.backupMessage ?? "")
        check("Restore can remove addons not on the list", model.installed(695) == nil)
        // Two installs at once: neither one's rescan may drop the other's record.
        if let logger = model.installed(2275) { await model.remove(logger) }
        async let guildStore: Void = model.install(695)
        async let debugLogger: Void = model.install(2275)
        _ = await (guildStore, debugLogger)
        check("two installs at once both keep their version", model.installed(695)?.record.version != nil
              && model.installed(2275)?.record.version != nil, "\(model.errors)")
        if let guildStore = model.installed(695) { await model.remove(guildStore) }
        if let initial = model.backups.first(where: { $0.kind == .initial }) {
            await model.restore(initial, options: .init(files: true, reinstallMissing: false, removeOthers: false))
            let dustman = Manifest.read(folder: model.addonsFolder.appending(path: "Dustman"))
            check("Minion's first backup restores AddOns folders", dustman?.version == "5.0")
        }
        model.prefs.backupsToKeep = 1
        model.pruneBackups()
        model.loadBackups()
        check("Old backups beyond the number to keep go to the Trash, the first one stays",
              model.backups.map(\.kind) == [.snapshot, .initial])
        model.prefs.backupsToKeep = 10
    }
}
