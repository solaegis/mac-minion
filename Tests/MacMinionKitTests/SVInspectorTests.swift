import Foundation
import Testing
@testable import MacMinionKit

private func doc(_ text: String) -> SVDocument { SVDocument.parse(Data(text.utf8)) }

private let ingame = doc("""
ZO_Ingame_SavedVariables =
{
    ["Default"] =
    {
        ["@SOLAEGIS"] =
        {
            ["$AccountWide"] =
            {
                ["NameChange"] =
                {
                    ["8796093036412335"] = "Masisi",
                },
            },
        },
    },
}
""")

private let chat = doc("""
PCHAT_OPTS =
{
    ["NA Megaserver"] =
    {
        ["@SOLAEGIS"] =
        {
            ["8796093036412335"] = { ["zoneId"] = 3, ["questId"] = 30, ["lastItem"] = "|H1:item:96175:4:22:0:0:0:0:0:0:0:0:0:0:0:1:9:0:1:0:10000:0|h|h" },
            ["8796093099999999"] = { ["$LastCharacterName"] = "Alpha Top" },
            ["8796093011111111"] = { ["setId"] = 19, ["achievementId"] = 1000 },
        },
    },
}
GS16DataSavedVariables = { ["itemLink"] = { ["|H0:item:43531:359:50:0:0:0:0:0:0:0:0:0:0:0:0:4:0:0:0:250:0|h|h"] = 7 }, ["guildNames"] = { ["Bandits Clan"] = 118 } }
GS17DataSavedVariables = { ["accountNames"] = { ["@Paltop"] = 21531 }, ["visitedEUTraders"] = { [487424] = { ["guildName"] = "Stendarr's Merchantry" } } }
GS00DataSavedVariables = { ["dataeu"] = { [1] = { ["sales"] = { [1] = { ["itemLink"] = 7, ["seller"] = 21531, ["guild"] = 118, ["guildId"] = 487424 } } } } }
""")

@Test func labelsTheSavedVarsLevels() {
    let v: LuaKey = .string("PCHAT_OPTS")
    #expect(SVLevel.of(.string("NA Megaserver"), at: [v]) == .profile)
    #expect(SVLevel.of(.string("Default"), at: [v]) == .profile)
    #expect(SVLevel.megaserver(ofProfile: "Default") == nil && SVLevel.megaserver(ofProfile: "EU Megaserver") == "EU Megaserver")
    #expect(SVLevel.of(.string("Masisi"), at: [v, .string("Default"), .string("@SOLAEGIS")]) == .characterName)
    #expect(SVLevel.of(.string("Masisi"), at: [v, .string("Default"), .string("$AllAccounts")]) == nil)
    #expect(SVLevel.of(.string("characters"), at: [.string("IIFA_DATABASE"), .string("@SOLAEGIS"), .string("x")]) == nil)
    #expect(SVLevel.of(.string("@SOLAEGIS"), at: [v, .string("NA Megaserver")]) == .account)
    #expect(SVLevel.of(.string("8796093036412335"), at: [v, .string("NA Megaserver"), .string("@SOLAEGIS")]) == .character)
    #expect(SVLevel.of(.string("Masisi^Fx"), at: [v, .string("Default"), .string("@SOLAEGIS")]) == .character)
    #expect(SVLevel.of(.string("$AccountWide"), at: [v, .string("Default"), .string("@SOLAEGIS")]) == .accountWide)
    #expect(SVLevel.of(.string("NA Megaserver"), at: [v, .string("x")]) == nil)
    #expect(!CharacterID.isID("4628250053726082675") && !CharacterID.isID("1234567890123456"), "item instance IDs aren't characters")
}

@Test func decodesItemLinks() throws {
    let link = try #require(ItemLink.parse("|H1:item:96175:4:22:0:0:0:0:0:0:0:0:0:0:0:1:9:0:1:0:10000:0|hMasisi's Blade^n|h"))
    #expect(link.itemID == 96175 && link.subtype == 4 && link.level == 22 && link.style == 9)
    #expect(link.bound && !link.crafted && !link.stolen && link.name == "Masisi's Blade^n")
    #expect(ItemLink.parse("not a link") == nil)
}

