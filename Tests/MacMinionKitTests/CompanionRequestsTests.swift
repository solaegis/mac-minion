import Foundation
import Testing
@testable import MacMinionKit

private let noLookups = """
EsoMacMinion_Data =
{
    ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
        ["schema"] = 1,
        ["characters"] = { ["8796093036412335"] = { ["name"] = "Masisi" } },
    } } },
    ["EU Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
        ["schema"] = 1,
        ["lookups"] = { ["requests"] = { ["item"] = { [1] = 96175 }, ["svGlobals"] = { [1] = "Old" } }, ["answers"] = {} },
    } } },
}
"""

@Test func setsTheSvGlobalsRequestInEveryAccountWideTableAndKeepsOtherRequests() throws {
    let updated = try #require(CompanionRequests.apply(svGlobals: ["AUI_Main", "PCHAT_OPTS"], to: Data(noLookups.utf8)))
    let doc = SVDocument.parse(updated)
    #expect(doc.error == nil)
    let snap = try #require(CompanionData.snapshot(doc))
    #expect(snap.requestedSvGlobals == ["AUI_Main", "PCHAT_OPTS"])
    #expect(snap.characters["8796093036412335"]?.name == "Masisi")
    let root = try #require(doc[CompanionData.variable]?.table)
    #expect(CompanionRequests.requested(in: root) == ["AUI_Main", "PCHAT_OPTS"])
    let eu = try #require(root["EU Megaserver"]?.table?["@SOLAEGIS"]?.table?["$AccountWide"]?.table)
    let item = eu["lookups"]?.table?["requests"]?.table?["item"]?.table?.entries.first?.value
    if case .integer(let id)? = item { #expect(id == 96175) } else { Issue.record("item request lost") }
    // A second pass with the same list changes nothing it has to.
    let again = try #require(CompanionRequests.apply(svGlobals: ["AUI_Main", "PCHAT_OPTS"], to: updated))
    #expect(CompanionRequests.requested(in: try #require(SVDocument.parse(again)[CompanionData.variable]?.table)) == ["AUI_Main", "PCHAT_OPTS"])
}

@Test func leavesFilesWithoutTheCompanionTableAlone() {
    #expect(CompanionRequests.apply(svGlobals: ["X"], to: Data("Other_SV = { }".utf8)) == nil)
    #expect(CompanionRequests.apply(svGlobals: ["X"], to: Data("EsoMacMinion_Data = { [".utf8)) == nil)
}

@Test func asksForEveryDeclaredGlobalButItsOwn() {
    let list = CompanionRequests.svGlobals(from: ["pchat": ["PCHAT_OPTS"], "aui": ["AUI_Main", "AUI_Minimap"],
                                                  "esomacminion": [CompanionData.variable]])
    #expect(list == ["AUI_Main", "AUI_Minimap", "PCHAT_OPTS"])
}

@Test func readsCharacterNamesAddonFoldersEnabledByAndLayouts() throws {
    let text = """
    EsoMacMinion_Data = { ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
        ["schema"] = 1,
        ["characters"] = { ["8796093036412335"] = { ["name"] = "Masisi", ["names"] = { ["Old Masisi"] = 1780000000, ["Masisi"] = 1790000000 } } },
        ["addons"] = { ["LibDup"] = { ["state"] = "loaded", ["enabled"] = true, ["rootPath"] = "user:/AddOns/LibDup/",
                                      ["copies"] = { [1] = "user:/AddOns/Host/Libs/LibDup/", [2] = "user:/AddOns/LibDup/" } } },
        ["enabledBy"] = { ["8796093036412335"] = { ["at"] = 1793288692, ["disabled"] = { [1] = "Off" } } },
        ["layouts"] = { ["sv"] = { ["PCHAT_OPTS"] = { ["source"] = "scan", ["zoShaped"] = true, ["pathCount"] = 9,
            ["tree"] = { ["Default"] = { ["@SOLAEGIS"] = { ["keys"] = { [1] = "$AccountWide" }, ["count"] = 1,
                                                           ["serverNamespaces"] = { [1] = "NA Megaserver" } } } } } },
                        ["scanned"] = { ["at"] = 1793288692, ["requested"] = 2, ["found"] = 1, ["missing"] = { [1] = "Gone" } } },
    } } } }
    """
    let snap = try #require(CompanionData.snapshot(SVDocument.parse(Data(text.utf8))))
    #expect(snap.characters["8796093036412335"]?.previousNames == ["Old Masisi"])
    #expect(snap.addons["LibDup"]?.rootPath == "user:/AddOns/LibDup/" && snap.addons["LibDup"]?.copies.count == 2)
    #expect(snap.enabledBy["8796093036412335"]?.disabled == ["Off"])
    let layout = try #require(snap.layouts["PCHAT_OPTS"])
    #expect(layout.zoShaped && layout.tree["Default"]?["@SOLAEGIS"] == ["$AccountWide"])
    #expect(layout.serverNamespaces["Default"]?["@SOLAEGIS"] == ["NA Megaserver"])
    #expect(snap.layoutScan?.found == 1 && snap.layoutScan?.missing == ["Gone"])
}

@Test func readsLeftOutAddonFieldsAsTheirDefaultsAndTakesTheNewestBlocksList() throws {
    let text = """
    EsoMacMinion_Data = {
        ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = { ["schema"] = 1, ["written"] = 100,
            ["addons"] = { ["Stale"] = {} } } } },
        ["EU Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = { ["schema"] = 1, ["written"] = 200,
            ["addons"] = { ["pChat"] = {}, ["Off"] = { ["enabled"] = false, ["state"] = "disabled" },
                           ["LibCharacterKnowledge"] = { ["rootPath"] = "user:/AddOns/CharacterKnowledge/LibCharacterKnowledge/" } } } } },
    }
    """
    let snap = try #require(CompanionData.snapshot(SVDocument.parse(Data(text.utf8))))
    #expect(snap.addons["Stale"] == nil)
    let pchat = try #require(snap.addons["pChat"])
    #expect(pchat.enabled && pchat.loaded && !pchat.failedToLoad && pchat.rootPath == nil)
    #expect(snap.addons["Off"]?.enabled == false && snap.addons["Off"]?.state == "disabled")
    #expect(snap.addons["LibCharacterKnowledge"]?.rootPath == "user:/AddOns/CharacterKnowledge/LibCharacterKnowledge/")
}
