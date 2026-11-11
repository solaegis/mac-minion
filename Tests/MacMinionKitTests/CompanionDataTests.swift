import Foundation
import Testing
@testable import MacMinionKit

private let schema1 = """
EsoMacMinion_Data =
{
    ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
        ["schema"] = 1, ["written"] = 1793288692,
        ["env"] = { ["apiVersion"] = 101051, ["gameVersion"] = "12.1.6", ["server"] = "NA Megaserver", ["companionVersion"] = "0.1.0" },
        ["characters"] = {
            ["8796093036412335"] = { ["name"] = "Masisi", ["class"] = 3, ["race"] = 9, ["level"] = 50, ["champion"] = 2410, ["lastPlayed"] = 1793288692 },
        },
        ["addons"] = {
            ["WritWorthy"] = { ["title"] = "WritWorthy", ["enabled"] = true, ["state"] = "loaded", ["outOfDate"] = false, ["loadMs"] = 1500 },
            ["BrokenOne"] = { ["title"] = "Broken One", ["enabled"] = true, ["state"] = "missing", ["missing"] = { [1] = "LibLazyCrafting" } },
            ["OldOne"] = { ["title"] = "Old One", ["enabled"] = true, ["state"] = "loaded", ["outOfDate"] = true },
        },
        ["errors"] = {
            [1] = { ["addon"] = "WizardsWardrobe", ["at"] = 1793288692, ["count"] = 12, ["message"] = "user:/AddOns/WizardsWardrobe/ui.lua:212: attempt to index a nil value" },
        },
        ["guilds"] = {
            ["127263"] = { ["name"] = "Bandits Clan", ["members"] = 487, ["server"] = "NA Megaserver" },
        },
    } } },
}
"""

@Test func readsASchema1CompanionSnapshotFromEitherFileName() throws {
    let doc = SVDocument.parse(Data(schema1.utf8))
    for name in CompanionData.fileNames {
        #expect(CompanionData.isCompanionFile(name))
        let snap = try #require(CompanionData.snapshot(doc, file: name))
        #expect(snap.schemaKnown && snap.schema == 1 && snap.file == name)
        #expect(snap.env?.gameVersion == "12.1.6" && snap.env?.apiVersion == 101051)
        let masisi = try #require(snap.characters["8796093036412335"])
        #expect(masisi.className == "Nightblade" && masisi.level == 50)
        #expect(snap.addons["BrokenOne"]?.failedToLoad == true && snap.addons["BrokenOne"]?.missing == ["LibLazyCrafting"])
        #expect(snap.errors.first?.addon == "WizardsWardrobe" && snap.errors.first?.count == 12)
        #expect(snap.guilds[127263]?.name == "Bandits Clan")
    }
    #expect(!CompanionData.isCompanionFile("pChat.lua"))
    #expect(CompanionData.roster(doc)["8796093036412335"]?.name == "Masisi")
}

@Test func unknownCompanionSchemaStillReadsKnownSectionsAndSaysSo() throws {
    let doc = SVDocument.parse(Data(schema1.replacingOccurrences(of: "[\"schema\"] = 1", with: "[\"schema\"] = 9").utf8))
    let snap = try #require(CompanionData.snapshot(doc))
    #expect(!snap.schemaKnown && snap.schema == 9 && snap.skipped.isEmpty == false)
    #expect(snap.characters["8796093036412335"]?.name == "Masisi")
    let problems = CompanionData.problems(from: snap)
    #expect(problems.contains { $0.kind == .unknownSchema })
}

@Test func companionProblemsCoverLoadFailuresAndLuaErrors() throws {
    let snap = try #require(CompanionData.snapshot(SVDocument.parse(Data(schema1.utf8))))
    let problems = CompanionData.problems(from: snap)
    #expect(problems.contains { $0.kind == .didntLoad && $0.message.contains("LibLazyCrafting") })
    #expect(problems.contains { $0.kind == .outOfDateAddon && $0.message.contains("Old One") })
    #expect(problems.contains { $0.kind == .luaError && $0.message.contains("WizardsWardrobe") && $0.severity == .error })
}

