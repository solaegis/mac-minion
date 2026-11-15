import AppKit
import MacMinionKit

extension SelfTest {
    /// Edit › Undo and Redo for every change to addons, files, and backups (S-067).
    static func undo(_ model: AppModel) async {
        let manager = UndoManager()
        manager.groupsByEvent = false
        MainUndo.override = manager
        defer { MainUndo.override = nil }
        /// One action, as one menu item.
        func step(_ body: () async -> Void) async {
            manager.beginUndoGrouping()
            await body()
            manager.endUndoGrouping()
        }
        func undo() async { manager.undo(); await MainUndo.settle() }
        func redo() async { manager.redo(); await MainUndo.settle() }
        let fm = FileManager.default
        func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

        // Install, then Undo takes it out again without a download; Redo puts it back.
        if let gone = model.installed(695) { await model.remove(gone, registeringUndo: false) }
        let historyBefore = model.history.count
        await step { await model.install(695) }
        let installedRecord = model.installed(695)?.record
        check("Undo names an install", manager.undoActionName == String(localized: "Install Addon"), manager.undoActionName)
        await undo()
        check("Undo of an install takes its folders out and drops the record and history",
              model.installed(695) == nil && model.history.count == historyBefore
              && installedRecord?.dirs.allSatisfy { !exists(model.addonsFolder.appending(path: $0)) } == true)
        await redo()
        check("Redo of an install puts it back as installed", model.installed(695)?.record == installedRecord
              && model.history.count == historyBefore + 1)

        // Installing again over itself is an update: Undo puts back the very folders it replaced.
        if let dir = installedRecord?.dirs.first {
            let marker = model.addonsFolder.appending(path: "\(dir)/undo-marker.txt")
            try? "the old copy".write(to: marker, atomically: true, encoding: .utf8)
            await step { await model.install(695) }
            check("an update replaces the folders", !exists(marker))
            check("Undo names an update", manager.undoActionName == String(localized: "Update Addon"), manager.undoActionName)
            await undo()
            check("Undo of an update puts back the folders it replaced, without downloading", exists(marker)
                  && model.installed(695)?.record == installedRecord)
            await redo()
            check("Redo of an update installs the new folders again", !exists(marker) && model.installed(695) != nil)
        }

        // Remove Addon goes to the Trash; Undo brings it back with its record and history.
        if let addon = model.installed(695) {
            let dirs = addon.record.dirs, record = addon.record, count = model.history.count
            await step { await model.remove(addon) }
            check("Undo names a removal", manager.undoActionName == String(localized: "Remove Addon"), manager.undoActionName)
            await undo()
            check("Undo of Remove Addon brings the folders back from the Trash, with the record",
                  model.installed(695)?.record == record && model.history.count == count
                  && dirs.allSatisfy { exists(model.addonsFolder.appending(path: $0)) })
            check("Undo shows the addon it brought back", model.sidebar == .installed && model.selection == .addon(695))
            await redo()
            check("Redo of Remove Addon moves it to the Trash again", model.installed(695) == nil && model.history.count == count + 1)
            await undo()
        }

        // A folder not on ESOUI.
        let probe = model.addonsFolder.appending(path: "ZZUndoProbe", directoryHint: .isDirectory)
        try? fm.createDirectory(at: probe, withIntermediateDirectories: true)
        try? "## Title: Undo Probe\n## Version: 1\n".write(to: probe.appending(path: "ZZUndoProbe.txt"), atomically: true, encoding: .utf8)
        await model.rescan()
        if let folder = model.unmatched.first(where: { $0.folder == "ZZUndoProbe" }) {
            await step { await model.removeFolder(folder) }
            await undo()
            check("Undo puts a folder not on ESOUI back", model.unmatched.contains { $0.folder == "ZZUndoProbe" } && exists(probe))
            await redo()
            check("Redo moves the folder to the Trash again", !model.unmatched.contains { $0.folder == "ZZUndoProbe" } && !exists(probe))
        } else {
            check("the probe folder shows as not on ESOUI", false)
        }

        // Clean Up: Undo is refused while ESO runs, and otherwise puts the files back.
        let saved = model.gameFolderURL.appending(path: "SavedVariables")
        let stray = saved.appending(path: "ZZUndoProbe.lua"), stray2 = saved.appending(path: "ZZUndoProbe2.lua")
        try? "ZZUndoProbe_Vars = {}".write(to: stray, atomically: true, encoding: .utf8)
        try? "ZZUndoProbe2_Vars = {}".write(to: stray2, atomically: true, encoding: .utf8)
        await model.gameFolder.scan()
        await step { await model.gameFolder.moveToTrash(TrashRequest(title: "", urls: [stray], bytes: 0)) }
        model.simulatesRunningGame = true
        model.undoFailure = nil
        await undo()
        check("Undo of Clean Up is refused while ESO runs, and says why", !exists(stray) && model.undoFailure != nil
              && !manager.canRedo, model.undoFailure?.message ?? "")
        model.simulatesRunningGame = false
        model.undoFailure = nil
        await step { await model.gameFolder.moveToTrash(TrashRequest(title: "", urls: [stray2], bytes: 0)) }
        check("Undo names Clean Up", manager.undoActionName == String(localized: "Clean Up"), manager.undoActionName)
        await undo()
        check("Undo of Clean Up puts the file back from the Trash", exists(stray2) && model.gameFolder.tab == .problems)
        await redo()
        check("Redo of Clean Up moves it to the Trash again", !exists(stray2))

        // Move Backup to Trash.
        await model.backUp()
        if let newest = model.backups.first, let zip = newest.zip {
            let count = model.backups.count
            await step { model.deleteBackup(newest) }
            check("a backup goes to the Trash", model.backups.count == count - 1 && !exists(zip))
            await undo()
            check("Undo brings a backup back from the Trash", model.backups.count == count && exists(zip))
        }

        // Restore This File, and Undo never overwrites a file changed since.
        let harvest = saved.appending(path: "HarvestMap.lua")
        let original = try? Data(contentsOf: harvest)
        if let newest = model.backups.first(where: { $0.kind == .snapshot && $0.zip != nil }), let original {
            let changed = Data("HarvestMap_SavedVars = { changed }".utf8)
            try? changed.write(to: harvest)
            await step { await model.restoreFile("HarvestMap.lua", from: newest) }
            check("Restore This File puts the backup's copy back", (try? Data(contentsOf: harvest)) == original, model.backupError ?? "")
            check("Undo names Restore File", manager.undoActionName == String(localized: "Restore File"), manager.undoActionName)
            await undo()
            check("Undo of Restore This File puts back what was there", (try? Data(contentsOf: harvest)) == changed)
            let newer = Data("HarvestMap_SavedVars = { the game wrote this }".utf8)
            try? newer.write(to: harvest)
            model.undoFailure = nil
            await redo()
            check("Redo never overwrites a file that changed since", (try? Data(contentsOf: harvest)) == newer && model.undoFailure != nil)

            // Restore Backup: Undo puts back the files from before, from the safety copy.
            model.undoFailure = nil
            try? changed.write(to: harvest)
            await step { await model.restore(newest, options: .init(files: true, reinstallMissing: false, removeOthers: false)) }
            check("Restore Backup brings the file back", (try? Data(contentsOf: harvest)) == original, model.backupError ?? "")
            check("Undo names Restore Backup", manager.undoActionName == String(localized: "Restore Backup"), manager.undoActionName)
            await undo()
            check("Undo of Restore Backup puts back the files from before it", (try? Data(contentsOf: harvest)) == changed,
                  model.undoFailure?.message ?? "")
            await redo()
            check("Redo of Restore Backup restores the backup's files again", (try? Data(contentsOf: harvest)) == original,
                  model.undoFailure?.message ?? "")
            try? original.write(to: harvest)
        }

        // Game Settings: a switch's edit, then Revert, each undone.
        model.gameFolder.loadGameSettings()
        if let field = model.gameFolder.gameSettings[.addOns]?.fields.first(where: { $0.type == .toggle }) {
            let flipped = field.value == "1" ? "0" : "1"
            await step { model.gameFolder.setGameSetting(field, in: .addOns, to: flipped) }
            check("Undo names a setting's edit", manager.undoActionName == String(localized: "Change Setting"), manager.undoActionName)
            await undo()
            check("Undo takes back a setting's edit", model.gameFolder.gameSettingsEdits(.addOns) == 0
                  && model.gameFolder.tab == .gameSettings && model.gameFolder.gameSettingsKind == .addOns)
            await redo()
            check("Redo makes the edit again", model.gameFolder.gameSettingValue(field, in: .addOns) == flipped)
            await step { model.gameFolder.revertGameSettings(.addOns) }
            await undo()
            check("Undo of Revert brings the edits back", model.gameFolder.gameSettingsEdits(.addOns) == 1)
            model.gameFolder.gameSettingsDrafts[.addOns] = nil
        }
        manager.removeAllActions()
    }
}
