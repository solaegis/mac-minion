import Foundation
import Testing
@testable import MacMinionKit

private let base = """
EsoMacMinion_Data = { ["NA Megaserver"] = { ["@ME"] = { ["$AccountWide"] = {
    ["lookups"] = { ["requests"] = { ["svGlobals"] = { [1] = "A" } }, ["answers"] = { ["item:1"] = "Sword" } },
} } } }
"""

@Test func companionAllowlistAcceptsRequestsButNotAnswers() {
    let old = SVDocument.parse(Data(base.utf8))
    let requestsOnly = """
    EsoMacMinion_Data = { ["NA Megaserver"] = { ["@ME"] = { ["$AccountWide"] = {
        ["lookups"] = { ["requests"] = { ["svGlobals"] = { [1] = "B" } }, ["answers"] = { ["item:1"] = "Sword" } },
    } } } }
    """
    let answersTouched = """
    EsoMacMinion_Data = { ["NA Megaserver"] = { ["@ME"] = { ["$AccountWide"] = {
        ["lookups"] = { ["requests"] = { ["svGlobals"] = { [1] = "A" } }, ["answers"] = { ["item:1"] = "Changed" } },
    } } } }
    """
    let allowed: Set<LuaCompare.AllowedPath> = [.companionRequests, .companionLookups]
    #expect(LuaCompare.onlyAllowedPathsDiffer(old: old, new: SVDocument.parse(Data(requestsOnly.utf8)), allowed: allowed))
    #expect(!LuaCompare.onlyAllowedPathsDiffer(old: old, new: SVDocument.parse(Data(answersTouched.utf8)), allowed: allowed))
}

@Test func omitLamPanelsLeavesExistingPanelsAlone() throws {
    let withPanels = """
    EsoMacMinion_Data = { ["NA Megaserver"] = { ["@ME"] = { ["$AccountWide"] = {
        ["lookups"] = { ["requests"] = {
            ["svGlobals"] = { [1] = "Old" },
            ["lamPanels"] = { [1] = "KeepMe" },
        }, ["answers"] = {} },
    } } } }
    """
    let updated = try #require(CompanionRequests.apply(svGlobals: ["New"], to: Data(withPanels.utf8)))
    let root = try #require(SVDocument.parse(updated)[CompanionData.variable]?.table)
    #expect(CompanionRequests.requested(in: root) == ["New"])
    #expect(CompanionRequests.requestedLamPanels(in: root) == ["KeepMe"])
}
