import Foundation
import Testing
@testable import MacMinionKit

@Test func turnsKeysIntoWords() {
    let cases: [(String, String)] = [("showMatCost", "Show mat cost"), ("bAutoAccept", "Auto accept"), ("$LastCharacterName", "Last character name"),
                                     ("incomplete_colour", "Incomplete colour"), ("UIScale", "UI scale"), ("areTimestampsEnabled", "Are timestamps enabled"),
                                     ("TotalPrice", "Total price"), ("guild1Color", "Guild 1 color"), ("version", "Version"), ("bags", "Bags"),
                                     ("NA Megaserver", "NA Megaserver"), ("Ringil of Eskiath", "Ringil of Eskiath"), ("textcolor", "Textcolor"), ("zoneId", "Zone ID"), ("addonIds", "Addon IDs"), ("showHudCP", "Show HUD CP")]
    for (key, words) in cases { #expect(SVReadable.label(.string(key)) == words, "\(key)") }
    #expect(SVReadable.label(.integer(3)) == "#3")
}

@Test func recognizesSwitchesColorsDatesAndGold() throws {
    let now = Date(timeIntervalSince1970: 1_793_300_000)
    func show(_ lua: String, _ key: String) -> SVDisplay {
        let doc = SVDocument.parse(Data("V = { [\"\(key)\"] = \(lua) }".utf8))
        return SVReadable.display(doc["V"]!.table![key]!, key: .string(key), at: [.string("V")], names: nil, now: now)
    }
    #expect(show("true", "areTimestampsEnabled") == .toggle(true))
    #expect(show("{ [\"r\"] = 1, [\"g\"] = 0, [\"b\"] = 0, [\"a\"] = 0.5 }", "anything") == .color(red: 1, green: 0, blue: 0, alpha: 0.5))
    #expect(show("{ [1] = 1, [2] = 0, [3] = 0 }", "incompleteColour") == .color(red: 1, green: 0, blue: 0, alpha: 1))
    #expect(show("{ [1] = 1, [2] = 0, [3] = 0 }", "counts") == .table(count: 3, isList: true), "numbers without a color key are a list")
    let pink: SVDisplay = .color(red: Double(0xE9) / 255, green: Double(0x74) / 255, blue: Double(0xD8) / 255, alpha: 1)
    #expect(show("\"|cE974D8\"", "rank3") == pink)
    #expect(show("\"dc8122\"", "EnglishColorKeeps") != .text("dc8122"))
    #expect(show("\"dc8122\"", "tag") == .text("dc8122"), "hex without a color key stays text")
    #expect(show("1793288692", "listingTime") == .date(Date(timeIntervalSince1970: 1_793_288_692)))
    #expect(show("60", "dailyResetWarnTime") == .number("60"), "a duration isn't a date")
    #expect(show("1793288692", "count") == .number("1,793,288,692"), "a big number without a time key isn't a date")
    #expect(show("12850.5", "goldSpent") == .gold(12850.5))
    #expect(show("true", "useGoldLimit") == .toggle(true))
    #expect(show("20251007", "savedVarsVersion") == .number("20251007") && show("1360", "addonId") == .number("1360"))
    #expect(show("{ [\"a\"] = 1, [\"b\"] = 2 }", "x") == .table(count: 2, isList: false))
}

@Test func buildsSectionsThroughServersAndAccounts() throws {
    let doc = SVDocument.parse(Data("""
    WW =
    {
        ["NA Megaserver"] =
        {
            ["@SOLAEGIS"] =
            {
                ["$AccountWide"] = { ["showMatCost"] = true, ["matColor"] = { [1] = 1, [2] = 0.5, [3] = 0 }, ["filters"] = { ["a"] = true } },
                ["8796093036412335"] = { ["goldSpent"] = 12, ["zoneId"] = 3 },
            },
        },
    }
    """.utf8))
    let names = SVNameIndex.build(documents: ["ZO_Ingame.lua": SVDocument.parse(Data("""
    ZO_Ingame_SavedVariables = { ["Default"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = { ["NameChange"] = { ["8796093036412335"] = "Masisi" } } } } }
    """.utf8))], addons: nil)
    let sections = SVReadable.sheet(doc.variables, at: [], title: "WritWorthy", names: names)
    #expect(sections.map(\.title) == ["Every character", "Masisi (8796093036412335)"], "a character's name, with the ID it stands for")
    let shared = try #require(sections.first)
    #expect(shared.subtitle == "@SOLAEGIS · NA")
    #expect(shared.rows.map(\.label) == ["Filters", "Mat color", "Show mat cost"], "rows by label")
    #expect(shared.rows[1].display == .color(red: 1, green: 0.5, blue: 0, alpha: 1))
    #expect(shared.rows[0].display == .table(count: 1, isList: false), "a table inside a section is a row that opens")
    #expect(sections[1].rows.map(\.display) == [.gold(12), .number("3")])
    #expect(shared.rows[2].path == [.string("WW"), .string("NA Megaserver"), .string("@SOLAEGIS"), .string("$AccountWide"), .string("showMatCost")])
}

@Test func keepsEachAccountsSectionsTogether() {
    let doc = SVDocument.parse(Data("""
    ADR =
    {
        ["Default"] =
        {
            ["@SOLAEGIS"] =
            {
                ["Zirhli"] = { ["a"] = 1 },
                ["$AccountWide"] = { ["a"] = 1 },
                ["Masisi"] = { ["a"] = 1 },
            },
            ["@vavasour"] =
            {
                ["Pelatiah"] = { ["a"] = 1 },
                ["$AccountWide"] = { ["a"] = 1 },
            },
        },
    }
    """.utf8))
    let sections = SVReadable.sheet(doc.variables, at: [], title: "ADR", names: nil)
    #expect(sections.map { "\($0.subtitle ?? "") \($0.title)" } == [
        "@SOLAEGIS · Default Every character", "@SOLAEGIS · Default Masisi", "@SOLAEGIS · Default Zirhli",
        "@vavasour · Default Every character", "@vavasour · Default Pelatiah",
    ], "each account's shared settings, then its characters")
    let groups = SVReadable.grouped(sections)
    #expect(groups.map(\.title) == ["@SOLAEGIS · Default", "@vavasour · Default"])
    #expect(groups.map(\.sections.count) == [3, 2])
    // With no known megaserver, each account's tables sit in its Default folder.
    let outline = SVReadable.outline(sections)
    #expect(outline.map(\.account) == ["@SOLAEGIS", "@vavasour"])
    #expect(outline.map { $0.folders.map(\.title) } == [["Default"], ["Default"]])
    #expect(outline[0].folders[0].rows.map(\.title) == ["Every character", "Masisi", "Zirhli"])
}