@Test func namesIDsFromSavedVariables() throws {
    let index = SVNameIndex.build(documents: ["ZO_Ingame.lua": ingame, "pChat.lua": chat, "GS.lua": chat], addons: nil)
    let char = try #require(index.name(forKey: .string("8796093036412335"), at: []))
    #expect(char.label == "Masisi · character" && char.source == "ZO_Ingame › NameChange")
    #expect(index.name(forKey: .string("8796093099999999"), at: [])?.title == "Alpha Top")
    #expect(index.name(forKey: .string("8796093011111111"), at: [])?.title == "Unknown character")
    #expect(index.name(forKey: .string("@SOLAEGIS"), at: [])?.detail == "yours")
    #expect(index.name(forValue: .string("@Paltop"), key: .string("x"), at: [])?.detail == nil)

    let gs: [LuaKey] = [.string("GS00DataSavedVariables"), .string("dataeu"), .integer(1), .string("sales"), .integer(1)]
    #expect(index.name(forValue: .integer(7), key: .string("itemLink"), at: gs)?.title == "Item 43531")
    #expect(index.name(forValue: .integer(21531), key: .string("seller"), at: gs)?.title == "@Paltop")
    #expect(index.name(forValue: .integer(118), key: .string("guild"), at: gs)?.title == "Bandits Clan")
    #expect(index.name(forValue: .integer(487424), key: .string("guildId"), at: gs)?.title == "Stendarr's Merchantry")
    #expect(index.name(forValue: .integer(7), key: .string("itemLink"), at: [.string("Other")]) == nil, "only in LibGuildStore's files")

    let item = try #require(index.name(forValue: .string("|H1:item:96175:4:22:0:0:0:0:0:0:0:0:0:0:0:1:9:0:1:0:10000:0|h|h"), key: .string("x"), at: []))
    #expect(item.kind == .item && item.detail == "level 22 · style 9 · bound")
    #expect(item.uesp?.absoluteString == "https://esoitem.uesp.net/itemLink.php?itemid=96175")
    #expect(index.name(forValue: .integer(1000), key: .string("achievementId"), at: [])?.uesp != nil)
}

