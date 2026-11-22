import Foundation
import Testing
@testable import MacMinionKit

// AutoResearch's shape: LibSavedVars, one character with a setting of their own, one with only bookkeeping,
// one on the account-wide settings, and a fourth with no table, who gets the account-wide settings.
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
    let context = SettingsMatrix.ProfileContext(defaults: defaults ? ["AutoResearch.lua": [found]] : [:])
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
    #expect(matrix(defaults: false).addon("AutoResearch.lua")?.characters[bare] == nil, "only bookkeeping and no defaults: left out")
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
    // Only characters with settings of their own get a grid cell, and the grid lists addons that have one.
    #expect(m.cell("AutoResearch.lua", own) != nil && m.cell("AutoResearch.lua", bare) == nil)
    #expect(m.gridAddons.contains { $0.file == "AutoResearch.lua" })
}

// ESO Combat Lock's shape: everything account-wide, split by megaserver, nothing at the character level.
@Test func anAddonThatKeepsOnlyAccountWideSettingsReachesEachCharacterOnThatAccount() {
    let lock = """
    Lock_SV = { ["Default"] = {
        ["@ME"] = { ["$AccountWide"] = { ["NA Megaserver"] = { ["emptySlots"] = true }, ["EU Megaserver"] = { ["emptySlots"] = false }, ["shared"] = 7 } },
        ["@OTHER"] = { ["$AccountWide"] = { ["shared"] = 9 } },
    } }
    """
    var names = SVNameIndex()
    names.characters[own] = (name: "Masisi", source: "test")
    names.characters[shared] = (name: "Alpha Top", source: "test")
    let eu = "8798292000000001"
    names.characters[eu] = (name: "Velvet Thorn", source: "test")
    let euFile = #"E_SV = { ["EU Megaserver"] = { ["@ME"] = { ["\#(eu)"] = { ["x"] = 1 } } } }"#
    let base = SettingsMatrix.build(documents: ["Other.lua": SVDocument.parse(Data(other.utf8)),
                                                "Eu.lua": SVDocument.parse(Data(euFile.utf8)),
                                                "Lock.lua": SVDocument.parse(Data(lock.utf8))], names: names)
    let m = base.applying(.init(), names: names)
    let addon = m.addon("Lock.lua")
    #expect(addon?.profile(own) == .accountWide)
    #expect(addon?.characters[own]?.first { $0.key.hasSuffix("Empty slots") }?.value.text == "true", "NA's part for an NA character")
    #expect(addon?.characters[eu]?.first { $0.key.hasSuffix("Empty slots") }?.value.text == "false", "EU's part for an EU character")
    #expect(addon?.characters[own]?.first { $0.key.hasSuffix("Shared") }?.value.text == "7", "their account's, not @OTHER's")
    #expect(!m.gridAddons.contains { $0.file == "Lock.lua" }, "nobody keeps settings of their own, so no grid row")
}

@Test func ptsAccountWideSplitDoesNotFoldIntoDefault() {
    let lock = """
    Lock_SV = { ["Default"] = {
        ["@ME"] = { ["$AccountWide"] = {
            ["NA Megaserver"] = { ["emptySlots"] = true },
            ["PTS"] = { ["emptySlots"] = false },
            ["shared"] = 7,
        } },
    } }
    """
    var names = SVNameIndex()
    names.characters[own] = (name: "Masisi", source: "test")
    let pts = "8796093099999999"
    names.characters[pts] = (name: "PTS Tester", source: "test")
    let ptsFile = #"P_SV = { ["PTS"] = { ["@ME"] = { ["\#(pts)"] = { ["x"] = 1 } } } }"#
    let base = SettingsMatrix.build(documents: ["Other.lua": SVDocument.parse(Data(other.utf8)),
                                                "Pts.lua": SVDocument.parse(Data(ptsFile.utf8)),
                                                "Lock.lua": SVDocument.parse(Data(lock.utf8))], names: names)
    let m = base.applying(.init(), names: names)
    let addon = m.addon("Lock.lua")
    #expect(addon?.characters[own]?.first { $0.key.hasSuffix("Empty slots") }?.value.text == "true", "NA keeps NA's part")
    #expect(addon?.characters[pts]?.first { $0.key.hasSuffix("Empty slots") }?.value.text == "false", "PTS keeps PTS's part")
    #expect(addon?.characters[own]?.first { $0.key.hasSuffix("Shared") }?.value.text == "7")
}

// ESO Combat Lock also keeps each character's own data inside the account-wide table, keyed by ID.
@Test func characterTablesInsideTheAccountWideTableAreThatCharactersOwnOverTheAccount() {
    let lock = """
    Lock_SV = { ["Default"] = { ["@ME"] = { ["$AccountWide"] = { ["NA Megaserver"] = {
        ["size"] = 64, ["park"] = "account",
        ["perCharacterData"] = {
            ["\(own)"] = { ["_characterName"] = "Masisi", ["park"] = "mine" },
            ["\(shared)"] = { ["_characterName"] = "Alpha Top" },
        },
    } } } } }
    """
    var names = SVNameIndex()
    for (id, name) in [(own, "Masisi"), (shared, "Alpha Top"), (none, "Nameless")] { names.characters[id] = (name: name, source: "test") }
    let base = SettingsMatrix.build(documents: ["Other.lua": SVDocument.parse(Data(other.utf8)),
                                                "Lock.lua": SVDocument.parse(Data(lock.utf8))], names: names)
    let m = base.applying(.init(), names: names)
    let addon = m.addon("Lock.lua")!
    func text(_ id: String, _ suffix: String) -> String? { addon.characters[id]?.first { $0.key.hasSuffix(suffix) }?.value.text }
    #expect(addon.profile(own) == .own)
    #expect(text(own, "Park") == "mine" && text(own, "Size") == "64", "their own over the account's")
    #expect(addon.profile(shared) == .accountWide, "only bookkeeping of their own")
    #expect(text(shared, "Park") == "account")
    #expect(addon.profile(none) == .accountWide && text(none, "Size") == "64", "no table: still the account's")
    #expect(!addon.characters[own]!.keys.contains { $0.contains("Per character data") || $0.hasSuffix("Character name") })
    #expect(m.gridAddons.contains { $0.file == "Lock.lua" })
    // Cloning Masisi's own value to Nameless has nowhere to go; cloning the account's size into Masisi's table does.
    let size = addon.characters[shared]!.keys.first { $0.hasSuffix("Size") }!
    #expect(m.target(file: "Lock.lua", key: size, from: shared, to: own)
            == [.string("Lock_SV"), .string("Default"), .string("@ME"), .string("$AccountWide"), .string("NA Megaserver"),
                .string("perCharacterData"), .string(own), .string("size")])
}

private extension LuaValue {
    var text: String { SettingsMatrix.plain(self) }
}
