import Foundation
import Testing
@testable import MacMinionKit

/// Fixed clock for companion age tests (Nov 2026); fixture stamps sit near this.
private let companionTestNow = Date(timeIntervalSince1970: 1_794_706_243)
private let companionTestStamp = 1_794_706_243

private let schema1 = """
EsoMacMinion_Data =
{
    ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
        ["schema"] = 1, ["written"] = \(companionTestStamp),
        ["env"] = { ["apiVersion"] = 101051, ["gameVersion"] = "12.1.6", ["server"] = "NA Megaserver", ["companionVersion"] = "0.1.0" },
        ["characters"] = {
            ["8796093036412335"] = { ["name"] = "Masisi", ["class"] = 3, ["race"] = 9, ["level"] = 50, ["champion"] = 2410, ["lastPlayed"] = \(companionTestStamp) },
        },
        ["addons"] = {
            ["WritWorthy"] = { ["title"] = "WritWorthy", ["enabled"] = true, ["state"] = "loaded", ["outOfDate"] = false, ["loadMs"] = 1500 },
            ["BrokenOne"] = { ["title"] = "Broken One", ["enabled"] = true, ["state"] = "missing", ["missing"] = { [1] = "LibLazyCrafting" } },
            ["OldOne"] = { ["title"] = "Old One", ["enabled"] = true, ["state"] = "loaded", ["outOfDate"] = true },
        },
        ["errors"] = {
            [1] = { ["addon"] = "WizardsWardrobe", ["at"] = \(companionTestStamp), ["count"] = 12, ["message"] = "user:/AddOns/WizardsWardrobe/ui.lua:212: attempt to index a nil value" },
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
    let problems = CompanionData.problems(from: snap, now: companionTestNow)
    #expect(problems.contains { $0.kind == .didntLoad && $0.message.contains("LibLazyCrafting") })
    #expect(problems.contains { $0.kind == .outOfDateAddon && $0.message.contains("Old One") })
    #expect(problems.contains { $0.kind == .luaError && $0.message.contains("WizardsWardrobe") && $0.severity == .error })
    #expect(problems.contains { $0.kind == .luaError && $0.message.contains("last session") })
}

@Test func companionProblemsNameTheirAddon() throws {
    let snap = try #require(CompanionData.snapshot(SVDocument.parse(Data(schema1.utf8))))
    let problems = CompanionData.problems(from: snap, now: companionTestNow)
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

/// The file lists EU first (older), then NA (newer). Snapshot must use the newest written, not file order.
private let multiBlockOlderFirst = """
EsoMacMinion_Data =
{
    ["EU Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
        ["schema"] = 1, ["written"] = 1794663262,
        ["env"] = { ["apiVersion"] = 101051, ["gameVersion"] = "12.1.5", ["server"] = "EU Megaserver", ["companionVersion"] = "0.1.0" },
        ["characters"] = {
            ["8796093036412335"] = { ["name"] = "MasisiEU", ["class"] = 3, ["level"] = 50 },
        },
        ["addons"] = { ["OldList"] = { ["title"] = "Old", ["outOfDate"] = true } },
        ["errors"] = {
            [1] = { ["addon"] = "SharedAddon", ["at"] = 1794663262, ["count"] = 2, ["message"] = "shared boom" },
            [2] = { ["addon"] = "EUOnly", ["at"] = 1794663200, ["count"] = 1, ["message"] = "eu only" },
        },
        ["layouts"] = {
            ["scanned"] = { ["at"] = 1794663262, ["requested"] = 3, ["found"] = 1, ["missing"] = { [1] = "OldMissing" } },
            ["sv"] = {
                ["OnlyInEU"] = { ["ctor"] = "NewAccountWide", ["addon"] = "EUAddon" },
                ["SharedSV"] = { ["ctor"] = "New", ["addon"] = "OldShared" },
            },
        },
    } } },
    ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
        ["schema"] = 1, ["written"] = 1794706243,
        ["env"] = { ["apiVersion"] = 101051, ["gameVersion"] = "12.1.6", ["server"] = "NA Megaserver", ["companionVersion"] = "0.1.0" },
        ["characters"] = {
            ["8796093036412999"] = { ["name"] = "MasisiNA", ["class"] = 1, ["level"] = 50 },
        },
        ["addons"] = { ["NewList"] = { ["title"] = "New", ["outOfDate"] = false } },
        ["errors"] = {
            [1] = { ["addon"] = "SharedAddon", ["at"] = 1794706243, ["count"] = 3, ["message"] = "shared boom" },
        },
        ["layouts"] = {
            ["scanned"] = { ["at"] = 1794706243, ["requested"] = 10, ["found"] = 8, ["missing"] = { [1] = "NewMissing" } },
            ["sv"] = {
                ["SharedSV"] = { ["ctor"] = "NewAccountWide", ["addon"] = "NewShared" },
                ["OnlyInNA"] = { ["ctor"] = "New", ["addon"] = "NAAddon" },
            },
        },
    } } },
}
"""

@Test func companionSnapshotPrefersNewestAccountWideBlock() throws {
    let snap = try #require(CompanionData.snapshot(SVDocument.parse(Data(multiBlockOlderFirst.utf8))))
    #expect(snap.written == Date(timeIntervalSince1970: 1_794_706_243))
    #expect(snap.env?.server == "NA Megaserver")
    #expect(snap.env?.gameVersion == "12.1.6")
    #expect(snap.layoutScan?.requested == 10 && snap.layoutScan?.missing == ["NewMissing"])
    #expect(snap.addons["NewList"] != nil && snap.addons["OldList"] == nil)
    #expect(snap.layouts["SharedSV"]?.addon == "NewShared")
    #expect(snap.layouts["OnlyInNA"] != nil && snap.layouts["OnlyInEU"] != nil)
    let shared = try #require(snap.errors.first { $0.addon == "SharedAddon" })
    #expect(shared.count == 5 && shared.at == Date(timeIntervalSince1970: 1_794_706_243))
    #expect(snap.errors.contains { $0.addon == "EUOnly" })
}

@Test func companionProblemsUseTheFirstLineOfALuaErrorAndKeepTheRestAsDetail() throws {
    let stack = "user:/AddOns/Boom/a.lua:1: nil value\nstack traceback:\n\t[C]: in function\n<Locals> x = 1"
    let lua = """
    EsoMacMinion_Data =
    {
        ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
            ["schema"] = 1, ["written"] = \(companionTestStamp),
            ["errors"] = {
                [1] = { ["addon"] = "Boom", ["at"] = \(companionTestStamp), ["count"] = 1,
                        ["message"] = "user:/AddOns/Boom/a.lua:1: nil value\\nstack traceback:\\n\\t[C]: in function\\n<Locals> x = 1" },
            },
        } } },
    }
    """
    let snap = try #require(CompanionData.snapshot(SVDocument.parse(Data(lua.utf8))))
    #expect(snap.errors.first?.message.contains("stack traceback") == true)
    let problem = try #require(CompanionData.problems(from: snap, now: companionTestNow).first { $0.kind == .luaError })
    #expect(problem.message.contains("user:/AddOns/Boom/a.lua:1: nil value"))
    #expect(!problem.message.contains("stack traceback"))
    #expect(problem.detail?.contains("stack traceback") == true)
    #expect(CompanionData.errorFirstLine(stack) == "user:/AddOns/Boom/a.lua:1: nil value")
}

@Test func companionProblemsHideErrorsOlderThanSevenDaysAndDateOlderOnes() throws {
    let staleAt = companionTestStamp - Int(8 * 24 * 3600)
    let olderSessionAt = companionTestStamp - Int(2 * 24 * 3600)
    let lua = """
    EsoMacMinion_Data =
    {
        ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
            ["schema"] = 1, ["written"] = \(companionTestStamp),
            ["errors"] = {
                [1] = { ["addon"] = "Fresh", ["at"] = \(companionTestStamp), ["count"] = 1, ["message"] = "fresh boom" },
                [2] = { ["addon"] = "Recent", ["at"] = \(olderSessionAt), ["count"] = 2, ["message"] = "recent boom" },
                [3] = { ["addon"] = "Ancient", ["at"] = \(staleAt), ["count"] = 9, ["message"] = "ancient boom" },
            },
        } } },
    }
    """
    let snap = try #require(CompanionData.snapshot(SVDocument.parse(Data(lua.utf8))))
    #expect(snap.errors.count == 3)
    let problems = CompanionData.problems(from: snap, now: companionTestNow)
    #expect(problems.filter { $0.kind == .luaError }.count == 2)
    #expect(problems.contains { $0.kind == .luaError && $0.message.contains("Fresh") && $0.message.contains("last session") })
    #expect(problems.contains { $0.kind == .luaError && $0.message.contains("Recent") && !$0.message.contains("last session") })
    #expect(!problems.contains { $0.message.contains("Ancient") })
}

@Test func companionSnapshotParsesAnswersSessionsSavedAtAndEnvCounts() throws {
    let lua = """
    EsoMacMinion_Data =
    {
        ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
            ["schema"] = 1, ["written"] = \(companionTestStamp), ["savedAt"] = \(companionTestStamp + 10),
            ["env"] = { ["server"] = "NA Megaserver", ["addonsTotal"] = 100, ["addonsLoaded"] = 80,
                        ["addonsDisabled"] = 15, ["loadOutOfDateAddOns"] = true },
            ["lookups"] = { ["answers"] = {
                ["zone:3"] = { ["name"] = "Glenumbra" },
                ["item:96175"] = { ["name"] = "Ring of the Wild Hunt", ["quality"] = 5, ["set"] = 576 },
            } },
            ["sessions"] = {
                [1] = { ["character"] = "8796093036412335", ["loginAt"] = \(companionTestStamp - 3600),
                        ["logoutAt"] = \(companionTestStamp), ["zoneId"] = 3 },
            },
            ["addons"] = { ["Boom"] = { ["addOnVersion"] = 5 } },
            ["errors"] = {
                [1] = { ["addon"] = "Boom", ["at"] = \(companionTestStamp), ["addonVersion"] = 4,
                        ["count"] = 1, ["message"] = "old boom" },
                [2] = { ["addon"] = "Boom", ["at"] = \(companionTestStamp), ["addonVersion"] = 5,
                        ["count"] = 1, ["message"] = "current boom" },
            },
        } } },
    }
    """
    let snap = try #require(CompanionData.snapshot(SVDocument.parse(Data(lua.utf8))))
    #expect(snap.savedAt == Date(timeIntervalSince1970: TimeInterval(companionTestStamp + 10)))
    #expect(snap.env?.addonsTotal == 100 && snap.env?.addonsLoaded == 80)
    #expect(snap.env?.loadOutOfDateAddOns == true)
    #expect(snap.answers["zone:3"]?.name == "Glenumbra")
    #expect(snap.answers["item:96175"]?.set == 576)
    #expect(snap.sessions.count == 1)
    #expect(CompanionData.playedTime(characterID: "8796093036412335", in: snap) == 3600)
    #expect(snap.addons["Boom"]?.addOnVersion == 5)
    let problems = CompanionData.problems(from: snap, now: companionTestNow)
    #expect(!problems.contains { $0.message.contains("old boom") })
    #expect(problems.contains { $0.message.contains("current boom") })
}

@Test func companionAnswersRankAboveLibraryNamesInTheIndex() {
    var names = SVNameIndex()
    names.zones[3] = "LibZone Glenumbra"
    names.finish(roster: nil, addons: nil, answers: ["zone:3": CompanionAnswer(key: "zone:3", name: "Companion Glenumbra",
                                                                               quality: nil, set: nil, icon: nil)])
    let named = names.name(forValue: .integer(3), key: .string("zoneId"), at: [.string("File")])
    #expect(named?.title == "Companion Glenumbra")
    #expect(named?.source.contains("Companion") == true)
}

@Test func missingAnswersStopTheAskButNeverNameAnything() throws {
    let lua = """
    EsoMacMinion_Data =
    {
        ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
            ["schema"] = 1, ["written"] = \(companionTestStamp),
            ["lookups"] = { ["answers"] = {
                ["zone:3"] = { ["missing"] = true, ["at"] = \(companionTestStamp) },
                ["item:96175"] = { ["missing"] = true, ["at"] = \(companionTestStamp) },
                ["quest:7"] = { ["name"] = "A Quest" },
            } },
        } } },
    }
    """
    let snap = try #require(CompanionData.snapshot(SVDocument.parse(Data(lua.utf8))))
    let zone = try #require(snap.answers["zone:3"])
    #expect(zone.missing && zone.name == nil && zone.at == Date(timeIntervalSince1970: TimeInterval(companionTestStamp)))

    // Answered at all, named or missing: not asked again.
    let refs = SVReferenceIndex.merging(files: ["A.lua"], parts: [[
        SVTarget(.zone, "3"): [SVHit(file: 0, offset: 0)], SVTarget(.item, "96175"): [SVHit(file: 0, offset: 1)],
        SVTarget(.quest, "7"): [SVHit(file: 0, offset: 2)], SVTarget(.quest, "8"): [SVHit(file: 0, offset: 3)],
    ]])
    let asks = CompanionRequests.unmetNameIDs(references: refs, names: nil, answers: snap.answers)
    #expect(asks["zone"] == [] && asks["item"] == [] && asks["quest"] == [8])

    // The cache keeps missing rows.
    let store = FileManager.default.temporaryDirectory.appending(path: "answers-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: store) }
    CompanionAnswerCache.save(snap.answers, to: store)
    let cached = CompanionAnswerCache.load(from: store)
    #expect(cached["zone:3"]?.missing == true && cached["quest:7"]?.missing == false)

    // A missing answer doesn't hide the library's name or name an item.
    var names = SVNameIndex()
    names.zones[3] = "LibZone Glenumbra"
    names.finish(roster: nil, addons: nil, answers: cached)
    #expect(names.name(forValue: .integer(3), key: .string("zoneId"), at: [.string("File")])?.title == "LibZone Glenumbra")
    #expect(names.companionName(kind: "zone", id: 3, as: .zone) == nil)
    #expect(names.itemName(id: 96175, link: nil)?.source != "MacMinion Companion")
    #expect(names.title(for: SVTarget(.achievement, "3")) == nil)
}

@Test func luaErrorProblemsOpenAtTheirNewestOccurrenceInTheFile() throws {
    let lua = """
    EsoMacMinion_Data =
    {
        ["EU Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
            ["schema"] = 1, ["written"] = \(companionTestStamp),
            ["errors"] = {
                [1] = { ["addon"] = "Newer", ["at"] = \(companionTestStamp), ["count"] = 1, ["message"] = "newer boom" },
                [2] = { ["addon"] = "Shared", ["at"] = \(companionTestStamp - 600), ["count"] = 1, ["message"] = "shared boom" },
            },
        } } },
        ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
            ["schema"] = 1, ["written"] = \(companionTestStamp - 3600),
            ["errors"] = {
                [1] = { ["addon"] = "Shared", ["at"] = \(companionTestStamp - 300), ["count"] = 2, ["message"] = "shared boom" },
                [2] = { ["addon"] = "SecondOnly", ["at"] = \(companionTestStamp - 3600), ["count"] = 1, ["message"] = "second boom" },
            },
        } } },
    }
    """
    let doc = SVDocument.parse(Data(lua.utf8))
    let snap = try #require(CompanionData.snapshot(doc))
    let problems = CompanionData.problems(from: snap, now: companionTestNow).filter { $0.kind == .luaError }
    func path(_ addon: String) -> [LuaKey]? { problems.first { $0.addon == addon }?.path }
    let na: [LuaKey] = [.string(CompanionData.variable), .string("NA Megaserver"), .string("@SOLAEGIS"), .string("$AccountWide"), .string("errors")]
    #expect(path("SecondOnly") == na + [.integer(2)])
    // Shared was last thrown in the older block's row.
    #expect(path("Shared") == na + [.integer(1)])
    #expect(path("Newer")?[1] == .string("EU Megaserver"))
    // Each path names the error's own row.
    for problem in problems {
        var value: LuaValue? = doc[CompanionData.variable]
        for key in problem.path.dropFirst() { value = value?.table?.entries.first { $0.key == key }?.value }
        let message = try #require(value?.table?["message"]?.string)
        #expect(problem.message.contains(message))
    }
}

@Test func companionSessionsComeFromEveryBlockOnceEach() throws {
    let login = companionTestStamp - 7200
    let lua = """
    EsoMacMinion_Data =
    {
        ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
            ["schema"] = 1, ["written"] = \(companionTestStamp),
            ["sessions"] = {
                [1] = { ["character"] = "1", ["loginAt"] = \(login), ["logoutAt"] = \(login + 3600) },
                [2] = { ["character"] = "2", ["loginAt"] = \(companionTestStamp - 600), ["logoutAt"] = \(companionTestStamp) },
            },
        } } },
        ["EU Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
            ["schema"] = 1, ["written"] = \(companionTestStamp - 86400),
            ["sessions"] = {
                [1] = { ["character"] = "1", ["loginAt"] = \(login), ["logoutAt"] = \(login + 60) },
                [2] = { ["character"] = "3", ["loginAt"] = \(companionTestStamp - 90000), ["logoutAt"] = \(companionTestStamp - 86400) },
            },
        } } },
    }
    """
    let snap = try #require(CompanionData.snapshot(SVDocument.parse(Data(lua.utf8))))
    #expect(snap.sessions.map(\.character) == ["3", "1", "2"])
    // The duplicate keeps the newest block's row.
    #expect(CompanionData.playedTime(characterID: "1", in: snap) == 3600)
}

@Test func luaErrorsFixedByAnUpdateInstalledSinceTheLastLoginAreHidden() throws {
    let lua = """
    EsoMacMinion_Data =
    {
        ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
            ["schema"] = 1, ["written"] = \(companionTestStamp),
            ["addons"] = { ["Boom"] = { ["addOnVersion"] = 4 } },
            ["errors"] = {
                [1] = { ["addon"] = "Boom", ["at"] = \(companionTestStamp), ["addonVersion"] = 4, ["count"] = 1, ["message"] = "boom" },
            },
        } } },
    }
    """
    let snap = try #require(CompanionData.snapshot(SVDocument.parse(Data(lua.utf8))))
    #expect(CompanionData.problems(from: snap, now: companionTestNow).contains { $0.kind == .luaError })
    #expect(!CompanionData.problems(from: snap, installedVersions: ["boom": 5], now: companionTestNow).contains { $0.kind == .luaError })
    #expect(CompanionData.problems(from: snap, installedVersions: ["boom": 4], now: companionTestNow).contains { $0.kind == .luaError })
    #expect(Manifest.parse("## Title: Boom\n## AddOnVersion: 5\n").addOnVersion == 5)
}
