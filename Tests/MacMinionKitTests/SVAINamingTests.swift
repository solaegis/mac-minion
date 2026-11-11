import Foundation
import Testing
@testable import MacMinionKit

private let source = #"""
local function Refresh()
    if WW.sv.maxGold > 0 then ShowBudget(WW.sv.maxGold) end
    -- WW.sv.maxGold is checked here
    local list = WW.sv["queue"]
end
WW.sv.maxGold = 100
"""#

@Test func gathersTheLinesThatUseEachKey() {
    let evidence = SVAINaming.evidence(keys: ["maxGold", "queue", "nowhere"], sources: [source])
    #expect(evidence.map(\.key) == ["maxGold", "queue"], "keys the source never mentions aren't sent")
    #expect(evidence[0].lines == ["if WW.sv.maxGold > 0 then ShowBudget(WW.sv.maxGold) end", "WW.sv.maxGold = 100"], "comments are left out")
    let prompt = SVAINaming.prompt(addon: "WW", table: "WW_SV › $AccountWide", evidence: evidence)
    #expect(prompt.contains("[queue]\n    local list = WW.sv[\"queue\"]"))
}

@Test func readsNamesFromTheAnswer() {
    let keys: Set = ["maxGold", "queue", "speed"]
    let lines = SVAINaming.parse("Here you go:\n- `maxGold` = Gold budget for writs.\nqueue: \"crafting queue\"\nspeed = ?\nother = Not asked\n", keys: keys)
    #expect(lines == ["maxGold": "Gold budget for writs", "queue": "Crafting queue"])
    let json = SVAINaming.parse("```json\n{\"maxGold\": \"Gold budget\", \"speed\": \"?\"}\n```", keys: keys)
    #expect(json == ["maxGold": "Gold budget"])
}

@Test func cachesNamesPerAddonVersion() throws {
    var cache = SVAINameCache()
    cache["WritWorthy", "1.2", "$AccountWide", "maxGold"] = "Gold budget"
    #expect(cache["writworthy", "1.2", "$AccountWide", "maxGold"] == "Gold budget")
    #expect(cache["WritWorthy", "1.3", "$AccountWide", "maxGold"] == nil, "a new version asks again")
    let entries = cache.entries(folder: "WritWorthy", version: "1.2")
    #expect(entries.count == 1 && entries[0].parent == "$AccountWide" && entries[0].key == "maxGold")
    let decoded = try JSONDecoder().decode(SVAINameCache.self, from: JSONEncoder().encode(cache))
    #expect(decoded == cache)
}

@Test func aiNamesNeverReplaceNamesFromTheSource() {
    var names = SVSourceNames.parse(["{ name = \"Show map\", getFunc = function() return A.sv.opts.showMap end }"])
    names.add(SVSourceName(title: "AI map", detail: nil, source: .ai, isGuess: true), key: "showMap", parent: "opts")
    names.add(SVSourceName(title: "Gold budget", detail: nil, source: .ai, isGuess: true), key: "maxGold", parent: "opts")
    #expect(names.name(for: .string("showMap"), at: [.string("opts")])?.title == "Show map")
    #expect(names.name(for: .string("maxGold"), at: [.string("opts")])?.source == .ai)
}
