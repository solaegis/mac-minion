import Foundation
import Testing
@testable import MacMinionKit

/// Files where order matters: an earlier file names a character, ZO_Ingame's NameChange renames it, a later
/// file's $LastCharacterName doesn't; a character's home on "Default" gives way to a real megaserver.
private let files: [String: String] = [
    "Alpha.lua": """
    Alpha_SV = { ["Default"] = { ["@me"] = { ["8796093036412335"] = { ["$LastCharacterName"] = "Old Name", ["showMap"] = true },
                                            ["$AccountWide"] = { ["guildId"] = 42, ["guildName"] = "Traders" } } } }
    """,
    "Beta.lua": """
    Beta_SV = { ["NA Megaserver"] = { ["@me"] = { ["8796093036412335"] = { ["showMap"] = false, ["owner"] = "8796093036412335" },
                                                 ["8798292071293572"] = { ["$LastCharacterName"] = "Alpha Top", ["showMap"] = true } } } }
    """,
    "ZO_Ingame.lua": """
    ZO_Ingame_SavedVariables = { ["Default"] = { ["@me"] = { ["$AccountWide"] = { ["NameChange"] = { ["8796093036412335"] = "Masisi" } } } } }
    """,
    "Zeta.lua": """
    Zeta_SV = { ["NA Megaserver"] = { ["@me"] = { ["8796093036412335"] = { ["$LastCharacterName"] = "Late Name", ["speed"] = 2 } } } }
    """,
    "Broken.lua": "Broken_SV = { [\"a\"] = { [\"b\"] = \"cut",
]

@Test func twoPassReadMatchesReadingEveryFileAtOnce() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "svfolderread-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for (name, text) in files { try text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8) }
    let urls = files.keys.map { folder.appending(path: $0) }
    let docs = try Dictionary(uniqueKeysWithValues: urls.map { ($0.lastPathComponent, try SVDocument.read($0)) })

    let names = SVNameIndex.build(documents: docs, addons: nil)
    let read = await SVFolderRead.read(urls, addons: nil, declarations: ["beta": ["Beta_SV"]])
    #expect(read.names.characters["8796093036412335"]?.name == "Masisi", "ZO_Ingame's NameChange wins over an earlier file")
    #expect(read.names.characters.mapValues(\.name) == names.characters.mapValues(\.name))
    #expect(read.names.guilds == names.guilds && read.names.ownAccounts == names.ownAccounts)
    #expect(read.references.files == SVReferenceIndex.build(documents: docs, names: names).files
            && read.references.hits == SVReferenceIndex.build(documents: docs, names: names).hits)
    let problems = await SVProblems.checkAll(documents: docs, declarations: ["beta": ["Beta_SV"]])
    #expect(read.problems.map(\.id) == problems.map(\.id) && read.problems.contains { $0.file == "Broken.lua" && $0.kind == .endsEarly })
    let usage = SVUsage.build(documents: docs, names: names)
    #expect(read.usage.characters == usage.characters && read.usage.files == usage.files && read.usage.totalBytes == usage.totalBytes)
    let matrix = SettingsMatrix.build(documents: docs, names: names)
    #expect(read.matrix.homes["8796093036412335"]?.server == "NA Megaserver", "a real megaserver wins over Default")
    #expect(read.matrix.addons.map(\.file) == matrix.addons.map(\.file) && read.matrix.characterIDs == matrix.characterIDs)
}