@Test func namesIDsFromLibraryDataFiles() throws {
    let fm = FileManager.default
    let addons = fm.temporaryDirectory.appending(path: "mm-libs-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: addons) }
    let files: [String: String] = [
        "LibSets/Data/LibSets_Data_SetNames.lua": """
        local lib = LibSets
        if lib.x then return end
            setDataPreloaded[LIBSETS_TABLEKEY_SETNAMES]={[19]={["de"]="Gewänder",["en"]="Vestments of the Warlock"},[20]={["en"]="Witchman Armor"}}
        """,
        "LibSets/Data/LibSets_Data_SetItemIds.lua": "-- 6* paste the result into setDataPreloaded[LIBSETS_TABLEKEY_SETITEMIDS], starting with {\n    setDataPreloaded[LIBSETS_TABLEKEY_SETITEMIDS]={[19]={[1]=22762,[2]=\"29513,3\"},[20]={[1]=10973}}\n",
        "Bundle/libs/LibZone/LibZone_Data.lua": "local x = 1\n--comment\npreloadedZoneNames = {\n\t[\"en\"] = {\n\t\t[3] = \"Glenumbra\", [11] = \"Vaults of Madness\",\n\t},\n\t[\"de\"] = { [3] = \"Glenumbra\" },\n}\n",
        "LibQuestData/quest_names/LibQuestData_QuestNames_en.lua": "local lib = _G[\"LibQuestData\"]\nlib.quest_names[\"en\"] = {\n  [30] = \"Dark Brotherhood Assassination\",\n}\n",
    ]
    for (path, text) in files {
        let url = addons.appending(path: path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    let index = SVNameIndex.build(documents: ["pChat.lua": chat], addons: addons)
    #expect(index.sets == [19: "Vestments of the Warlock", 20: "Witchman Armor"])
    #expect(index.itemSets[29516] == 19 && index.itemSets[29517] == nil && index.itemSets[10973] == 20)
    #expect(index.zones == [3: "Glenumbra", 11: "Vaults of Madness"], "a library nested in another addon counts")
    #expect(index.quests[30] == "Dark Brotherhood Assassination")
    let char: [LuaKey] = [.string("PCHAT_OPTS"), .string("NA Megaserver"), .string("@SOLAEGIS"), .string("8796093036412335")]
    #expect(index.name(forValue: .integer(3), key: .string("zoneId"), at: char)?.label == "Glenumbra · zone")
    #expect(index.name(forValue: .integer(30), key: .string("questId"), at: char)?.source == "LibQuestData")
    #expect(index.name(forValue: .integer(19), key: .string("setId"), at: char)?.title == "Vestments of the Warlock")
    #expect(index.name(forValue: .integer(22762), key: .string("itemId"), at: char)?.detail == "Vestments of the Warlock set")
}

@Test func treeChildrenAreMadeOnFirstUseAndFast() throws {
    var text = "Big =\n{\n"
    for i in 1...100_000 { text += "    [\(i)] = \"row \(i)\",\n" }
    text += "}\n"
    let d = doc(text)
    let root = try #require(SVNode.roots(d).first)
    let start = Date()
    let rows = try #require(root.children)
    #expect(rows.count == 100_000 && Date().timeIntervalSince(start) < 1)
    #expect(rows[41].path == [.string("Big"), .integer(42)] && rows[41].children == nil)
    #expect(rows[41].bytes == "[42] = \"row 42\"".utf8.count)
}

/// A read-only look at what the index finds in a real game folder, run by hand:
///   MM_REAL_SV=~/Documents/Elder\ Scrolls\ Online/live/SavedVariables swift test -c release --filter namesARealFolder
@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_REAL_SV"] != nil))
func namesARealFolder() throws {
    let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MM_REAL_SV"]!)
    let start = Date()
    var docs: [String: SVDocument] = [:]
    for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where url.pathExtension == "lua" {
        docs[url.lastPathComponent] = try SVDocument.read(url)
    }
    let index = SVNameIndex.build(documents: docs, addons: folder.deletingLastPathComponent().appending(path: "AddOns"))
    let refs = SVReferenceIndex.build(documents: docs, names: index)
    let top = refs.hits.max { $0.value.count < $1.value.count }
    print("REFS \(refs.targetCount) IDs, \(refs.hitCount) mentions; most: \(top?.key.description ?? "") \(top?.value.count ?? 0)")
    let t0 = Date()
    if let masisi = index.characters.first(where: { $0.value.name == "Masisi" })?.key {
        let n = SVNeighborhood.build(SVTarget(.character, masisi), refs: refs, names: index) { docs[$0] }
        print("NEAR Masisi in \(String(format: "%.2f", Date().timeIntervalSince(t0))) s: files \(n.files.prefix(6).map { "\($0.file)×\($0.count)" }), "
              + "next to \(n.neighbors.map { "\(index.title(for: $0.target) ?? $0.target.description)×\($0.count)" })")
    }
    let usage = SVUsage.build(documents: docs, names: index)
    func head(_ b: [SVUsage.Bucket], _ n: Int) -> String { b.prefix(n).map { "\($0.title)\($0.flagged ? "!" : "") \($0.bytes / 1024)K" }.joined(separator: ", ") }
    print("USAGE characters \(usage.characters.count) (\(usage.characters.filter(\.flagged).count) unknown): \(head(usage.characters, 8))")
    print("USAGE accounts \(usage.accounts.count) (\(usage.accounts.filter(\.flagged).count) others): \(head(usage.accounts, 5))")
    print("USAGE servers: \(head(usage.servers, 5))")
    for b in usage.biggest.prefix(10) { print("USAGE table \(b.bytes / 1024)K \(b.detail ?? "")") }
    print("NAMES in \(String(format: "%.2f", Date().timeIntervalSince(start))) s: \(index.characters.count) characters, \(index.ownAccounts.sorted()) yours, "
          + "\(index.guilds.count) guilds, \(index.sets.count) sets (\(index.itemSets.count) items), \(index.zones.count) zones, \(index.quests.count) quests, "
          + "guild store \(index.guildStoreLinks.count) links / \(index.guildStoreAccounts.count) accounts / \(index.guildStoreGuilds.count) guilds")
    #expect(!index.characters.isEmpty && !index.sets.isEmpty && !index.zones.isEmpty && !index.quests.isEmpty)
}

@Test func findsEveryPlaceAnIDAppears() throws {
    let docs = ["ZO_Ingame.lua": ingame, "pChat.lua": chat]
    let names = SVNameIndex.build(documents: docs, addons: nil)
    let refs = SVReferenceIndex.build(documents: docs, names: names)
    #expect(refs.files == ["ZO_Ingame.lua", "pChat.lua"])

    // Masisi: a key in both files.
    let masisi = SVTarget(.character, "8796093036412335")
    #expect(refs.targets(matching: "masisi", names: names) == [masisi])
    let places = try #require(refs.hits[masisi]).map { hit -> String in
        let doc = docs[refs.files[Int(hit.file)]]!
        return doc.entry(at: Int(hit.offset))!.path.map(\.description).joined(separator: " › ")
    }
    #expect(Set(places) == ["ZO_Ingame_SavedVariables › Default › @SOLAEGIS › $AccountWide › NameChange › 8796093036412335",
                            "PCHAT_OPTS › NA Megaserver › @SOLAEGIS › 8796093036412335"])

    // Item 43531: a link used as a key in LibGuildStore's index, and the number standing for it in a sale.
    let item = SVTarget(.item, "43531")
    let itemHits = try #require(refs.hits[item])
    let paths = itemHits.map { docs["pChat.lua"]!.entry(at: Int($0.offset))!.path.last!.description }
    #expect(Set(paths) == ["|H0:item:43531:359:50:0:0:0:0:0:0:0:0:0:0:0:0:4:0:0:0:250:0|h|h", "itemLink"])
    #expect(refs.hits[SVTarget(.item, "96175")]?.count == 1)

    // Accounts and guilds through LibGuildStore's numbers; guild by ID where a file pairs it with a name.
    #expect(refs.hits[SVTarget(.account, "@Paltop")]?.count == 2, "the index entry and the sale")
    #expect(refs.hits[SVTarget(.guild, "487424")]?.count == 1)
    #expect(refs.hits[SVTarget(.guild, "Bandits Clan")]?.count == 1)
    #expect(refs.hits[SVTarget(.zone, "3")]?.count == 1 && refs.hits[SVTarget(.quest, "30")]?.count == 1)

    // A plain ID finds its target; nothing matches nonsense.
    #expect(refs.targets(matching: "43531", names: names) == [item])
    #expect(refs.targets(matching: "zzz-nothing", names: names).isEmpty)
    #expect(ingame.entry(at: 999_999) == nil)
}

