import Foundation
import Testing
@testable import MacMinionKit

private let files: [String: String] = [
    "WritWorthy.lua": """
    WritWorthyVars = { ["Default"] = { ["@SOLAEGIS"] = {
        ["$AccountWide"] = { ["version"] = 1 },
        ["Masisi"] = { ["version"] = 1 },
        ["Kellen Dysart"] = { ["version"] = 1 },
    } } }
    """,
    "IJA.lua": """
    IJA_FavCollectibles_Saves = { ["EU Megaserver"] = { ["@SOLAEGIS"] = { ["Masisi"] = { ["version"] = 1 } } } }
    """,
    "WizardsWardrobe.lua": """
    WizardsWardrobeSV = { ["Default"] = { ["@SOLAEGIS"] = {
        ["8796093036412335"] = { ["version"] = 1, ["$LastCharacterName"] = "Masisi" },
        ["8798292071266932"] = { ["version"] = 1, ["$LastCharacterName"] = "Masisi" },
    } } }
    """,
    "AGS_UnknownOnAltsFilter.lua": """
    AGS_UOAFVars = { ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = { ["version"] = 1 } } } }
    """,
]

private func graph(snapshot: CompanionSnapshot? = nil) -> SVGraph {
    let documents = files.mapValues { SVDocument.parse(Data($0.utf8)) }
    let names = SVNameIndex.build(documents: documents, addons: nil)
    var homes: [String: SettingsMatrix.Home] = [:]
    for (_, doc) in documents.sorted(by: { $0.key < $1.key }) { SettingsMatrix.mergeHomes(&homes, SettingsMatrix.homes(in: doc)) }
    let addons: [String: (addon: String, variables: [String], dependsOn: [String])] = [
        "writworthy": ("WritWorthy", ["WritWorthyVars"], ["LibLazyCrafting>=4"]),
        "esofavoritecollectibles": ("EsoFavoriteCollectibles", ["IJA_FavCollectibles_Saves"], []),
        "wizardswardrobe": ("WizardsWardrobe", ["WizardsWardrobeSV"], []),
    ]
    return SVGraph.build(.init(documents: documents, addons: addons, names: names, homes: homes, snapshot: snapshot))
}

@Test func keepsTwoCharactersWhoShareANameApartAndMarksTheDefaultProfileScopeAmbiguous() {
    let g = graph()
    let na = SVGraph.NodeID(.character, "8796093036412335"), eu = SVGraph.NodeID(.character, "8798292071266932")
    #expect(g.out[na]?[.onServer] == [SVGraph.NodeID(.megaserver, "NA Megaserver")])
    #expect(g.out[eu]?[.onServer] == [SVGraph.NodeID(.megaserver, "EU Megaserver")])
    #expect(g.explain(na, .onServer, SVGraph.NodeID(.megaserver, "NA Megaserver")).first?.rule == "R5")
    let shared = SVGraph.NodeID(.scope, "WritWorthyVars|Default|@SOLAEGIS|Masisi")
    #expect(g.nodes[shared]?["ambiguous"] == "true")
    #expect(g.out[shared]?[.scopeOwner] == [na, eu])
    // Under a real megaserver profile the name resolves.
    let euScope = SVGraph.NodeID(.scope, "IJA_FavCollectibles_Saves|EU Megaserver|@SOLAEGIS|Masisi")
    #expect(g.out[euScope]?[.scopeOwner] == [eu])
}

@Test func recordsNameOnlyCharactersAndUndeclaredGlobalsAsOrphans() {
    let orphans = graph().orphans().map(\.description)
    #expect(orphans.contains("character:name:@SOLAEGIS:Kellen Dysart"))
    #expect(orphans.contains("svGlobal:AGS_UOAFVars"))
    #expect(orphans.contains("scope:WritWorthyVars|Default|@SOLAEGIS|Masisi"))
}

@Test func tiesCharactersToAddonsBothWaysAndWalksUpToBothRoots() {
    let g = graph()
    let na = "8796093036412335"
    let mine = g.addons(for: na)
    #expect(mine.contains { $0.addon.key == "WizardsWardrobe" && $0.why == [.hasDataIn] })
    #expect(g.characters(for: "WizardsWardrobe").map(\.character.key).sorted() == [na, "8798292071266932"])
    let scope = SVGraph.NodeID(.scope, "WizardsWardrobeSV|Default|@SOLAEGIS|\(na)")
    let roots = Set(g.up(from: scope).compactMap(\.last))
    #expect(roots == [SVGraph.NodeID(.addon, "WizardsWardrobe"), SVGraph.NodeID(.account, "@SOLAEGIS")])
    #expect(g.ownershipIsAcyclic)
    #expect(g.out[SVGraph.NodeID(.addon, "WritWorthy")]?[.dependsOn] == [SVGraph.NodeID(.addon, "LibLazyCrafting")])
}

@Test func takesTheCompanionsRosterAndEnabledAddonsOverRules() {
    let roster = CompanionCharacter(id: "8796093036412335", name: "Masisi", server: "NA Megaserver", account: "@SOLAEGIS",
                                    classID: nil, raceID: nil, alliance: nil, level: nil, champion: nil, lastPlayed: nil)
    var snap = CompanionSnapshot(file: "EsoMacMinion.lua", schema: 1, schemaKnown: true, written: nil, env: nil,
                                 characters: [roster.id: roster], addons: [:], errors: [], guilds: [:], skipped: [])
    snap.enabledBy = [roster.id: CompanionEnabled(at: nil, disabled: ["WizardsWardrobe"], notLoaded: [])]
    let g = graph(snapshot: snap)
    let na = SVGraph.NodeID(.character, roster.id)
    #expect(g.explain(na, .onServer, SVGraph.NodeID(.megaserver, "NA Megaserver")).first?.rule == "companion")
    #expect(g.out[na]?[.enabledFor] == nil || g.out[na]?[.enabledFor]?.isEmpty == true)
}