@Test func rereadsOnlyTheFilesThatChanged() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "svfolderread-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for (name, text) in files { try text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8) }
    func urls() throws -> [URL] { try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) }
    func same(_ a: SVFolderRead, _ b: SVFolderRead) -> Bool {
        a.names.characters.mapValues(\.name) == b.names.characters.mapValues(\.name) && a.references.files == b.references.files
            && a.references.hits == b.references.hits && a.problems.map(\.id) == b.problems.map(\.id)
            && a.usage.characters == b.usage.characters && a.usage.files == b.usage.files
            && a.matrix.addons.map(\.file) == b.matrix.addons.map(\.file) && a.matrix.characterIDs == b.matrix.characterIDs
    }
    let declared = ["beta": ["Beta_SV"]]
    let (_, first) = await SVFolderRead.read(try urls(), addons: nil, declarations: declared, cache: .init())
    #expect(first.parsed == (5, 5), "every file, in both passes")

    // Nothing changed: nothing is parsed.
    let (again, unchanged) = await SVFolderRead.read(try urls(), addons: nil, declarations: declared, cache: first)
    #expect(unchanged.parsed == (0, 0))
    #expect(same(again, await SVFolderRead.read(try urls(), addons: nil, declarations: declared)))

    // One file's settings change, names don't: only that file is read again.
    let zeta = folder.appending(path: "Zeta.lua")
    try files["Zeta.lua"]!.replacingOccurrences(of: "[\"speed\"] = 2", with: "[\"speed\"] = 3, [\"extra\"] = true").write(to: zeta, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: zeta.path)
    let (oneChanged, afterOne) = await SVFolderRead.read(try urls(), addons: nil, declarations: declared, cache: unchanged)
    #expect(afterOne.parsed == (1, 1))
    #expect(same(oneChanged, await SVFolderRead.read(try urls(), addons: nil, declarations: declared)))

    // A name changes: every file's references are made again, since they depend on names.
    let beta = folder.appending(path: "Beta.lua")
    try files["Beta.lua"]!.replacingOccurrences(of: "Alpha Top", with: "Alpha Bottom").write(to: beta, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: beta.path)
    let (renamed, afterRename) = await SVFolderRead.read(try urls(), addons: nil, declarations: declared, cache: afterOne)
    #expect(afterRename.parsed == (1, 5))
    #expect(renamed.names.characters["8798292071293572"]?.name == "Alpha Bottom")
    #expect(same(renamed, await SVFolderRead.read(try urls(), addons: nil, declarations: declared)))

    // A file goes to the Trash: it drops out, and the rest keep their numbers in name order.
    try FileManager.default.removeItem(at: folder.appending(path: "Alpha.lua"))
    let (removed, afterRemove) = await SVFolderRead.read(try urls(), addons: nil, declarations: declared, cache: afterRename)
    #expect(!removed.references.files.contains("Alpha.lua"))
    #expect(same(removed, await SVFolderRead.read(try urls(), addons: nil, declarations: declared)))
    _ = afterRemove
}

@Test func twoPassReadBuildsTheSameGraphAsWholeDocuments() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "svfolderread-graph-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for (name, text) in files { try text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8) }
    let urls = files.keys.map { folder.appending(path: $0) }
    let docs = try Dictionary(uniqueKeysWithValues: urls.map { ($0.lastPathComponent, try SVDocument.read($0)) })
    let manifests: [String: (addon: String, variables: [String], dependsOn: [String])] = [
        "alpha": ("Alpha", ["Alpha_SV"], []), "beta": ("Beta", ["Beta_SV"], ["LibStub"]),
    ]

    let read = await SVFolderRead.read(urls, addons: nil, declarations: ["beta": ["Beta_SV"]], manifests: manifests)
    var homes: [String: SettingsMatrix.Home] = [:]
    for file in docs.keys.sorted() { SettingsMatrix.mergeHomes(&homes, SettingsMatrix.homes(in: docs[file]!)) }
    let whole = SVGraph.build(.init(documents: docs, addons: manifests, names: read.names, homes: homes, snapshot: nil))
    #expect(read.graph.nodes == whole.nodes)
    #expect(read.graph.out == whole.out)
    #expect(read.graph.provenance == whole.provenance)
    // What Problems groups by: a manifest's dependency, and the global no installed addon declares.
    #expect(read.graph.out[SVGraph.NodeID(.addon, "Beta")]?[.dependsOn]?.contains(SVGraph.NodeID(.addon, "LibStub")) == true)
    #expect(read.graph.nodes[SVGraph.NodeID(.svGlobal, "Zeta_SV")]?["orphan"] == "true")
    // Without manifests the read still builds a graph: every global is an orphan.
    let bare = await SVFolderRead.read(urls, addons: nil, declarations: [:])
    #expect(bare.graph.nodes[SVGraph.NodeID(.svGlobal, "Alpha_SV")]?["orphan"] == "true")
}