@Test func totalsSpaceByCharacterAccountServerAndTable() throws {
    let pad = String(repeating: "x", count: 2_000)
    let usageDoc = SVDocument.parse(Data("""
    U_Vars =
    {
        ["NA Megaserver"] =
        {
            ["@SOLAEGIS"] =
            {
                ["8796093036412335"] = { ["notes"] = "\(pad)" },
                ["8796093079837777"] = { ["a"] = 1 },
            },
        },
        ["Default"] =
        {
            ["@SOLAEGIS"] =
            {
                ["$AccountWide"] = { ["roster"] = { ["@Friend"] = { ["note"] = "\(pad)" }, ["@Other"] = 3 } },
            },
        },
    }
    """.utf8))
    let docs = ["U.lua": usageDoc, "ZO_Ingame.lua": ingame]
    let usage = SVUsage.build(documents: docs, names: SVNameIndex.build(documents: docs, addons: nil))
    #expect(usage.totalBytes == usageDoc.byteCount + ingame.byteCount)
    #expect(usage.files.first?.id == "U.lua")

    let masisi = try #require(usage.characters.first)
    #expect(masisi.title == "Masisi" && masisi.detail == "8796093036412335" && masisi.files == 2 && masisi.bytes > 2_000 && !masisi.flagged)
    let unknown = try #require(usage.characters.first { $0.id == "8796093079837777" })
    #expect(unknown.flagged && unknown.detail == "Unknown character")

    #expect(usage.accounts.map(\.id) == ["@SOLAEGIS", "@Friend"], "yours first; @Other holds no data")
    #expect(usage.accounts.first?.detail == "yours" && usage.accounts.last?.flagged == true)
    #expect(Set(usage.servers.map(\.id)) == ["NA Megaserver", "Default"])
    #expect(usage.servers.first { $0.id == "Default" }?.detail == "no profile: shared across megaservers")

    // The roster holds its weight in one child (@Friend), so @Friend is listed rather than every table above it.
    let titles = usage.biggest.map(\.title)
    #expect(titles.contains("@Friend") && !titles.contains("roster") && !titles.contains("$AccountWide"))
    #expect(usage.biggest.first { $0.title == "@Friend" }?.path == [.string("U_Vars"), .string("Default"), .string("@SOLAEGIS"),
                                                                   .string("$AccountWide"), .string("roster"), .string("@Friend")])
    #expect(zip(usage.biggest, usage.biggest.dropFirst()).allSatisfy { $0.bytes >= $1.bytes })
}

