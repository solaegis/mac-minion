import Foundation
import Testing
@testable import MacMinionKit

// AutoResearch's shape: LibSavedVars, one character with a setting of their own, one with only bookkeeping,
// one on the account-wide settings, and a fourth with no table who loads the addon.
private let own = "8796093036412335", bare = "8796093011112222", shared = "8798292071293572", none = "8796093079837777"
private let research = """
AutoResearch_Account = { ["NA Megaserver"] = { ["@ME"] = { ["$AccountWide"] = { ["bags"] = 2 } } } }
AutoResearch_Character =
{
    ["NA Megaserver"] = { ["@ME"] = {
        ["\(own)"] = { ["LibSavedVars"] = { ["accountSavedVarsActive"] = false }, ["version"] = 4, ["bags"] = 1 },
        ["\(bare)"] = { ["version"] = 4, ["$LastCharacterName"] = "Quiet Ember" },
        ["\(shared)"] = { ["LibSavedVars"] = { ["accountSavedVarsActive"] = true }, ["version"] = 4 },
    } },
}
"""
// A second file every character has a table in, so all four are characters the matrix knows.
private let other = """
Other_SV = { ["NA Megaserver"] = { ["@ME"] = {
    ["\(own)"] = { ["x"] = 1 }, ["\(bare)"] = { ["x"] = 1 }, ["\(shared)"] = { ["x"] = 1 }, ["\(none)"] = { ["x"] = 2 },
} } }
"""

private func matrix(defaults: Bool = true) -> SettingsMatrix {
    var names = SVNameIndex()
    for (id, name) in [(own, "Masisi"), (bare, "Quiet Ember"), (shared, "Alpha Top"), (none, "Nameless")] {
        names.characters[id] = (name: name, source: "test")
    }
    let base = SettingsMatrix.build(documents: ["AutoResearch.lua": SVDocument.parse(Data(research.utf8)),
                                                "Other.lua": SVDocument.parse(Data(other.utf8))], names: names)
    var parser = LiteralParser(text: "bags = 3, shortPrefix = true, maxQuality = ITEM_FUNCTIONAL_QUALITY_ARCANE")
    let table = parser.table(at: [])
    let found = SVDefaults.Found(variable: "AutoResearch_Character", table: table, unresolved: parser.unresolved, libSavedVars: true)
    let context = SettingsMatrix.ProfileContext(defaults: defaults ? ["AutoResearch.lua": [found]] : [:],
                                                loads: [none: ["AutoResearch.lua"]])
    return base.applying(context, names: names)
}

private func value(_ m: SettingsMatrix, _ id: String, _ suffix: String) -> String? {
    m.addon("AutoResearch.lua")?.characters[id]?.first { $0.key.hasSuffix(suffix) }?.value.text
}

@Test func eachCharacterGetsTheProfileTheAddonRunsThemOn() {
    let m = matrix()
    let addon = m.addon("AutoResearch.lua")
    #expect(addon?.profile(own) == .own)
    #expect(addon?.profile(bare) == .defaults, "bookkeeping alone is no settings")
    #expect(addon?.profile(shared) == .accountWide)
    #expect(addon?.profile(none) == .accountWide, "LibSavedVars with no table uses the account-wide settings")
    #expect(matrix(defaults: false).addon("AutoResearch.lua")?.profile(bare) == .loadedOnly)
}

@Test func valuesStackDefaultsThenAccountThenOwn() {
    let m = matrix()
    #expect(value(m, own, "Bags") == "1")
    #expect(value(m, bare, "Bags") == "3")
    #expect(value(m, shared, "Bags") == "2")
    #expect(value(m, shared, "Short prefix") == "true", "account-wide values sit over the defaults")
    let addon = m.addon("AutoResearch.lua")!
    let bags = addon.characters[bare]!.keys.first { $0.hasSuffix("Bags") }!
    #expect(addon.source(bare, bags) == .defaults && addon.source(shared, bags) == .account && addon.source(own, bags) == .own)
    #expect(addon.characters[own]!.values.allSatisfy { !SettingsMatrix.isBookkeeping($0) })
    #expect(addon.unresolvedDefaults.values.contains("ITEM_FUNCTIONAL_QUALITY_ARCANE"))
    #expect(addon.characters[bare]!.keys.allSatisfy { !$0.hasSuffix("Max quality") }, "a constant is never compared")
    #expect(addon.changedFromDefault(own) == 1)
}

@Test func compareAndCloneUseTheValuesCharactersRunOn() {
    let m = matrix()
    let c = m.compare(own, bare).first { $0.file == "AutoResearch.lua" }
    #expect(c?.differing.map(\.key).contains { $0.hasSuffix("Bags") } == true)
    let bags = m.addon("AutoResearch.lua")!.characters[bare]!.keys.first { $0.hasSuffix("Bags") }!
    // A default goes into the other character's own table; nothing goes to an account-wide character.
    #expect(m.target(file: "AutoResearch.lua", key: bags, from: bare, to: own)?.last == .string("bags"))
    #expect(m.target(file: "AutoResearch.lua", key: bags, from: own, to: shared) == nil)
    #expect(m.target(file: "AutoResearch.lua", key: bags, from: own, to: bare)?.prefix(4).last == .string(bare))
    // Only characters with settings of their own get a grid cell.
    #expect(m.cell("AutoResearch.lua", own) != nil && m.cell("AutoResearch.lua", bare) == nil)
}

private extension LuaValue {
    var text: String { SettingsMatrix.plain(self) }
}