@Test func companionProblemsNameTheirAddon() throws {
    let snap = try #require(CompanionData.snapshot(SVDocument.parse(Data(schema1.utf8))))
    let problems = CompanionData.problems(from: snap)
    func addon(_ kind: SVProblem.Kind) -> String? { problems.first { $0.kind == kind }?.addon }
    #expect(addon(.didntLoad) == "BrokenOne")
    #expect(addon(.outOfDateAddon) == "OldOne")
    #expect(addon(.slowLoad) == "WritWorthy")
    #expect(addon(.luaError) == "WizardsWardrobe")
    // Only companion problems name an addon, and the addon doesn't change a problem's id.
    let tagged = try #require(problems.first { $0.kind == .luaError })
    var untagged = tagged
    untagged.addon = nil
    #expect(tagged.id == untagged.id)
}

@Test func companionFolderIsNotUnmatched() {
    let folders: [String: Manifest?] = [
        "EsoMacMinion": Manifest(title: "ESO Mac Minion", author: "solaegis"),
        "MyOwn": Manifest(title: "Mine"),
    ]
    let r = AddonMatcher.match(folders: folders, catalog: [], records: [:])
    #expect(r.unmatched.map(\.folder) == ["MyOwn"])
    #expect(CompanionData.isCompanionFolder("EsoMacMinion") && CompanionInstaller.isPresent(in: URL(fileURLWithPath: "/no/such")) == false)
}

@Test func installsTheCompanionFromASourceFolder() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "companion-install-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "src/\(CompanionData.folderName)")
    let addons = root.appending(path: "AddOns")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try "## Title: ESO Mac Minion\n".write(to: source.appending(path: "EsoMacMinion.txt"), atomically: true, encoding: .utf8)
    try CompanionInstaller.install(from: source, into: addons)
    #expect(CompanionInstaller.isPresent(in: addons))
    #expect(FileManager.default.fileExists(atPath: addons.appending(path: "EsoMacMinion/EsoMacMinion.txt").path))
}

@Test func companionSavedVariablesFileBelongsToTheAddonByVariableName() throws {
    let fm = FileManager.default
    let game = fm.temporaryDirectory.appending(path: "mm-companion-sv-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: game) }
    let addons = game.appending(path: "AddOns/EsoMacMinion"), sv = game.appending(path: "SavedVariables")
    try fm.createDirectory(at: addons, withIntermediateDirectories: true)
    try fm.createDirectory(at: sv, withIntermediateDirectories: true)
    try "## Title: ESO Mac Minion\n## SavedVariables: EsoMacMinion_Data\n"
        .write(to: addons.appending(path: "EsoMacMinion.txt"), atomically: true, encoding: .utf8)
    try schema1.write(to: sv.appending(path: "EsoMacMinion.lua"), atomically: true, encoding: .utf8)
    try schema1.write(to: sv.appending(path: "EsoMacMinion_Data.lua"), atomically: true, encoding: .utf8)
    let owners = Dictionary(uniqueKeysWithValues: SavedVariablesAudit.run(game: game, addons: addons.deletingLastPathComponent()).map { ($0.name, $0.owner) })
    #expect(owners["EsoMacMinion.lua"] == .addon("EsoMacMinion"))
    #expect(owners["EsoMacMinion_Data.lua"] == .addon("EsoMacMinion"))
}

@Test func companionSnapshotIsReadFromEsoMacMinionLua() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "companion-sv-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try schema1.write(to: folder.appending(path: "EsoMacMinion.lua"), atomically: true, encoding: .utf8)
    let snap = try #require(CompanionData.read(in: folder))
    #expect(snap.file == "EsoMacMinion.lua" && snap.characters["8796093036412335"]?.name == "Masisi")

    let read = await SVFolderRead.read([folder.appending(path: "EsoMacMinion.lua")], addons: nil, declarations: [:])
    #expect(read.roster["8796093036412335"]?.className == "Nightblade")
    #expect(read.names.guilds[127263] == "Bandits Clan")
    #expect(read.problems.contains { $0.kind == .luaError })
    #expect(read.snapshot?.env?.gameVersion == "12.1.6")
}
