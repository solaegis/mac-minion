import Foundation
import Testing
@testable import MacMinionKit

private func check(_ text: String, declared: [String]? = nil) -> [SVProblem] {
    SVProblems.check(file: "X.lua", document: SVDocument.parse(Data(text.utf8)), declared: declared)
}

@Test func reportsFilesThatEndEarlyOrBreak() throws {
    let cut = try #require(check("X_Vars =\n{\n    [\"a\"] =\n    {\n        [\"b\"] = \"Mud").first)
    #expect(cut.kind == .endsEarly && cut.severity == .error && cut.path == [.string("X_Vars"), .string("a"), .string("b")])
    #expect(cut.message.hasPrefix("The file stops at line 5, column"))
    #expect(check("X_Vars = { [\"a\"] = @ }").first?.kind == .unreadable)
    #expect(check("").map(\.kind) == [.empty])
    #expect(check("-- only a comment\n").map(\.kind) == [.empty])
}

@Test func comparesVariablesWithTheManifest() {
    let problems = check("X_Old = { [\"a\"] = 1 }\nX_Vars = { [\"b\"] = 2 }\n", declared: ["X_Vars", "X_Global"])
    #expect(problems.map(\.kind) == [.unknownVariable], "X_Global missing is normal: the addon may not use it any more")
    #expect(problems[0].path == [.string("X_Old")])
    let renamed = check("X_Old = { [\"a\"] = 1 }\n", declared: ["X_Vars"])
    #expect(Set(renamed.map(\.kind)) == [.unknownVariable, .missingVariable])
    #expect(check("X_Vars = { }", declared: nil).isEmpty, "no owner, nothing to compare")
}

@Test func findsKeysWhoseTypeDiffersByCharacter() throws {
    let problems = check("""
    X_Vars =
    {
        ["NA Megaserver"] =
        {
            ["@me"] =
            {
                ["8796093036412335"] = { ["count"] = 42, ["on"] = true },
                ["8796093079837777"] = { ["count"] = 7, ["on"] = { } },
                ["8798292071293572"] = { ["count"] = "3", ["on"] = false },
            },
        },
    }
    """)
    #expect(problems.count == 1, "\(problems.map(\.path))")
    let count = try #require(problems.first { $0.path.last == .string("count") })
    #expect(count.kind == .typeMismatch && count.path[3] == .string("8798292071293572"))
    #expect(count.message.contains("a string here but a number in 2 other places"))
    #expect(!problems.contains { $0.path.last == .string("on") }, "false beside a table is how addons write \"no table yet\"")
}

@Test func findsLongListsAndLargeFiles() throws {
    var text = "Log_Vars =\n{\n    [\"log\"] =\n    {\n"
    for i in 1...SVProblems.longList { text += "        [\(i)] = \"line \(i)\",\n" }
    text += "    },\n    [\"byID\"] = { [5] = 1, [9] = 2 },\n    [\"points\"] = { [1] = { 0.5, 0.25, \"Glenumbra\" }, [2] = { \"x\", 1, 2 } },\n}\n"
    let problems = check(text)
    let long = try #require(problems.first)
    #expect(problems.count == 1 && long.kind == .longList && long.path == [.string("Log_Vars"), .string("log")])
    #expect(long.message.hasPrefix("A list of 5,000 entries"))
    let big = SVProblems.check(file: "Big.lua", document: SVDocument(variables: [], error: nil, byteCount: SVProblems.largeFile), declared: nil)
    #expect(big.map(\.kind).contains(.largeFile))
}

/// What the checks report on a real folder, read-only, run by hand:
///   MM_REAL_SV=~/Documents/Elder\ Scrolls\ Online/live/SavedVariables swift test -c release --filter problemsInARealFolder
@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_REAL_SV"] != nil))
func problemsInARealFolder() throws {
    let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MM_REAL_SV"]!)
    let declarations = SavedVariablesAudit.declarations(folder.deletingLastPathComponent().appending(path: "AddOns"))
    var all: [SVProblem] = []
    for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where url.pathExtension == "lua" {
        let name = url.deletingPathExtension().lastPathComponent
        all += SVProblems.check(file: url.lastPathComponent, document: try SVDocument.read(url), declared: declarations[name.lowercased()]?.variables)
    }
    let counts = Dictionary(grouping: all, by: \.kind).mapValues(\.count)
    print("PROBLEMS \(all.count): \(counts.map { "\($0.key.rawValue) \($0.value)" }.sorted().joined(separator: ", "))")
    for p in all.prefix(60) { print("  \(p.severity) \(p.kind.rawValue) \(p.file) \(p.path.map(\.description).joined(separator: " › ").prefix(90))") }
}

@Test func namesPeopleGiveCopiesAreCopies() {
    for name in ["pChat copy", "pChat Copy 2", "pChat (2)", "pChat-backup", "pChat.bak", "pChat_old", "pChat 2026-10-24", "pChat-20261024"] {
        #expect(SavedVariablesAudit.isCopyName(name), "\(name)")
    }
    for name in ["pChat", "Gold", "Copy", "LibAddonMenu-2", "HarvestMapAD", "GS17Data"] {
        #expect(!SavedVariablesAudit.isCopyName(name), "\(name)")
    }
}

@Test func reportsFilesNotInUse() {
    let dir = URL(filePath: "/tmp/sv")
    let now = Date(timeIntervalSince1970: 1_800_000_000), day: TimeInterval = 86_400
    func file(_ name: String, _ owner: SavedVariablesFile.Owner, daysAgo: Double = 0) -> SavedVariablesFile {
        SavedVariablesFile(name: name, url: dir.appending(path: name), bytes: 4096, modified: now - daysAgo * day, owner: owner)
    }
    let files = [file("A.lua", .addon("A")), file("Old.lua", .addon("Old"), daysAgo: 200), file("Recent.lua", .addon("Recent"), daysAgo: 30),
                 file("Gone.lua", .none), file("A copy.lua", .copy), file("ZO_Ingame.lua", .game, daysAgo: 400), file("README.md", .other)]
    let stray = GameFolderItem(name: "AddOns.bak", kind: nil, url: dir.appending(path: "AddOns.bak"), isFolder: true, bytes: 10, modified: nil)
    let problems = SVFileProblems.check(files: files, strays: [stray])
    #expect(problems.map(\.file) == ["A copy.lua", "AddOns.bak", "Gone.lua", "Old.lua"])
    #expect(problems.map(\.kind) == [.copyFile, .strayItem, .unusedFile, .staleFile])
    #expect(problems.allSatisfy { $0.kind.isFileNotInUse && $0.url != nil && $0.severity == .note })
    #expect(problems.last?.message.hasPrefix("Written 200 days before") == true)
}
