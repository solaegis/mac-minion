import Foundation
import Testing
@testable import MacMinionKit

private struct Game {
    let root: URL, game: URL, restore: BackupRestore
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "mm-restore-\(UUID().uuidString)")
        game = root.appending(path: "live")
        try FileManager.default.createDirectory(at: game.appending(path: "SavedVariables"), withIntermediateDirectories: true)
        restore = BackupRestore(gameFolder: game, safetyRoot: root.appending(path: "restore-safety"))
    }
    func write(_ relative: String, _ text: String) throws {
        let url = game.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    func read(_ relative: String) -> String? { try? String(contentsOf: game.appending(path: relative), encoding: .utf8) }
    func exists(_ relative: String) -> Bool { FileManager.default.fileExists(atPath: game.appending(path: relative).path) }
    func snapshot() throws -> URL {
        try #require(MinionBackup.create(gameFolder: game, addonIDs: [7], backupDir: root.appending(path: "backups"), gameID: "live").zip)
    }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

@Test func restoringEverythingPutsBackEveryFileAndSavesFirst() async throws {
    let g = try Game(); defer { g.cleanUp() }
    try g.write("SavedVariables/HarvestMap.lua", "harvest = 'backed up'")
    try g.write("AddOnSettings.txt", "settings = 'backed up'")
    let zip = try g.snapshot()
    try g.write("SavedVariables/HarvestMap.lua", "harvest = 'changed since'")
    try g.write("AddOnSettings.txt", "settings = 'changed since'")

    let result = try await g.restore.run(.everything(from: zip), addonIDs: [7])
    #expect(result.restored == 2)
    #expect(g.read("SavedVariables/HarvestMap.lua") == "harvest = 'backed up'")
    #expect(g.read("AddOnSettings.txt") == "settings = 'backed up'")
    let saved = try #require(MinionBackup.list(backupDir: result.safety, gameID: "before-restore").first?.zip)
    #expect(MinionBackup.files(in: saved) == ["SavedVariables/HarvestMap.lua", "AddOnSettings.txt"],
            "what was there before is saved first")
}

@Test func restoringOneFileLeavesTheOthersAsTheyAre() async throws {
    let g = try Game(); defer { g.cleanUp() }
    try g.write("SavedVariables/HarvestMap.lua", "harvest = 'backed up'")
    try g.write("SavedVariables/Dustman.lua", "dust = 'backed up'")
    let zip = try g.snapshot()
    try g.write("SavedVariables/HarvestMap.lua", "harvest = 'changed since'")
    try g.write("SavedVariables/Dustman.lua", "dust = 'changed since'")

    let result = try await g.restore.run(.file("SavedVariables/Dustman.lua", from: zip), addonIDs: [7])
    #expect(result.restored == 1)
    #expect(g.read("SavedVariables/Dustman.lua") == "dust = 'backed up'")
    #expect(g.read("SavedVariables/HarvestMap.lua") == "harvest = 'changed since'")
}

@Test func aFileTheBackupLacksChangesNothing() async throws {
    let g = try Game(); defer { g.cleanUp() }
    try g.write("SavedVariables/HarvestMap.lua", "harvest = 'now'")
    let zip = try g.snapshot()
    do {
        _ = try await g.restore.run(.file("SavedVariables/Nope.lua", from: zip), addonIDs: [])
        Issue.record("expected notInBackup")
    } catch .notInBackup(let safety) {
        #expect(FileManager.default.fileExists(atPath: safety.path), "the save before still happened")
    } catch {
        Issue.record("unexpected \(error)")
    }
    #expect(g.read("SavedVariables/HarvestMap.lua") == "harvest = 'now'")
    #expect(!g.exists("SavedVariables/Nope.lua"))
}

@Test func saveOnlyPutsNothingBack() async throws {
    let g = try Game(); defer { g.cleanUp() }
    try g.write("SavedVariables/HarvestMap.lua", "harvest = 'backed up'")
    _ = try g.snapshot()
    try g.write("SavedVariables/HarvestMap.lua", "harvest = 'changed since'")
    let result = try await g.restore.run(.saveOnly, addonIDs: [])
    #expect(result.restored == 0)
    #expect(g.read("SavedVariables/HarvestMap.lua") == "harvest = 'changed since'")
    #expect(FileManager.default.fileExists(atPath: result.safety.path))
}

@Test func aFullAddOnsBackupReplacesWholeAddonFolders() async throws {
    let g = try Game(); defer { g.cleanUp() }
    // An initial backup: the whole AddOns folder, with absolute entry names as Minion writes them.
    let old = g.root.appending(path: "elsewhere/live/AddOns/HarvestMap")
    let zip = g.root.appending(path: "initial.zip")
    try ZipWriter.write([.init(name: old.appending(path: "HarvestMap.txt").path, data: Data("## Version: 1".utf8), modified: .now)], to: zip)
    try g.write("AddOns/HarvestMap/HarvestMap.txt", "## Version: 2")
    try g.write("AddOns/HarvestMap/NewInVersion2.lua", "-- only in the newer version")
    try g.write("AddOns/Dustman/Dustman.txt", "## Version: 9")

    let result = try await g.restore.run(.everything(from: zip), addonIDs: [])
    #expect(result.restored == 1)
    #expect(g.read("AddOns/HarvestMap/HarvestMap.txt") == "## Version: 1")
    #expect(!g.exists("AddOns/HarvestMap/NewInVersion2.lua"), "files from the newer version don't linger")
    #expect(g.read("AddOns/Dustman/Dustman.txt") == "## Version: 9", "addons the backup doesn't hold stay")
}

@Test func replacedAddonFoldersAreOnlyFoldersWithFilesInside() {
    let game = URL(filePath: "/g/live")
    let files = ["AddOns/A/A.txt", "AddOns/B/sub/x.lua", "AddOns/loose.txt", "SavedVariables/A.lua"].map { game.appending(path: $0) }
    #expect(BackupRestore.replacedAddonFolders(files, gameFolder: game) == ["A", "B"])
}

@Test func aSaveThatFailsMeansNothingChanged() async throws {
    let g = try Game(); defer { g.cleanUp() }
    try g.write("SavedVariables/HarvestMap.lua", "harvest = 'now'")
    let zip = try g.snapshot()
    // The safety root is a file, so the save can't make its folder.
    let blocked = g.root.appending(path: "blocked")
    try "x".write(to: blocked, atomically: true, encoding: .utf8)
    let restore = BackupRestore(gameFolder: g.game, safetyRoot: blocked)
    do {
        _ = try await restore.run(.everything(from: zip), addonIDs: [])
        Issue.record("expected couldNotSaveFirst")
    } catch .couldNotSaveFirst {
    } catch {
        Issue.record("unexpected \(error)")
    }
}