@Test func readsKeyPathsAsCopyPathWritesThem() {
    #expect(LuaPath.parse("PCHAT_OPTS[\"NA Megaserver\"][\"@SOLAEGIS\"][1]") == [.string("PCHAT_OPTS"), .string("NA Megaserver"), .string("@SOLAEGIS"), .integer(1)])
    #expect(LuaPath.parse("V[\"say \\\"hi\\\"\"][true]") == [.string("V"), .string("say \"hi\""), .bool(true)])
    #expect(LuaPath.parse("V › NA Megaserver › 8796093036412335 › 2") == [.string("V"), .string("NA Megaserver"), .integer(8796093036412335), .integer(2)])
    // A typed number finds the character ID stored as a string.
    let typed = LuaPath.parse("PCHAT_OPTS › NA Megaserver › @SOLAEGIS › 8796093036412335 › zoneId")!
    #expect(chat.resolve(typed)?.path[3] == .string("8796093036412335"))
    if case .integer(3)? = chat.resolve(typed)?.value {} else { Issue.record("zoneId") }
    #expect(chat.resolve([.string("PCHAT_OPTS"), .string("nope")]) == nil)
    #expect(LuaPath.parse("") == [] && LuaPath.parse("V[\"open") == nil && LuaPath.parse("V[x]") == nil)
}

@Test func readsTheCompanionRosterAndBreaksSpaceDownByCharacter() throws {
    let companion = SVDocument.parse(Data("""
    EsoMacMinion_Data =
    {
        ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = { ["schema"] = 1, ["characters"] =
        {
            ["8796093036412335"] = { ["name"] = "Masisi", ["class"] = 3, ["race"] = 9, ["level"] = 50, ["champion"] = 2410, ["lastPlayed"] = 1793288692 },
            ["8796093079837777"] = { ["name"] = "Renamed Now", ["class"] = 117, ["level"] = 12 },
        } } } },
    }
    """.utf8))
    let roster = CompanionData.roster(companion)
    let masisi = try #require(roster["8796093036412335"])
    #expect(masisi.className == "Nightblade" && masisi.raceName == "Khajiit" && masisi.level == 50 && masisi.server == "NA Megaserver")
    #expect(masisi.lastPlayed == Date(timeIntervalSince1970: 1_793_288_692))
    #expect(roster["8796093079837777"]?.className == "Arcanist")

    let docs = ["EsoMacMinion_Data.lua": companion, "ZO_Ingame.lua": ingame, "pChat.lua": chat]
    let names = SVNameIndex.build(documents: docs, addons: nil)
    #expect(names.characters["8796093079837777"]?.name == "Renamed Now", "the roster names characters no other file does")
    #expect(names.characters["8796093036412335"]?.source == "MacMinion Companion")

    let usage = SVUsage.build(documents: docs, names: names)
    let card = try #require(usage.characters.first { $0.id == "8796093036412335" })
    #expect(card.servers == ["NA Megaserver"], "Default drops out when a real server holds it")
    #expect(Set(card.byFile.map(\.file)) == ["EsoMacMinion_Data.lua", "ZO_Ingame.lua", "pChat.lua"])
    #expect(card.byFile.reduce(0) { $0 + $1.bytes } == card.bytes)
}

