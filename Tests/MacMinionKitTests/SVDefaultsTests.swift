import Foundation
import Testing
@testable import MacMinionKit

private func value(_ found: SVDefaults.Found?, _ path: LuaKey...) -> LuaValue? { found?.table.value(at: path) }

@Test func defaultsFromAZOSavedVarsCallWithATableInPlace() {
    let source = """
    local sv = ZO_SavedVars:NewAccountWide("Pins_SV", 2, nil, { size = 20, show = true, label = "Pins", -- shown on the map
        colors = { r = 1, g = 0.5 }, [3] = 'three' })
    """
    let found = SVDefaults.parse(sources: [source], variables: ["Pins_SV"])["Pins_SV"]
    if case .integer(20)? = value(found, .string("size")) {} else { Issue.record("size") }
    if case .bool(true)? = value(found, .string("show")) {} else { Issue.record("show") }
    if case .string("Pins")? = value(found, .string("label")) {} else { Issue.record("label") }
    if case .number(0.5)? = value(found, .string("colors"), .string("g")) {} else { Issue.record("nested") }
    if case .string("three")? = value(found, .integer(3)) {} else { Issue.record("bracket key") }
    #expect(found?.libSavedVars == false)
}

@Test func aTableWhereTheNamespaceGoesIsTheDefaults() {
    let source = #"MyAddon.sv = ZO_SavedVars:NewCharacterIdSettings("MyAddon_SV", 1, MyAddon.defaults)"# + "\n"
        + "MyAddon.defaults = { enabled = true, mode = 2 }"
    let found = SVDefaults.parse(sources: [source], variables: ["MyAddon_SV"])["MyAddon_SV"]
    if case .integer(2)? = value(found, .string("mode")) {} else { Issue.record("mode: \(String(describing: found?.table.entries.map(\.key)))") }
}

@Test func libSavedVarsWithANameBuiltFromTheAddonAndConstantsLeftUnresolved() {
    let main = """
    local addon = {
        name = "AutoResearch",
        defaults = {
            bags = AUTORESEARCH_BAG_BOTH,
            maxQuality = {
                [CRAFTING_TYPE_BLACKSMITHING] = ITEM_FUNCTIONAL_QUALITY_ARCANE,
            },
            shortPrefix = true,
            chatColor = { 1, 1, 1, 1 },
            traitOrder = { ITEM_TRAIT_TYPE_WEAPON_INFUSED, ITEM_TRAIT_TYPE_WEAPON_SHARPENED },
        },
    }
    """
    let settings = """
    local LSV = LibSavedVars or LibStub("LibSavedVars")
    self.settings = LSV:NewCharacterSettings(self.name .. "_Character", self.defaults)
                       :AddAccountWideToggle(self.name .. "_Account")
    """
    let found = SVDefaults.parse(sources: [main, settings], variables: ["AutoResearch_Account", "AutoResearch_Character"])
    let character = found["AutoResearch_Character"]
    #expect(found.count == 1)
    #expect(character?.libSavedVars == true)
    if case .bool(true)? = value(character, .string("shortPrefix")) {} else { Issue.record("shortPrefix") }
    if case .integer(1)? = value(character, .string("chatColor"), .integer(4)) {} else { Issue.record("positional") }
    #expect(character?.unresolved[[.string("bags")]] == "AUTORESEARCH_BAG_BOTH")
    #expect(character?.unresolved[[.string("traitOrder"), .integer(1)]] == "ITEM_TRAIT_TYPE_WEAPON_INFUSED")
    // A constant used as a key can't be placed at all: it's left out, not guessed.
    #expect(character?.table.value(at: [.string("maxQuality")])?.table?.count == 0)
    #expect(value(character, .string("bags")) == nil)
}

@Test func callsOnOtherObjectsAndNamesNoManifestDeclaresAreIgnored() {
    let source = """
    local x = Something:New("Other_SV", 1, nil, { a = 1 })
    local y = ZO_SavedVars:NewAccountWide("Undeclared_SV", 1, nil, { b = 2 })
    """
    #expect(SVDefaults.parse(sources: [source], variables: ["Mine_SV"]).isEmpty)
}
