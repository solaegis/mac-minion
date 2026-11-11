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
    }

    /// A field's value with its unsaved edit.
    func gameSettingValue(_ field: GameSettingsFile.Field, in kind: GameSettingsFile.Kind) -> String {
        gameSettingsDrafts[kind]?[field.id] ?? field.value
    }

    /// Records an edit; going back to the file's value drops it.
    func setGameSetting(_ field: GameSettingsFile.Field, in kind: GameSettingsFile.Kind, to value: String) {
        var draft = gameSettingsDrafts[kind] ?? [:]
        draft[field.id] = value == field.value ? nil : value
        gameSettingsDrafts[kind] = draft.isEmpty ? nil : draft
    }

    func gameSettingsEdits(_ kind: GameSettingsFile.Kind) -> Int { gameSettingsDrafts[kind]?.count ?? 0 }

    func revertGameSettings(_ kind: GameSettingsFile.Kind) { gameSettingsDrafts[kind] = nil }

    /// Writes the edits to one file: refused while ESO runs (it writes its own copy when it quits), backed up
    /// first, and only the changed lines rewritten.
    func saveGameSettings(_ kind: GameSettingsFile.Kind, undoManager: UndoManager? = nil) async {
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
            registerFileUndo(before: [url: before], after: [url: after], name: String(localized: "Save Game Settings"), undoManager: undoManager)
            gameSettingsDrafts[kind] = nil
            message = String(localized: "Backed up, then saved \(String(localized: "\(draft.count) settings")) in \(kind.fileName).")
        } catch {
            errorMessage = String(localized: "\(kind.fileName) wasn't saved: \(error.localizedDescription)")
        }
        loadGameSettings()
    }

    /// Edit › Undo for a save or a copy that wrote files (rule 43: undo in place, not only a backup): puts back
    /// each file's bytes from before, and registers Redo to write them again. Refused while ESO runs.
    func registerFileUndo(before: [URL: Data], after: [URL: Data], name: String, undoManager: UndoManager?) {
        guard let undoManager, !before.isEmpty else { return }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard !model.app.gameIsRunning else {
                    model.errorMessage = String(localized: "Quit Elder Scrolls Online first: it writes its own copy of these files when it quits.")
                    return
                }
                for (url, data) in before { try? data.write(to: url, options: .atomic) }
                model.message = String(localized: "Undid \(name).")
                model.registerFileUndo(before: after, after: before, name: name, undoManager: undoManager)
                model.loadGameSettings()
                Task { await model.scan(); await model.load() }
            }
        }
        undoManager.setActionName(name)
    }
}
