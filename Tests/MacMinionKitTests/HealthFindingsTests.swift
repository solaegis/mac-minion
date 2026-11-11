import Foundation
import Testing
@testable import MacMinionKit

// MARK: Fixtures

private func problem(_ kind: SVProblem.Kind, _ file: String, path: [LuaKey] = [], severity: SVProblem.Severity = .warning,
                     bytes: Int64 = 0, addon: String? = nil) -> SVProblem {
    var p = SVProblem(file: file, path: path, kind: kind, severity: severity, message: "\(kind.rawValue) in \(file)", bytes: bytes)
    p.addon = addon
    return p
}

private func svFile(_ name: String, _ owner: SavedVariablesFile.Owner, bytes: Int64 = 1_000) -> SavedVariablesFile {
    SavedVariablesFile(name: name, url: URL(filePath: "/tmp/SavedVariables/\(name)"), bytes: bytes, modified: nil, owner: owner)
}

private func library(_ folder: String, wantedBy: [String], required: Bool = true) -> MissingLibrary {
    MissingLibrary(folder: folder, addon: CatalogAddon(id: folder.count, categoryID: AddonCategory.librariesID, version: "1", date: .now,
                                                       name: folder, author: "x", dirs: [folder]),
                   wantedBy: wantedBy, required: required)
}

/// A companion snapshot from Lua table bodies for `addons`, `errors`, and `enabledBy`.
private func companion(addons: String, errors: String = "", enabledBy: String = "") throws -> CompanionSnapshot {
    let lua = """
    EsoMacMinion_Data =
    {
        ["NA Megaserver"] = { ["@ME"] = { ["$AccountWide"] = {
            ["schema"] = 1, ["written"] = 1793288692,
            ["characters"] = {
                ["8796093036412335"] = { ["name"] = "Masisi", ["level"] = 50 },
                ["8796093036412336"] = { ["name"] = "Alpha Top", ["level"] = 50 },
            },
            ["addons"] = { \(addons) },
            ["errors"] = { \(errors) },
            ["enabledBy"] = { \(enabledBy) },
        } } },
    }
    """
    return try #require(CompanionData.snapshot(SVDocument.parse(Data(lua.utf8))))
}

private func claimedOnce(_ findings: [HealthFinding], _ input: [SVProblem]) -> Bool {
    findings.flatMap(\.problems).count == input.count
        && findings.flatMap(\.problems).map(\.id).sorted() == input.map(\.id).sorted()
}

// MARK: Every problem, exactly once

@Test func everyKindLandsInExactlyOneFinding() {
    let input = SVProblem.Kind.allCases.enumerated().map { i, kind in
        problem(kind, "File\(i).lua", addon: ["didntLoad", "luaError", "outOfDateAddon", "slowLoad"].contains(kind.rawValue) ? "Addon\(i)" : nil)
    }
    let findings = HealthFindings.build(problems: input, context: .init())
    #expect(claimedOnce(findings, input))
    // Every kind has a tier, and a finding is never below the tier of its own problems' cause.
    for kind in SVProblem.Kind.allCases { _ = HealthFinding.Tier.of(kind) }
}