/// The outline: account, then megaserver (Default last), then characters. Characters sit under their own
/// megaserver even under Default; a name NA and EU share there is listed under each.
@Test func outlinesByAccountThenMegaserver() {
    let doc = SVDocument.parse(Data("""
    ADR = { ["Default"] = { ["@SOLAEGIS"] = {
        ["$AccountWide"] = { ["a"] = 1 },
        ["8796093036412335"] = { ["a"] = 1 },
        ["8798292071266932"] = { ["a"] = 1 },
        ["Masisi"] = { ["a"] = 1 },
        ["Zirhli"] = { ["a"] = 1 },
    } },
    ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["8796093000000009"] = { ["b"] = 1 } } } }
    """.utf8))
    let names = SVNameIndex.build(documents: ["WW.lua": SVDocument.parse(Data("""
    WW = { ["Default"] = { ["@SOLAEGIS"] = {
        ["8796093036412335"] = { ["$LastCharacterName"] = "Masisi" },
        ["8798292071266932"] = { ["$LastCharacterName"] = "Masisi" },
        ["8796093000000009"] = { ["$LastCharacterName"] = "Zirhli" },
    } } }
    """.utf8))], addons: nil)
    let sections = SVReadable.sheet(doc.variables, at: [], title: "ADR", names: names)
    let outline = SVReadable.outline(sections)
    #expect(outline.map(\.account) == ["@SOLAEGIS"])
    let folders = outline[0].folders
    #expect(folders.map(\.title) == ["EU", "NA", "Default"], "real megaservers by name, then Default")
    #expect(folders.map { $0.rows.map(\.title) } == [["Masisi", "Masisi"], ["Masisi", "Masisi", "Zirhli", "Zirhli"], ["Every character"]],
            "\(folders.map { $0.rows.map(\.title) })")
    let rows = outline.flatMap(\.rows)
    #expect(Set(rows.map(\.id)).count == rows.count, "a table listed twice has two rows")
    let shared = rows.filter { $0.sectionID.hasSuffix("Masisi") }
    #expect(shared.count == 2 && Set(shared.map(\.sectionID)).count == 1 && Set(shared.compactMap(\.megaserver)) == ["NA Megaserver", "EU Megaserver"])
    #expect(rows.first { $0.sectionID.hasSuffix("8796093036412335") }?.help == "Masisi (8796093036412335)")
    #expect(!sections.contains { $0.title.contains(" and ") }, "no \"(EU and NA)\" titles")
}

/// What sheets look like for real files, read-only, run by hand:
///   MM_REAL_SV=~/Documents/Elder\ Scrolls\ Online/live/SavedVariables swift test --filter sheetsForARealFolder
@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_REAL_SV"] != nil))
func sheetsForARealFolder() throws {
    let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MM_REAL_SV"]!)
    for file in ["pChat.lua", "WritWorthy.lua", "PersonalAssistantJunk.lua", "LostTreasure.lua"] {
        guard let doc = try? SVDocument.read(folder.appending(path: file)) else { continue }
        let sections = SVReadable.sheet(doc.variables, at: [], title: file, names: nil)
        print("SHEET \(file): \(sections.count) sections: \(sections.prefix(4).map { "\($0.title) [\($0.subtitle ?? "")]" }.joined(separator: ", "))")
        for row in sections.first?.rows.prefix(8) ?? [] { print("   \(row.label) = \(row.display)") }
    }
}