@Test func findsWhatSitsNextToAnID() throws {
    let docs = ["ZO_Ingame.lua": ingame, "pChat.lua": chat]
    let names = SVNameIndex.build(documents: docs, addons: nil)
    let refs = SVReferenceIndex.build(documents: docs, names: names)

    // A character: the IDs inside her table.
    let masisi = SVNeighborhood.build(SVTarget(.character, "8796093036412335"), refs: refs, names: names) { docs[$0] }
    #expect(masisi.files.map(\.file).sorted() == ["ZO_Ingame.lua", "pChat.lua"])
    #expect(Set(masisi.neighbors.map(\.target)) == [SVTarget(.zone, "3"), SVTarget(.quest, "30"), SVTarget(.item, "96175")])

    // An item in a sale: the seller and guild beside it, and the index entry naming it.
    let item = SVNeighborhood.build(SVTarget(.item, "43531"), refs: refs, names: names) { docs[$0] }
    let around = Set(item.neighbors.map(\.target))
    #expect(around.contains(SVTarget(.account, "@Paltop")) && around.contains(SVTarget(.guild, "Bandits Clan")))
    #expect(around.contains(SVTarget(.guild, "487424")), "the sale's guild ID too")
    #expect(!around.contains(SVTarget(.item, "43531")), "never itself")

    // Siblings in a table keyed by character are the rest of a list, not connections.
    let roster = SVDocument.parse(Data("R = { [\"8796093036412335\"] = \"Masisi\", [\"8796093079837777\"] = \"Other\", [\"8798292071293572\"] = \"Third\" }".utf8))
    let rosterDocs = ["R.lua": roster]
    let rosterNames = SVNameIndex.build(documents: rosterDocs, addons: nil)
    let rosterRefs = SVReferenceIndex.build(documents: rosterDocs, names: rosterNames)
    #expect(SVNeighborhood.build(SVTarget(.character, "8796093036412335"), refs: rosterRefs, names: rosterNames) { rosterDocs[$0] }.neighbors.isEmpty)

    let nothing = SVNeighborhood.build(SVTarget(.zone, "999"), refs: refs, names: names) { docs[$0] }
    #expect(nothing.files.isEmpty && nothing.neighbors.isEmpty)
}

/// Per-character settings on a real folder, to ground the character and addon views. Run by hand:
///   MM_REAL_SV=~/Documents/Elder\ Scrolls\ Online/live/SavedVariables swift test -c release --filter perCharacterSettingsInARealFolder
@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_REAL_SV"] != nil))
func perCharacterSettingsInARealFolder() throws {
    let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MM_REAL_SV"]!)
    var docs: [String: SVDocument] = [:]
    for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where url.pathExtension == "lua" {
        docs[url.lastPathComponent] = try SVDocument.read(url)
    }
    let names = SVNameIndex.build(documents: docs, addons: nil)
    var rows: [(file: String, chars: Int, keys: Int, differing: Int, shared: Int)] = []
    for (file, doc) in docs {
        var perChar: [String: LuaTable] = [:]
        var shared = 0
        func walk(_ t: LuaTable, _ path: [LuaKey]) {
            for e in t.entries {
                let level = SVLevel.of(e.key, at: path)
                if level == .character, let inner = e.value.table { perChar[e.key.description] = inner; continue }
                if level == .accountWide, let inner = e.value.table { shared += inner.count; continue }
                if path.count < 3, let inner = e.value.table { walk(inner, path + [e.key]) }
            }
        }
        for v in doc.variables { if let t = v.value.table { walk(t, [v.key]) } }
        guard !perChar.isEmpty else { continue }
        var values: [String: Set<String>] = [:]
        for (_, t) in perChar {
            for e in t.entries where e.value.table == nil { values[e.key.description, default: []].insert(InspectorPlain.text(e.value)) }
        }
        rows.append((file, perChar.count, values.count, values.values.filter { $0.count > 1 }.count, shared))
    }
    print("PERCHAR \(rows.count) files keep per-character settings; \(names.characters.count) characters named")
    let matrix = SettingsMatrix.build(documents: docs, names: names)
    print("MATRIX \(matrix.addons.count) addons x \(matrix.characterIDs.count) characters")
    for addon in matrix.addons { print("  \(addon.file): \(addon.characters.count) chars, \(addon.keys.count) keys, \(addon.differing.count) differ, shared \(addon.shared)") }
    if let m = names.characters.first(where: { $0.value.name == "Masisi" })?.key {
        print("MASISI odd: \(matrix.addons.flatMap { a in a.oddOnesOut(m).map { "\(a.file):\($0.key)=\($0.setting.text) (usually \($0.usual.text))" } }.prefix(8))")
    }
    for r in rows.sorted(by: { $0.chars > $1.chars }).prefix(25) {
        print("  \(r.file): \(r.chars) characters, \(r.keys) plain settings, \(r.differing) differ between characters, \(r.shared) shared")
    }
}

enum InspectorPlain {
    static func text(_ v: LuaValue) -> String {
        switch v {
        case .string(let s): s
        case .integer(let n): String(n)
        case .number(let d): String(d)
        case .bool(let b): String(b)
        default: ""
        }
    }
}

