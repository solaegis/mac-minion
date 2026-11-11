import Foundation
import Testing
@testable import MacMinionKit

private let file = """
Sample_SavedVars =
{
    ["NA Megaserver"] =
    {
        ["@ME"] =
        {
            ["8796093036412335"] =
            {
                ["Masisi"] =
                {
                    ["autoCraft"] = true,
                    ["budget"] = 50,
                    ["color"] =
                    {
                        ["r"] = 1,
                    },
                },
            },
            ["8798292071293572"] =
            {
                ["Masisi"] =
                {
                    ["autoCraft"] = false,
                },
            },
        },
    },
}

"""

private func value(_ data: Data, _ path: [LuaKey]) -> LuaValue? {
    let doc = SVDocument.parse(data)
    guard doc.error == nil, let table = doc.variables.first(where: { $0.key == path[0] })?.value.table else { return nil }
    return table.value(at: Array(path.dropFirst()))
}

private let base: [LuaKey] = [.string("Sample_SavedVars"), .string("NA Megaserver"), .string("@ME")]

@Test func changesOneValueAndLeavesTheRestAsItWas() throws {
    let path = base + [.string("8798292071293572"), .string("Masisi"), .string("autoCraft")]
    let out = try SVEdit.apply([SVEdit.Change(path: path, value: .bool(true))], to: Data(file.utf8))
    if case .bool(true)? = value(out, path) {} else { Issue.record("not changed") }
    #expect(String(decoding: out, as: UTF8.self) == file.replacingOccurrences(of: "[\"autoCraft\"] = false", with: "[\"autoCraft\"] = true"))
}

@Test func addsAMissingSettingAndTheTablesOnTheWay() throws {
    let path = base + [.string("8798292071293572"), .string("Masisi"), .string("color"), .string("r")]
    let budget = base + [.string("8798292071293572"), .string("Masisi"), .string("budget")]
    let out = try SVEdit.apply([SVEdit.Change(path: path, value: .integer(1)),
                                SVEdit.Change(path: budget, value: .number(0.5))], to: Data(file.utf8))
    if case .integer(1)? = value(out, path) {} else { Issue.record("color not added: \(String(decoding: out, as: UTF8.self))") }
    if case .number(0.5)? = value(out, budget) {} else { Issue.record("budget not added") }
    // The other character is untouched.
    if case .integer(50)? = value(out, base + [.string("8796093036412335"), .string("Masisi"), .string("budget")]) {} else { Issue.record("other changed") }
}

@Test func addsToATableWithoutATrailingCommaOrEntries() throws {
    let text = "V = { [\"a\"] = { [\"x\"] = 1 }, [\"b\"] = {} }"
    let out = try SVEdit.apply([SVEdit.Change(path: [.string("V"), .string("a"), .string("y")], value: .string("q\"\n")),
                                SVEdit.Change(path: [.string("V"), .string("b"), .integer(1)], value: .bool(false))], to: Data(text.utf8))
    if case .string("q\"\n")? = value(out, [.string("V"), .string("a"), .string("y")]) {} else { Issue.record(Comment(rawValue: String(decoding: out, as: UTF8.self))) }
    if case .integer(1)? = value(out, [.string("V"), .string("a"), .string("x")]) {} else { Issue.record("x lost") }
    if case .bool(false)? = value(out, [.string("V"), .string("b"), .integer(1)]) {} else { Issue.record("b not added") }
}

@Test func refusesAFileThatDoesntReadOrAPathWithNoPlace() {
    #expect(throws: SVEdit.Failure.self) { try SVEdit.apply([SVEdit.Change(path: [.string("V"), .string("a")], value: .nil)], to: Data("V = { [\"a\"] = ".utf8)) }
    #expect(throws: SVEdit.Failure.self) { try SVEdit.apply([SVEdit.Change(path: [.string("Nope"), .string("a")], value: .nil)], to: Data(file.utf8)) }
    #expect(throws: SVEdit.Failure.self) {
        try SVEdit.apply([SVEdit.Change(path: base + [.string("8796093036412335"), .string("Masisi"), .string("budget"), .string("x")], value: .nil)], to: Data(file.utf8))
    }
}

