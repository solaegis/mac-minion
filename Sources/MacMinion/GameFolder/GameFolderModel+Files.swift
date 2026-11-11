import AppKit
import MacMinionKit

/// The game folder's files: the scan, Clean Up, and opening files elsewhere (S-028, S-029).
extension GameFolderModel {
    /// Reads the game folder and who owns each SavedVariables file, off the main thread.
    func scan() async {
        let game = app.gameFolderURL, addons = app.addonsFolder
        let (scan, files) = await Task.detached {
            (GameFolderScan.scan(game), SavedVariablesAudit.run(game: game, addons: addons))
        }.value
        gameScan = scan
        if files.map(\.modified) != savedVariables.map(\.modified) || files.map(\.name) != savedVariables.map(\.name) {
            readIsCurrent = false // read again from the new files when a Game Folder page next opens
            inspectorSourceNames = [:] // read again from the addon's source when a file next opens
            generation += 1 // a read of the old files, still under way, is thrown away
        }
        savedVariables = files
        retainParsedDocuments(files.filter { $0.name.hasSuffix(".lua") }.map(\.url))
        fileProblems = SVFileProblems.check(files: files, strays: scan.copies)
        app.companionSnapshot = await Task.detached {
            CompanionData.read(in: game.appending(path: "SavedVariables"))
        }.value
    }

    /// SavedVariables files no installed addon uses, and copies of them.
    var tidyableSavedVariables: [SavedVariablesFile] { savedVariables.filter(\.isTidyable) }

    /// Asks before moving every tidyable SavedVariables file, or just the chosen ones, to the Trash.
    func askToTidy(_ chosen: Set<SavedVariablesFile.ID> = []) {
        let files = tidyableSavedVariables.filter { chosen.isEmpty || chosen.contains($0.id) }
        guard !files.isEmpty else { return }
        pendingTrash = TrashRequest(title: files.count == 1 ? "Move “\(files[0].name)” to the Trash?"
                                        : String(localized: "Move \(files.count) SavedVariables files to the Trash?"),
                                    urls: files.map(\.url), bytes: files.reduce(0) { $0 + $1.bytes })
    }

    /// Asks before moving copies beside AddOns to the Trash.
    func askToTrash(_ copies: [GameFolderItem]) {
        guard !copies.isEmpty else { return }
        pendingTrash = TrashRequest(title: copies.count == 1 ? "Move “\(copies[0].name)” to the Trash?"
                                        : String(localized: "Move \(copies.count) copies to the Trash?"),
                                    urls: copies.map(\.url), bytes: copies.reduce(0) { $0 + $1.bytes })
    }

    /// Backs up, then moves the files to the Trash. Refuses while ESO runs: it rewrites the folder when it quits.
    func moveToTrash(_ request: TrashRequest) async {
        message = nil
        errorMessage = nil
        guard !app.gameIsRunning else {
            errorMessage = String(localized: "Quit Elder Scrolls Online first: it rewrites these files when it quits.")
            return
        }
        await app.backUp()
        if let backupError = app.backupError {
            errorMessage = String(localized: "Nothing was moved. \(backupError)")
            return
        }
        var moved = 0
        for url in request.urls {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil); moved += 1 }
            catch { errorMessage = String(localized: "Couldn't move \(url.lastPathComponent) to the Trash: \(error.localizedDescription)") }
        }
        if moved > 0 {
            let items = String(localized: "\(moved) items")
            message = String(localized: "Backed up, then moved \(items) (\(request.bytes.formatted(.byteCount(style: .file)))) to the Trash.")
        }
        await scan()
    }

    func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([app.gameFolderURL])
    }

    /// Opens files in the editor chosen in Settings > General, or else in each file's default app.
    /// A file no app claims, like a `.lua` file on a fresh Mac, opens in TextEdit.
    func openInEditor(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let workspace = NSWorkspace.shared
        if let editor = app.prefs.editorURL, FileManager.default.fileExists(atPath: editor.path) {
            workspace.open(urls, withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        for url in urls {
            if workspace.urlForApplication(toOpen: url) != nil {
                workspace.open(url)
            } else if let textEdit = workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
                workspace.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }
}
