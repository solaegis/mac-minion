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
    let prompt = SVAISchema.prompt(addon: "WW", table: "WW_SV › $AccountWide", evidence: evidence, shapes: ["queue": "a list of 3 numbers"])
    #expect(prompt.contains("[queue] a list of 3 numbers\n<untrusted_data>\n    local list = WW.sv[\"queue\"]"))
}

@Test func readsFieldsFromTheAnswer() {
    let keys: Set = ["mode", "zones", "delay", "speed"]
    let answer = """
    Here you go:
    ```json
    {"mode": {"label": "when to show", "choices": {"0": "Never", "2": "In combat", "3": "?"}},
     "zones": {"idKind": "Zone", "indexMeaning": "favorite zone"},
     "delay": {"label": "Delay", "unit": "seconds", "idKind": "spaceship"},
     "speed": {"label": "?"},
     "other": {"label": "Not asked"}}
    ```
    """
    let fields = SVAISchema.parse(answer, keys: keys)
    #expect(fields["mode"] == SVAIField(label: "When to show", choices: ["0": "Never", "2": "In combat"]))
    #expect(fields["zones"] == SVAIField(idKind: "zone", indexMeaning: "Favorite zone"))
    #expect(fields["delay"] == SVAIField(label: "Delay", unit: "seconds"), "an ID kind MacMinion can't name is dropped")
    #expect(fields["speed"] == nil && fields["other"] == nil)
    #expect(SVAISchema.parse("I can't tell.", keys: keys).isEmpty)
}

@Test func describesShapesWithoutValues() {
    let doc = SVDocument.parse(Data(#"T = { a = { 3, 57 }, b = { x = 1 }, c = 2, d = "Masisi", e = { "x", "y" } }"#.utf8))
    let t = doc.variables[0].value.table!
    #expect(SVAISchema.shape(of: t["a"]!) == "a list of 2 numbers")
    #expect(SVAISchema.shape(of: t["b"]!) == "a table of 1 named entries")
    #expect(SVAISchema.shape(of: t["c"]!) == "a whole number")
    #expect(SVAISchema.shape(of: t["d"]!) == "text")
    #expect(SVAISchema.shape(of: t["e"]!) == "a list of 2 texts")
}

@Test func aiFillsOnlyWhatTheSourceLeftOut() throws {
    var names = SVSourceNames.parse([#"{ type = "slider", name = "Scale", min = 1, max = 5, getFunc = function() return A.sv.scale end }"#])
    names.addAI(SVAIField(label: "AI scale", choices: ["1": "Tiny"], unit: "%"), key: "scale", parent: "")
    names.addAI(SVAIField(choices: ["0": "Off", "10": "On", "2": "Some"]), key: "mode", parent: "")
    let scale = try #require(names.control(for: .string("scale"), at: []))
    #expect(scale.range == 1...5 && scale.unit == "%")
    #expect(scale.choices.isEmpty == false && scale.guessedChoices == true)
    #expect(names.name(for: .string("scale"), at: [])?.title == "Scale", "the panel's name stays")
    let mode = try #require(names.control(for: .string("mode"), at: []))
    #expect(mode.choices.map(\.value) == ["0", "2", "10"], "choices in number order")
    #expect(SVReadable.display(.integer(2), key: .string("mode"), at: [], names: nil, control: mode) == .choice(label: "Some?", value: "2"))
    #expect(SVReadable.display(.integer(3), key: .string("scale"), at: [], names: nil, control: scale) == .ranged(text: "3%", range: 1...5, outOfRange: false))
    #expect(SVSourceNames.withoutAI(names).control(for: .string("mode"), at: []) == nil)
}

@Test func cachesAIFieldsPerAddonVersion() throws {
    var cache = SVAIFieldCache()
    cache["WW", "1.2", "$AccountWide", "mode"] = SVAIField(unit: "s")
    #expect(cache["ww", "1.2", "$AccountWide", "mode"]?.unit == "s")
    #expect(cache["WW", "1.3", "$AccountWide", "mode"] == nil)
    #expect(cache.entries(folder: "WW", version: "1.2").map(\.key) == ["mode"])
    #expect(try JSONDecoder().decode(SVAIFieldCache.self, from: JSONEncoder().encode(cache)) == cache)
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