@Test func aMixOfEveryCauseClaimsEachProblemOnce() throws {
    let snap = try companion(addons: """
        ["Needy"] = { ["title"] = "Needy", ["state"] = "missing", ["missing"] = { [1] = "LibAddonMenu-2.0" } },
        ["Old"] = { ["title"] = "Old", ["state"] = "loaded", ["outOfDate"] = true },
        ["Older"] = { ["title"] = "Older", ["state"] = "loaded", ["outOfDate"] = true },
        ["Slow"] = { ["title"] = "Slow", ["state"] = "loaded", ["loadMs"] = 2500 },
        """, errors: """
        [1] = { ["addon"] = "Needy", ["count"] = 3, ["message"] = "boom" },
        [2] = { ["addon"] = "Old", ["count"] = 7, ["message"] = "bang" },
        """)
    let input = CompanionData.problems(from: snap) + [
        problem(.endsEarly, "Broken.lua", severity: .error), problem(.typeMismatch, "Broken.lua"),
        problem(.missingVariable, "Ignored.lua"), problem(.unknownVariable, "Ignored.lua", path: [.string("X")]),
        problem(.largeFile, "Slow.lua", severity: .note), problem(.longList, "Slow.lua", path: [.string("log")]),
        problem(.unusedFile, "Gone.lua", severity: .note, bytes: 10), problem(.copyFile, "A.lua.bak", severity: .note),
        problem(.staleFile, "Dusty.lua", severity: .note), problem(.typeMismatch, "Mixed.lua", path: [.string("a")]),
        problem(.unknownVariable, "Leftover.lua", path: [.string("Old")]), problem(.empty, "Empty.lua", severity: .note),
    ]
    let context = HealthFindings.Context(files: [svFile("Slow.lua", .addon("Slow")), svFile("Dusty.lua", .addon("Dusty"))],
                                         libraries: [library("LibAddonMenu-2.0", wantedBy: ["Needy"])], companion: snap)
    let findings = HealthFindings.build(problems: input, context: context)
    #expect(claimedOnce(findings, input))
    #expect(Set(findings.map(\.id)).count == findings.count)
    // Shuffled input, same findings in the same order.
    for _ in 0..<5 {
        #expect(HealthFindings.build(problems: input.shuffled(), context: context).map(\.id) == findings.map(\.id))
    }
}

// MARK: Missing library