@Test func findsWhereASettingGoesForTheOtherCharacter() {
    let doc = SVDocument.parse(Data(file.utf8))
    var names = SVNameIndex()
    names.characters["8796093036412335"] = (name: "Masisi", source: "test")
    names.characters["8798292071293572"] = (name: "Alpha Top", source: "test")
    let matrix = SettingsMatrix.build(documents: ["Sample.lua": doc], names: names)
    let a = "8796093036412335", b = "8798292071293572"
    let budgetKey = matrix.addons[0].characters[a]!.keys.first { $0.hasSuffix("Budget") }!
    #expect(matrix.target(file: "Sample.lua", key: budgetKey, from: a, to: b)
            == base + [.string(b), .string("Masisi"), .string("budget")])
    let craftKey = matrix.addons[0].characters[a]!.keys.first { $0.hasSuffix("Auto craft") }!
    #expect(matrix.target(file: "Sample.lua", key: craftKey, from: a, to: b) == matrix.addons[0].characters[b]![craftKey]!.path)
}

@Test func packedDataIsNotASetting() {
    for packed in ["zsU%t#tt#ltw%t##t#%t#tt#xt#%r#xt#lr#%ts%ty%t#%t#%t#x%Vg", "8mc8r6IIqepWV3WU32SJWtMQXKAXKQn4aM6eq4Wa0aTtusYy#3ewd00",
                   "00:G00000000000", "G0:200100000040"] {
        #expect(SettingsMatrix.isPacked(packed), Comment(rawValue: packed))
    }
    for setting in ["Daily", "1: Farming", "ZO_ControlName", "autoCraftEnabled", "LibAddonMenu2", "Mudcrab Chitin", "TOPLEFT"] {
        #expect(!SettingsMatrix.isPacked(setting), Comment(rawValue: setting))
    }
}

@Test func timestampsAndPackedStringsAreLeftOutOfACharactersSettings() {
    let doc = SVDocument.parse(Data("""
    V = { ["NA Megaserver"] = { ["@ME"] = { ["8796093036412335"] = { ["mode"] = "Daily", ["timestamp"] = 1794157504,
          ["rt"] = "8mc8r6IIqepWV3WU32SJWtMQXKAXKQn4aM6eq4Wa0aTtusYy#3ewd00", ["sc"] = "00:G00000000000" } } } }
    """.utf8))
    var names = SVNameIndex()
    names.characters["8796093036412335"] = (name: "Masisi", source: "test")
    let matrix = SettingsMatrix.build(documents: ["V.lua": doc], names: names)
    #expect(matrix.addons.first?.characters["8796093036412335"].map { Array($0.keys) } == ["Mode"])
}

@Test func copyChangesTakeFromsValuesToTosPlaces() throws {
    var names = SVNameIndex()
    names.characters["8796093036412335"] = (name: "Masisi", source: "test")
    names.characters["8798292071293572"] = (name: "Alpha Top", source: "test")
    let matrix = SettingsMatrix.build(documents: ["Sample.lua": SVDocument.parse(Data(file.utf8))], names: names)
    let a = "8796093036412335", b = "8798292071293572"
    let budgetKey = try #require(matrix.addons[0].characters[a]?.keys.first { $0.hasSuffix("Budget") })
    let changes = matrix.copyChanges([("Sample.lua", budgetKey), ("Sample.lua", "No such key"), ("Other.lua", budgetKey)], from: a, to: b)
    #expect(Array(changes.keys) == ["Sample.lua"], "unknown keys and files are left out")
    #expect(changes["Sample.lua"]?.map(\.path) == [base + [.string(b), .string("Masisi"), .string("budget")]])
    if case .integer(50)? = changes["Sample.lua"]?.first?.value {} else { Issue.record("not from's value") }
}

@Test func writingFilesChangesTheGoodOnesAndKeepsBeforeAndAfter() async throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appending(path: "mm-svedit-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }
    let good = dir.appending(path: "A.lua"), broken = dir.appending(path: "B.lua"), missing = dir.appending(path: "C.lua")
    try Data(file.utf8).write(to: good)
    try Data("V = { [\"a\"] = ".utf8).write(to: broken)
    let craft = base + [.string("8798292071293572"), .string("Masisi"), .string("autoCraft")]
    let nope = SVEdit.Change(path: [.string("V"), .string("a")], value: .nil)

    let result = await SVEdit.apply(toFiles: [good: [SVEdit.Change(path: craft, value: .bool(true))], broken: [nope], missing: [nope]])
    #expect(result.changed == 1)
    #expect(result.before == [good: Data(file.utf8)])
    let written = try Data(contentsOf: good)
    #expect(result.after == [good: written])
    if case .bool(true)? = value(written, craft) {} else { Issue.record("not written") }
    #expect(result.failures.map(\.file) == ["B.lua", "C.lua"], "failures in file-name order")
    #expect(try Data(contentsOf: broken) == Data("V = { [\"a\"] = ".utf8), "a file that fails is left as it was")
}
