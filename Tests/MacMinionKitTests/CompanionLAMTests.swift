import Foundation
import Testing
@testable import MacMinionKit

private let companionLua = #"""
EsoMacMinion_Data = {
    ["NA Megaserver"] = { ["@ME"] = { ["$AccountWide"] = {
        ["schema"] = 1, ["written"] = 1794706243,
        ["layouts"] = { ["lam"] = {
            ["WritWorthyPanel"] = { ["addon"] = "WritWorthy", ["name"] = "WritWorthy", ["controls"] = {
                [1] = { ["type"] = "slider", ["name"] = "Writs to keep", ["min"] = 0, ["max"] = 50, ["step"] = 5, ["default"] = 10,
                        ["tooltip"] = "How many writs to hold." },
                [2] = { ["type"] = "dropdown", ["name"] = "Mode", ["choices"] = { [1] = "Never", [2] = "Always" },
                        ["choicesValues"] = { [1] = 0, [2] = 1 }, ["submenu"] = "Crafting" },
                [3] = { ["type"] = "dropdown", ["name"] = "Font", ["choices"] = { [1] = "Univers", [2] = "Futura" } },
            } },
        } },
        ["lookups"] = { ["answers"] = { ["ability:61919"] = { ["name"] = "Merciless Resolve" }, ["cp:59"] = { ["name"] = "Rejuvenation" } } },
    } } },
}
"""#

private let source = #"""
local options = {
    { type = "slider", name = "Writs to keep", min = 0, max = 100, getFunc = function() return WW.sv.maxWrits end },
    { type = "dropdown", name = "Mode", choices = WW.ModeNames(), getFunc = function() return WW.sv.mode end },
    { type = "dropdown", name = function() return "Font" end, getFunc = function() return WW.sv.font end },
}
"""#

@Test func readsTheCompanionsSettingsPanels() throws {
    let snap = try #require(CompanionData.snapshot(SVDocument.parse(Data(companionLua.utf8))))
    let panel = try #require(snap.lamPanels["WritWorthyPanel"])
    #expect(panel.addon == "WritWorthy" && panel.controls.count == 3)
    let slider = panel.controls[0]
    #expect(slider.min == 0 && slider.max == 50 && slider.step == 5 && slider.defaultValue == "10" && slider.tooltip == "How many writs to hold.")
    let mode = panel.controls[1]
    #expect(mode.control.choices == [.init(value: "0", label: "Never"), .init(value: "1", label: "Always")] && mode.submenu == "Crafting")
    #expect(panel.controls[2].control.choices.map(\.value) == ["Univers", "Futura"], "without values, the label is saved")
    #expect(snap.answers["ability:61919"]?.name == "Merciless Resolve" && snap.answers["cp:59"]?.name == "Rejuvenation")
}

@Test func theGamesControlWinsOverTheSource() throws {
    let snap = try #require(CompanionData.snapshot(SVDocument.parse(Data(companionLua.utf8))))
    var names = SVSourceNames.parse([source])
    #expect(names.control(for: .string("maxWrits"), at: [])?.range == 0...100)
    #expect(names.control(for: .string("mode"), at: [])?.choices.isEmpty ?? true, "choices built at run time: the source can't see them")
    let reached = names.applyCompanion(snap.lamPanels["WritWorthyPanel"]?.controls ?? [])
    #expect(reached == 2, "Font's name is a function in the source, so it can't be matched")
    let writs = try #require(names.control(for: .string("maxWrits"), at: []))
    #expect(writs.range == 0...50 && writs.step == 5 && writs.defaultValue == "10")
    #expect(names.name(for: .string("maxWrits"), at: [])?.detail == "How many writs to hold.")
    #expect(names.control(for: .string("mode"), at: [])?.choice(for: .integer(1))?.label == "Always")
    #expect(SVSourceNames.withoutAI(names).control(for: .string("maxWrits"), at: [])?.range == 0...100, "the cache keeps the source alone")
}

@Test func listsAIReadAsIDsAreAskedOfTheCompanion() throws {
    var names = SVSourceNames()
    names.addAI(SVAIField(idKind: "ability"), key: "tracked", parent: "")
    names.addAI(SVAIField(idKind: "cp"), key: "slotted", parent: "")
    #expect(names.hasIDKinds)
    let doc = SVDocument.parse(Data(#"SV = { ["Default"] = { tracked = { 61919, 40195, 61919 }, slotted = 59, other = { 1, 2 } } }"#.utf8))
    let ids = names.idLookups(in: doc)
    #expect(ids == ["ability": [61919, 40195], "cp": [59]])
    #expect(names.idLookups(in: doc, cap: 1).values.map(\.count).reduce(0, +) == 1)
    let unmet = CompanionRequests.unmetNameIDs(references: SVReferenceIndex(files: []), names: nil,
                                               answers: ["ability:61919": CompanionAnswer(key: "ability:61919", name: "Merciless Resolve", quality: nil, set: nil, icon: nil)],
                                               listed: ids)
    #expect(unmet["ability"] == [40195] && unmet["cp"] == [59], "already answered IDs aren't asked again")
    var index = SVNameIndex()
    index.companionAnswers = ["cp:59": CompanionAnswer(key: "cp:59", name: "Rejuvenation", quality: nil, set: nil, icon: nil)]
    #expect(index.name(forID: 59, kind: "cp")?.title == "Rejuvenation" && index.name(forID: 59, kind: "cp")?.kind == .championSkill)
}