@Test func buildsTheSettingsMatrixAndFindsOddOnesOut() throws {
    let doc = SVDocument.parse(Data("""
    WW =
    {
        ["NA Megaserver"] =
        {
            ["@SOLAEGIS"] =
            {
                ["$AccountWide"] = { ["a"] = 1, ["b"] = 2, ["c"] = 3 },
                ["8796093036412335"] = { ["autoCraft"] = false, ["maxWrits"] = 10, ["color"] = { ["r"] = 1, ["g"] = 0, ["b"] = 0 }, ["deep"] = { ["inner"] = 1 } },
                ["8798292071293572"] = { ["autoCraft"] = true, ["maxWrits"] = 10, ["color"] = { ["r"] = 1, ["g"] = 0, ["b"] = 0 }, ["deep"] = { ["inner"] = 1 } },
                ["8796093079837777"] = { ["autoCraft"] = true, ["maxWrits"] = 10, ["color"] = { ["r"] = 0, ["g"] = 1, ["b"] = 0 }, ["deep"] = { ["inner"] = 1 } },
            },
        },
        ["Default"] = { ["@SOLAEGIS"] = { ["Masisi"] = { ["onlyByName"] = true, ["knowledge"] = "%%%%#EaLTR%%%%y%%%%%yh0l%%VkR%%tk#%%%%%%%%72v%%%%%%%#%ym01V%%%%%%%%%y%Vo%%V%#Uxv2tX000b" } } },
    }
    """.utf8))
    let docs = ["WW.lua": doc, "Solo.lua": SVDocument.parse(Data("Solo = { [\"Default\"] = { [\"@SOLAEGIS\"] = { [\"8796093036412335\"] = { [\"x\"] = 1 } } } }".utf8)),
                "ZO_Ingame.lua": ingame]
    let matrix = SettingsMatrix.build(documents: docs, names: SVNameIndex.build(documents: docs, addons: nil))
    let ww = try #require(matrix.addon("WW.lua"))
    #expect(ww.shared == 3)
    #expect(ww.characters.count == 3)
    #expect(ww.keys == ["Auto craft", "Color", "Deep › Inner", "Max writs", "Only by name"], "long encoded data isn't a setting: \(ww.keys)")
    #expect(Set(ww.differing) == ["Auto craft", "Color"])
    #expect(ww.same == ["Deep › Inner", "Max writs"] && ww.partial == ["Only by name"], "a key only Masisi has isn't the same on every character")
    let masisi = "8796093036412335"
    let odd = ww.oddOnesOut(masisi)
    #expect(odd.map(\.key) == ["Auto craft"] && odd.first?.usual.text == "true")
    #expect(ww.oddOnesOut("8796093079837777").map(\.key) == ["Color"])
    let groups = ww.values(of: "Auto craft")
    #expect(groups.map { $0.characters.count } == [2, 1] && groups.last?.characters == [masisi])
    #expect(ww.characters[masisi]?["Only by name"] != nil, "a table keyed by her name counts as hers")
    #expect(matrix.cell("WW.lua", masisi)?.odd == 1 && matrix.cell("WW.lua", masisi)?.settings == 5, "\(String(describing: matrix.cell("WW.lua", masisi)))")
    #expect(matrix.onlyHere(masisi) == ["Solo.lua"])
    #expect(matrix.characterIDs.count == 3)

    // Masisi beside the second character: Auto craft differs, and only Masisi has a setting kept by name.
    let compared = matrix.compare(masisi, "8798292071293572")
    let wwCompared = try #require(compared.first { $0.file == "WW.lua" })
    #expect(wwCompared.differing.map(\.key) == ["Auto craft"] && wwCompared.differing[0].a.text == "false")
    #expect(wwCompared.onlyA.map(\.key) == ["Only by name"] && wwCompared.onlyB.isEmpty)
    #expect(compared.contains { $0.file == "Solo.lua" && $0.onlyA.map(\.key) == ["X"] })
    #expect(matrix.compare(masisi, masisi).allSatisfy { $0.differing.isEmpty && $0.onlyA.isEmpty }, "a character matches itself")
}

