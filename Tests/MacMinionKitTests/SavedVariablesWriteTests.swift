import Foundation
import Testing
@testable import MacMinionKit

private let companionFixture = """
EsoMacMinion_Data =
{
    ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
        ["schema"] = 1,
        ["lookups"] = { ["requests"] = { ["svGlobals"] = { [1] = "Old", }, }, ["answers"] = {} },
        ["errors"] = { [1] = { ["message"] = "say \\"hi\\"\\n<Locals></Locals>", }, },
    } } },
}
"""

@Test func companionWriteUpdatesRequestsAndKeepsBackup() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "mm-sv-write-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "EsoMacMinion.lua")
    try Data(companionFixture.utf8).write(to: url)
    #expect(try CompanionRequests.write(svGlobals: ["A", "B"], savedVariables: dir))
    let bak = SavedVariablesWrite.backupURL(for: url)
    #expect(FileManager.default.fileExists(atPath: bak.path))
    #expect(try Data(contentsOf: bak) == Data(companionFixture.utf8))
    let written = try Data(contentsOf: url)
    #expect(SVDocument.parse(written).error == nil)
    let root = try #require(SVDocument.parse(written)[CompanionData.variable]?.table)
    #expect(CompanionRequests.requested(in: root) == ["A", "B"])
    #expect(root["NA Megaserver"]?.table?["@SOLAEGIS"]?.table?["$AccountWide"]?.table?["errors"]?.table != nil)
}

@Test func writeRefusesUnparsableNewBytes() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "mm-sv-refuse-parse-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "X.lua")
    let original = Data("V = { [\"a\"] = 1 }\n".utf8)
    try original.write(to: url)
    let stamp = try SavedVariablesWrite.Stamp.read(url: url)
    var refused = false
    do {
        try SavedVariablesWrite.write(Data("V = { [".utf8), to: url, previouslyRead: stamp, allowed: [.exact([.string("V"), .string("a")])])
    } catch let refusal as SavedVariablesWrite.Refusal {
        if case .parseFailed = refusal { refused = true }
    }
    #expect(refused)
    #expect(try Data(contentsOf: url) == original)
    #expect(!FileManager.default.fileExists(atPath: SavedVariablesWrite.backupURL(for: url).path))
}

@Test func writeRefusesUnintendedKeyChanges() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "mm-sv-refuse-keys-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "X.lua")
    let original = Data("V = { [\"a\"] = 1, [\"b\"] = 2 }\n".utf8)
    try original.write(to: url)
    let stamp = try SavedVariablesWrite.Stamp.read(url: url)
    let tampered = Data("V = { [\"a\"] = 1, [\"b\"] = 99 }\n".utf8)
    #expect(throws: SavedVariablesWrite.Refusal.unintendedChanges) {
        try SavedVariablesWrite.write(tampered, to: url, previouslyRead: stamp, allowed: [.exact([.string("V"), .string("a")])])
    }
    #expect(try Data(contentsOf: url) == original)
}

@Test func writeRefusesWhenFileChangedSinceRead() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "mm-sv-refuse-stale-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "X.lua")
    try Data("V = { [\"a\"] = 1 }\n".utf8).write(to: url)
    let stamp = try SavedVariablesWrite.Stamp.read(url: url)
    try Data("V = { [\"a\"] = 2 }\n".utf8).write(to: url)
    let newBytes = Data("V = { [\"a\"] = 3 }\n".utf8)
    #expect(throws: SavedVariablesWrite.Refusal.fileChangedSinceRead) {
        try SavedVariablesWrite.write(newBytes, to: url, previouslyRead: stamp, allowed: [.exact([.string("V"), .string("a")])])
    }
    #expect(try Data(contentsOf: url) == Data("V = { [\"a\"] = 2 }\n".utf8))
}

@Test func svEditToFilesUsesGuardedWriteAndBackup() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "mm-sv-edit-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "PCHAT_OPTS.lua")
    let original = Data("""
    PCHAT_OPTS = { ["NA Megaserver"] = { ["@A"] = { ["1"] = { ["scale"] = 1, }, }, }, }
    """.utf8)
    try original.write(to: url)
    let edits = await SVEdit.apply(toFiles: [
        url: [SVEdit.Change(path: [.string("PCHAT_OPTS"), .string("NA Megaserver"), .string("@A"), .string("1"), .string("scale")],
                            value: .number(0.5))],
    ])
    #expect(edits.failures.isEmpty)
    #expect(edits.changed == 1)
    #expect(FileManager.default.fileExists(atPath: SavedVariablesWrite.backupURL(for: url).path))
    let doc = SVDocument.parse(try Data(contentsOf: url))
    #expect(doc.error == nil)
    if case .number(let n) = doc["PCHAT_OPTS"]?.table?.value(at: [.string("NA Megaserver"), .string("@A"), .string("1"), .string("scale")]) {
        #expect(abs(n - 0.5) < 0.001)
    } else {
        Issue.record("scale not updated")
    }
}
