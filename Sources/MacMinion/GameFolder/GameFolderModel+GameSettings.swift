import Foundation
import MacMinionKit

/// The game's own settings files: read, edit, save, and undo (S-062).
extension GameFolderModel {
    /// Reads the game's three settings files; one that isn't there is left out.
    func loadGameSettings() {
        var files: [GameSettingsFile.Kind: GameSettingsFile] = [:]
        for kind in GameSettingsFile.Kind.allCases {
            if let data = try? Data(contentsOf: app.gameFolderURL.appending(path: kind.fileName)) {
                files[kind] = GameSettingsFile.parse(data, kind: kind)
            }
        }
        gameSettings = files
        // Who loads what may have changed, and with it the settings each character runs on (S-070).
        refreshEffectiveMatrix()
    }

    /// A field's value with its unsaved edit.
    func gameSettingValue(_ field: GameSettingsFile.Field, in kind: GameSettingsFile.Kind) -> String {
        gameSettingsDrafts[kind]?[field.id] ?? field.value
    }

    /// Records an edit; going back to the file's value drops it. With `undoable`, Edit › Undo takes it back;
    /// changes to one field in a row (dragging a color) are one undo. Text fields pass false: while typing,
    /// the field's own undo applies.
    func setGameSetting(_ field: GameSettingsFile.Field, in kind: GameSettingsFile.Kind, to value: String, undoable: Bool = true) {
        let was = gameSettingsDrafts[kind]?[field.id]
        var draft = gameSettingsDrafts[kind] ?? [:]
        draft[field.id] = value == field.value ? nil : value
        guard draft[field.id] != was else { return }
        gameSettingsDrafts[kind] = draft.isEmpty ? nil : draft
        guard undoable, let manager = MainUndo.manager else { return }
        let key = "\(kind)|\(field.id)"
        // Coalesce: while this field's undo is still the newest, a further change only moves where Redo goes.
        if !manager.isUndoing, !manager.isRedoing, draftUndoKey == key, manager.canUndo,
           manager.undoActionName == String(localized: "Change Setting") { return }
        draftUndoKey = manager.isUndoing || manager.isRedoing ? nil : key
        app.registerUndo(String(localized: "Change Setting")) { app in
            let model = app.gameFolder
            model.draftUndoKey = nil
            // Back to the value before; `field.value` stands for "no edit".
            model.setGameSetting(field, in: kind, to: was ?? field.value)
            model.showGameSettings(kind)
        }
    }

    /// Shows the Game Settings tab on one file, after an undo there.
    func showGameSettings(_ kind: GameSettingsFile.Kind) {
        app.open(.gameFolder)
        tab = .gameSettings
        gameSettingsKind = kind
    }

    func gameSettingsEdits(_ kind: GameSettingsFile.Kind) -> Int { gameSettingsDrafts[kind]?.count ?? 0 }

    /// Drops the edits to one file; Edit › Undo brings them back.
    func revertGameSettings(_ kind: GameSettingsFile.Kind) {
        guard let draft = gameSettingsDrafts[kind] else { return }
        gameSettingsDrafts[kind] = nil
        draftUndoKey = nil
        registerDraftUndo(kind, draft: draft, name: String(localized: "Revert Game Settings"))
    }

    /// Puts a whole draft back, and registers the opposite.
    private func registerDraftUndo(_ kind: GameSettingsFile.Kind, draft: [Int: String]?, name: String) {
        app.registerUndo(name) { app in
            let model = app.gameFolder
            let now = model.gameSettingsDrafts[kind]
            model.gameSettingsDrafts[kind] = draft
            model.draftUndoKey = nil
            model.registerDraftUndo(kind, draft: now, name: name)
            model.showGameSettings(kind)
        }
    }

    /// Writes the edits to one file: refused while ESO runs (it writes its own copy when it quits), backed up
    /// first, and only the changed lines rewritten.
    func saveGameSettings(_ kind: GameSettingsFile.Kind) async {
        message = nil
        errorMessage = nil
        guard let file = gameSettings[kind], let draft = gameSettingsDrafts[kind], !draft.isEmpty else { return }
        guard !app.gameIsRunning else {
            errorMessage = String(localized: "Quit Elder Scrolls Online first: it writes its own copy of these files when it quits.")
            return
        }
        await app.backUp()
        if let backupError = app.backupError {
            errorMessage = String(localized: "Nothing was saved. \(backupError)")
            return
        }
        do {
            let url = app.gameFolderURL.appending(path: kind.fileName)
            let before = try Data(contentsOf: url), after = file.applying(draft)
            try after.write(to: url, options: .atomic)
            registerFileUndo(before: [url: before], after: [url: after], name: String(localized: "Save Game Settings"))
            gameSettingsDrafts[kind] = nil
            message = String(localized: "Backed up, then saved \(String(localized: "\(draft.count) settings")) in \(kind.fileName).")
        } catch {
            errorMessage = String(localized: "\(kind.fileName) wasn't saved: \(error.localizedDescription)")
        }
        loadGameSettings()
    }

    /// Edit › Undo for a save or a copy that wrote files (rule 43: undo in place, not only a backup): puts back
    /// each file's bytes from before, and Redo writes them again. Refused while ESO runs, and when a file
    /// changed since, so nothing the game wrote is lost.
    func registerFileUndo(before: [URL: Data], after: [URL: Data], name: String) {
        guard !before.isEmpty else { return }
        MainUndo.register(.files(name, before: before, after: after, gameRunning: { [weak self] in self?.app.gameIsRunning ?? false }) { [weak self] undone in
            guard let self else { return }
            message = undone ? String(localized: "Undid \(name).") : String(localized: "Redid \(name).")
            errorMessage = nil
            loadGameSettings()
            await scan()
            await load()
        })
    }
}