@Test func groupsCharactersByAccountThenMegaserver() throws {
    let doc = SVDocument.parse(Data("""
    HM =
    {
        ["NA Megaserver"] =
        {
            ["@Zed"] = { ["8796093000000003"] = { ["a"] = 1 } },
            ["@Amy"] = { ["8796093000000002"] = { ["a"] = 1 }, ["8796093000000001"] = { ["a"] = 2 } },
        },
        ["EU Megaserver"] = { ["@Amy"] = { ["8798292000000004"] = { ["a"] = 3 } } },
        ["Default"] = { ["@Amy"] = { ["8796093000000001"] = { ["b"] = 1 } } },
    }
    """.utf8))
    let names = SVNameIndex.build(documents: ["ZO_Ingame.lua": SVDocument.parse(Data("""
    ZO_Ingame_SavedVariables = { ["Default"] = { ["@Amy"] = { ["$AccountWide"] = { ["NameChange"] = {
        ["8796093000000001"] = "Zara", ["8796093000000002"] = "Bo", ["8796093000000003"] = "Cy", ["8798292000000004"] = "Di",
    } } } } }
    """.utf8))], addons: nil)
    let matrix = SettingsMatrix.build(documents: ["HM.lua": doc], names: names)
    #expect(matrix.accounts.map(\.account) == ["@Amy", "@Zed"])
    let amy = try #require(matrix.accounts.first)
    #expect(amy.servers.map(\.server) == ["EU Megaserver", "NA Megaserver"])
    #expect(amy.servers.last?.characters == ["8796093000000002", "8796093000000001"], "by name: Bo, then Zara")
    #expect(matrix.homes["8796093000000001"]?.server == "NA Megaserver", "a real megaserver wins over Default")
    #expect(matrix.characterIDs == ["8798292000000004", "8796093000000002", "8796093000000001", "8796093000000003"])
    #expect(SettingsMatrix.shortServer("EU Megaserver") == "EU")
}

@Test func keepsTwoCharactersWithOneNameApart() throws {
    let eu = "8798292071266932", na = "8796093036412335"
    let docs = [
        "ZO_Ingame.lua": SVDocument.parse(Data("""
        ZO_Ingame_SavedVariables = { ["Default"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = { ["NameChange"] = {
            ["\(eu)"] = "Masisi", ["\(na)"] = "Masisi",
        } } } } }
        """.utf8)),
        "AA.lua": SVDocument.parse(Data("""
        AA = {
            ["EU Megaserver"] = { ["@SOLAEGIS"] = { ["\(eu)"] = { ["x"] = 1 } } },
            ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["\(na)"] = { ["x"] = 2 }, ["Masisi"] = { ["y"] = 1 } } },
        }
        """.utf8)),
        "Byname.lua": SVDocument.parse(Data("""
        Byname = { ["Default"] = { ["@SOLAEGIS"] = { ["Masisi"] = { ["z"] = 1 } } } }
        """.utf8)),
    ]
    let matrix = SettingsMatrix.build(documents: docs, names: SVNameIndex.build(documents: docs, addons: nil))
    #expect(matrix.homes[eu]?.server == "EU Megaserver" && matrix.homes[na]?.server == "NA Megaserver",
            "a name-keyed table on NA doesn't move the EU Masisi: \(matrix.homes)")
    #expect(matrix.accounts.first?.servers.map(\.characters) == [[eu], [na]])
    let aa = try #require(matrix.addon("AA.lua"))
    #expect(aa.characters[na]?["Y"] != nil && aa.characters[eu]?["Y"] == nil, "a name on NA is the NA Masisi")
    #expect(matrix.addon("Byname.lua") == nil, "a name under Default could be either Masisi, so it's neither")
}

/// Prints every character's account and megaserver in a real folder:
///   MM_REAL_SV=~/Documents/Elder\ Scrolls\ Online/live/SavedVariables swift test -c release --filter charactersByAccountInARealFolder
@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_REAL_SV"] != nil))
func charactersByAccountInARealFolder() throws {
    let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MM_REAL_SV"]!)
    var docs: [String: SVDocument] = [:]
    for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where url.pathExtension == "lua" {
        docs[url.lastPathComponent] = try SVDocument.read(url)
    }
    let names = SVNameIndex.build(documents: docs, addons: nil)
    let matrix = SettingsMatrix.build(documents: docs, names: names)
    for account in matrix.accounts {
        for server in account.servers {
            print("\(account.account) \(server.server): " + server.characters.map { "\(names.characters[$0]?.name ?? "?") \($0.prefix(4))" }.joined(separator: ", "))
        }
    }
}