@Test func aMissingLibraryGroupsItsDependentsFailures() throws {
    let snap = try companion(addons: """
        ["A"] = { ["state"] = "missing", ["missing"] = { [1] = "LibX" } },
        ["B"] = { ["state"] = "missing", ["missing"] = { [1] = "LibX" } },
        """, errors: #"[1] = { ["addon"] = "A", ["count"] = 4, ["message"] = "nil" },"#)
    let input = CompanionData.problems(from: snap)
    let findings = HealthFindings.build(problems: input, context: .init(libraries: [library("LibX", wantedBy: ["A", "B"])], companion: snap))
    #expect(findings.count == 1)
    let f = try #require(findings.first)
    #expect(f.cause == .missingLibraries && f.tier == .broken && f.certainty == .certain)
    #expect(f.action == .installLibraries(folders: ["LibX"]))
    #expect(f.problems.map(\.kind).sorted { $0.rawValue < $1.rawValue } == [.didntLoad, .didntLoad, .luaError])
    #expect(f.title.contains("LibX"))
    #expect(f.summary?.contains("4") == true)
}

@Test func twoLibrariesTheSameAddonNeedsAreOneFinding() throws {
    let snap = try companion(addons: #"["A"] = { ["state"] = "missing", ["missing"] = { [1] = "LibX", [2] = "LibY" } },"#)
    let findings = HealthFindings.build(problems: CompanionData.problems(from: snap),
                                        context: .init(libraries: [library("LibX", wantedBy: ["A"]), library("LibY", wantedBy: ["A"])], companion: snap))
    #expect(findings.count == 1)
    #expect(findings[0].action == .installLibraries(folders: ["LibX", "LibY"]))
}

@Test func anInstalledLibraryThatDidntLoadJoinsTheRootCause() throws {
    // A needs LibB (installed), and LibB didn't load because LibC is missing.
    let snap = try companion(addons: """
        ["A"] = { ["state"] = "missing", ["missing"] = { [1] = "LibB" } },
        ["LibB"] = { ["state"] = "missing", ["missing"] = { [1] = "LibC" } },
        """)
    let findings = HealthFindings.build(problems: CompanionData.problems(from: snap),
                                        context: .init(libraries: [library("LibC", wantedBy: ["LibB"])], companion: snap, installed: ["a", "libb"]))
    #expect(findings.count == 1)
    #expect(findings[0].action == .installLibraries(folders: ["LibC"]))
    #expect(findings[0].problems.count == 2)
}

@Test func aRequiredLibraryWithNoCompanionIsStillAFinding() {
    let findings = HealthFindings.build(problems: [], context: .init(libraries: [library("LibX", wantedBy: ["A"]),
                                                                                 library("LibOpt", wantedBy: ["A"], required: false)]))
    #expect(findings.map(\.cause) == [.missingLibraries])
    #expect(findings[0].tier == .broken && findings[0].problems.isEmpty)
}

// MARK: Out of date

@Test func libStubMeansOutOfDateNeverInstall() throws {
    let snap = try companion(addons: #"["Ancient"] = { ["state"] = "missing", ["missing"] = { [1] = "LibStub" } },"#)
    let findings = HealthFindings.build(problems: CompanionData.problems(from: snap), context: .init(companion: snap))
    #expect(findings.count == 1)
    #expect(findings[0].cause == .outOfDateAddon && findings[0].tier == .broken)
    #expect(findings[0].action == .showAddon(folder: "Ancient"))
    #expect(findings[0].summary?.contains("LibStub") == true)
}

@Test func outOfDateAddonsMergeWithTheirCountInterpreted() throws {
    let snap = try companion(addons: """
        ["A"] = { ["state"] = "loaded", ["outOfDate"] = true },
        ["B"] = { ["state"] = "loaded", ["outOfDate"] = true },
        ["C"] = { ["state"] = "loaded", ["outOfDate"] = true },
        """)
    var graph = SVGraph()
    graph.link(SVGraph.NodeID(.addon, "A"), .dependsOn, SVGraph.NodeID(.addon, "LibStub"),
               SVGraph.Provenance(file: nil, path: [], rule: "manifest", confidence: .high))
    let findings = HealthFindings.build(problems: CompanionData.problems(from: snap),
                                        context: .init(graph: graph, companion: snap, updatable: ["b"]))
    #expect(findings.count == 1)
    let f = findings[0]
    #expect(f.cause == .outOfDateAddons && f.tier == .outOfDate && f.problems.count == 3)
    #expect(f.title.contains("3"))
    #expect(f.summary?.contains("LibStub") == true && f.summary?.contains("update") == true)
    #expect(f.action == .update(folders: ["B"]))
}

@Test func anOutOfDateAddonThrowingErrorsIsBrokenOnItsOwn() throws {
    let snap = try companion(addons: """
        ["A"] = { ["state"] = "loaded", ["outOfDate"] = true },
        ["B"] = { ["state"] = "loaded", ["outOfDate"] = true },
        """, errors: #"[1] = { ["addon"] = "A", ["count"] = 9, ["message"] = "x" },"#)
    let findings = HealthFindings.build(problems: CompanionData.problems(from: snap), context: .init(companion: snap, updatable: ["a"]))
    #expect(findings.map(\.cause) == [.outOfDateAddon, .outOfDateAddons])
    #expect(findings[0].tier == .broken && findings[0].action == .update(folders: ["A"]))
    #expect(findings[1].summary == "No update yet." && findings[1].impact.hasPrefix("It loads"))
}

// MARK: Inside one file

@Test func aDamagedFileTakesTheRestOfItsRows() {
    let input = [problem(.endsEarly, "X.lua", severity: .error), problem(.typeMismatch, "X.lua", path: [.string("a")]),
                 problem(.longList, "X.lua", path: [.string("b")]), problem(.typeMismatch, "Y.lua", path: [.string("a")])]
    let findings = HealthFindings.build(problems: input, context: .init(files: [svFile("X.lua", .addon("Xaddon"))]))
    let damaged = findings.first { $0.cause == .damagedFile }
    #expect(damaged?.problems.count == 3)
    #expect(damaged?.action == .restoreFromBackup(files: ["X.lua"]))
    #expect(damaged?.title.contains("Xaddon") == true)
    #expect(findings.first { $0.cause == .mixedTypes }?.problems.map(\.file) == ["Y.lua"])
}

@Test func undeclaredNamesJoinTheMissingVariableInTheSameFile() {
    let input = [problem(.missingVariable, "W.lua"), problem(.unknownVariable, "W.lua", path: [.string("New")]),
                 problem(.unknownVariable, "V.lua", path: [.string("Old")])]
    let findings = HealthFindings.build(problems: input, context: .init(files: [svFile("W.lua", .addon("W"), bytes: 2_000_000)]))
    let ignored = findings.first { $0.cause == .ignoredData }
    #expect(ignored?.problems.count == 2 && ignored?.tier == .dataAtRisk && ignored?.certainty == .likely)
    let leftover = findings.first { $0.cause == .olderVersionLeftovers }
    #expect(leftover?.problems.map(\.file) == ["V.lua"] && leftover?.isMain == false)
}

@Test func runawayDataNeedsALongListAndTakesTheSlowLoad() throws {
    let snap = try companion(addons: #"["Logger"] = { ["state"] = "loaded", ["loadMs"] = 3000 },"#)
    let input = CompanionData.problems(from: snap) + [
        problem(.largeFile, "Logger.lua", severity: .note), problem(.longList, "Logger.lua", path: [.string("log")]),
        problem(.largeFile, "Big.lua", severity: .note),
    ]
    let findings = HealthFindings.build(problems: input, context: .init(files: [svFile("Logger.lua", .addon("Logger"), bytes: 7_000_000),
                                                                                svFile("Big.lua", .addon("Big"))], companion: snap))
    let runaway = try #require(findings.first { $0.cause == .runawayData })
    #expect(runaway.problems.map(\.kind).contains(.slowLoad) && runaway.problems.count == 3 && runaway.isMain)
    // Size alone is never in the main list.
    let big = try #require(findings.first { $0.problems.first?.file == "Big.lua" })
    #expect(big.tier == .info && !big.isMain)
}

// MARK: Clutter and certainty

@Test func clutterGroupsByCause() {
    let input = [problem(.unusedFile, "Gone1.lua", severity: .note, bytes: 100), problem(.unusedFile, "Gone2.lua", severity: .note, bytes: 200),
                 problem(.copyFile, "a.bak", severity: .note), problem(.strayItem, "SavedVariables.old", severity: .note)]
    let findings = HealthFindings.build(problems: input, context: .init())
    #expect(findings.map(\.cause).sorted { $0.rawValue < $1.rawValue } == [.copiesAndStrays, .removedAddonLeftovers])
    let removed = findings.first { $0.cause == .removedAddonLeftovers }
    #expect(removed?.bytes == 300 && removed?.tier == .clutter)
    #expect(removed?.action == .cleanUp(problemIDs: input.prefix(2).map(\.id)))
}

@Test func staleFileCertaintyFollowsWhoHasTheAddonOn() throws {
    let input = [problem(.staleFile, "Dusty.lua", severity: .note)]
    let files = [svFile("Dusty.lua", .addon("Dusty"))]
    func certainty(_ snap: CompanionSnapshot?) -> (HealthFinding.Certainty?, String?) {
        let f = HealthFindings.build(problems: input, context: .init(files: files, companion: snap)).first
        return (f?.certainty, f?.certaintyNote)
    }
    #expect(certainty(nil).0 == .likely)
    let off = try companion(addons: #"["Dusty"] = { ["state"] = "loaded" },"#, enabledBy: """
        ["8796093036412335"] = { ["disabled"] = { [1] = "Dusty" } },
        ["8796093036412336"] = { ["disabled"] = { [1] = "Dusty" } },
        """)
    #expect(certainty(off).0 == .certain)
    let on = try companion(addons: #"["Dusty"] = { ["state"] = "loaded" },"#, enabledBy: """
        ["8796093036412335"] = { ["disabled"] = { [1] = "Other" } },
        ["8796093036412336"] = { ["disabled"] = { [1] = "Dusty" } },
        """)
    #expect(certainty(on).0 == .possible)
    #expect(certainty(on).1?.contains("Masisi") == true)
}

// MARK: Ranking

@Test func tierBeatsCountAndCountBeatsBytes() throws {
    let snap = try companion(addons: #"["A"] = { ["state"] = "missing" },"#)
    let input = CompanionData.problems(from: snap) + [
        problem(.unusedFile, "Huge.lua", severity: .note, bytes: 900_000_000),
        problem(.typeMismatch, "One.lua", path: [.string("a")]),
        problem(.typeMismatch, "Two.lua", path: [.string("a")]),
    ]
    let files = [svFile("One.lua", .addon("One"), bytes: 1), svFile("Two.lua", .addon("Two"), bytes: 999_999)]
    let findings = HealthFindings.build(problems: input, context: .init(files: files, companion: snap))
    #expect(findings.map(\.tier) == findings.map(\.tier).sorted())
    #expect(findings.first?.tier == .broken)
    #expect(findings.last?.cause == .removedAddonLeftovers)
    // Same tier and reach: the larger runs first only as a tie-breaker, by title otherwise.
    let mixed = findings.filter { $0.cause == .mixedTypes }.map { $0.problems[0].file }
    #expect(mixed == ["One.lua", "Two.lua"])
}

@Test func moreAffectedRanksHigherWithinATier() {
    let input = [problem(.didntLoad, "C.lua", path: [.string("x")], addon: "Solo"),
                 problem(.luaError, "C.lua", path: [.integer(1)], addon: "Pair")]
    var graph = SVGraph()
    for c in ["1", "2"] {
        graph.link(SVGraph.NodeID(.character, c), .enabledFor, SVGraph.NodeID(.addon, "Pair"),
                   SVGraph.Provenance(file: nil, path: [], rule: "companion", confidence: .high))
    }
    let findings = HealthFindings.build(problems: input, context: .init(graph: graph))
    #expect(findings.map { $0.problems[0].addon } == ["Pair", "Solo"])
}

// MARK: Links from other tabs (S-058)

@Test func findingsNameTheAddonFoldersAndCharactersTheyConcern() throws {
    let snap = try companion(addons: """
        ["Needy"] = { ["state"] = "missing", ["missing"] = { [1] = "LibX" } },
        """, enabledBy: """
        ["8796093036412335"] = { ["disabled"] = { } },
        ["8796093036412336"] = { ["disabled"] = { [1] = "Needy" } },
        """)
    let input = CompanionData.problems(from: snap) + [problem(.endsEarly, "Saver.lua", severity: .error)]
    let findings = HealthFindings.build(problems: input, context: .init(files: [svFile("Saver.lua", .addon("Saver"))],
                                                                        libraries: [library("LibX", wantedBy: ["Needy", "Other"])], companion: snap))
    let library = try #require(findings.first { $0.cause == .missingLibraries })
    #expect(library.addonFolders == ["needy", "other"])
    #expect(library.characterIDs == ["8796093036412335"], "only the character with Needy on")
    #expect(library.affected.contains(.character("Masisi")) && !library.affected.contains(.character("Alpha Top")))
    let damaged = try #require(findings.first { $0.cause == .damagedFile })
    #expect(damaged.addonFolders == ["saver"] && damaged.characterIDs.isEmpty)
}

@Test func theCompanionFileNeverMakesAFindingAboutTheCompanion() throws {
    let snap = try companion(addons: #"["Broken"] = { ["state"] = "missing" },"#)
    let findings = HealthFindings.build(problems: CompanionData.problems(from: snap),
                                        context: .init(files: [svFile(snap.file, .addon("EsoMacMinion"))], companion: snap))
    #expect(findings.count == 1)
    #expect(findings[0].addonFolders == ["broken"])
}

@Test func dataForAnUnknownCharacterIsOneCleanUpFindingPerCharacter() {
    func unknown(_ file: String, _ id: String, bytes: Int64) -> SVProblem {
        var p = problem(.unknownCharacter, file, path: [.string(id)], bytes: bytes)
        p.character = id
        return p
    }
    let gone = "8796093011112222", other = "8798292033334444"
    let input = [unknown("WritWorthy.lua", gone, bytes: 400), unknown("HarvestMap.lua", gone, bytes: 600), unknown("pChat.lua", other, bytes: 50)]
    let findings = HealthFindings.build(problems: input, context: .init())
    #expect(claimedOnce(findings, input))
    let mine = findings.first { $0.cause == .unknownCharacter && $0.characterIDs == [gone] }
    #expect(mine?.tier == .clutter && mine?.certainty == .likely && mine?.problems.count == 2 && mine?.bytes == 1_000)
    #expect(mine?.action == .findCharacter(id: gone))
    #expect(mine?.isMain == true)
    #expect(findings.filter { $0.cause == .unknownCharacter }.count == 2)
}
