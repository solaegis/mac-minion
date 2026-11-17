import Foundation
import Testing
@testable import MacMinionKit

private let source = #"""
local options = {
    { type = "slider", name = "Writs to keep", tooltip = "How many writs to hold.", min = 0, max = 100, step = 5, default = 10,
      getFunc = function() return WW.sv.maxWrits end },
    { type = "dropdown", name = "Show", choices = { "Never", "Always" }, choicesValues = { 0, 1 },
      getFunc = function() return WW.sv.mode end },
}
if WW.sv.maxWrits > 50 then WW.Warn() end
"""#

@Test func explainsFromTheSourceAlone() throws {
    let names = SVSourceNames.parse([source])
    let e = SVExplanation.build(key: .string("maxWrits"), parent: [], source: names, sources: [source])
    #expect(e.name?.title == "Writs to keep" && e.name?.detail == "How many writs to hold.")
    #expect(e.values == "0 to 100, in steps of 5")
    #expect(e.control?.defaultValue == "10")
    #expect(e.lines.contains("if WW.sv.maxWrits > 50 then WW.Warn() end"))
    let prompt = e.prompt(addon: "WritWorthy", table: "WritWorthy.lua › $AccountWide")
    #expect(prompt.contains("Name: Writs to keep") && prompt.contains("Values: 0 to 100, in steps of 5") && prompt.contains("Default: 10"))
    let mode = SVExplanation.build(key: .string("mode"), parent: [], source: names, sources: [source])
    #expect(mode.values == "Never (0) or Always (1)")
    #expect(SVExplanation.build(key: .string("nothing"), parent: [], source: names, sources: [source]).isEmpty)
}

@Test func checksAValueBeforeItIsWritten() {
    let names = SVSourceNames.parse([source])
    let slider = names.control(for: .string("maxWrits"), at: []), dropdown = names.control(for: .string("mode"), at: [])
    #expect(SVWriteCheck.issues(value: .integer(250), replacing: .integer(10), control: slider) == [.outOfRange(range: 0...100)])
    #expect(SVWriteCheck.issues(value: .integer(20), replacing: .integer(10), control: slider).isEmpty)
    #expect(SVWriteCheck.issues(value: .integer(7), replacing: .integer(0), control: dropdown) == [.notAChoice])
    #expect(SVWriteCheck.issues(value: .integer(42), replacing: .string("7"), control: nil) == [.typeChange(from: "string", to: "number")])
    #expect(SVWriteCheck.issues(value: .integer(42), replacing: nil, control: nil).isEmpty, "a new key has nothing to compare with")
    let table = LuaTable(entries: [LuaEntry(key: .string("owner"), value: .string("Masisi^Fx"), span: 0..<0)], span: 0..<0)
    #expect(SVWriteCheck.issues(value: .table(table), replacing: nil, control: nil, from: ("8796093036412335", "Masisi")) == [.characterSpecific])
    #expect(SVWriteCheck.issues(value: .string("x8796093036412335"), replacing: nil, control: nil, from: ("8796093036412335", nil)) == [.characterSpecific])
    // AI's choices are guesses: a value outside them isn't flagged.
    var guessed = SVControl(type: "dropdown", choices: [.init(value: "1", label: "One")])
    guessed.guessedChoices = true
    #expect(SVWriteCheck.issues(value: .integer(3), replacing: .integer(1), control: guessed).isEmpty)
    #expect(SVWriteCheck.message(.outOfRange(range: 0...100), label: "WW · Writs to keep", value: "250") == "WW · Writs to keep: 250 is outside 0–100")
}
