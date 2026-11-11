import AppKit
import MacMinionKit

extension SelfTest {
    /// Problems and health findings, their links, and Restore from Backup (S-039, S-052, S-058, S-059).
    static func problems(_ model: AppModel) async {
        // S-039 Find why an addon breaks
        await model.gameFolder.load()
        let problems = model.gameFolder.svProblems ?? []
        @MainActor func problem(_ file: String, _ kind: SVProblem.Kind) -> SVProblem? { problems.first { $0.file == file && $0.kind == kind } }
        check("a file that ends early is an error", problem("Dustman.lua", .endsEarly)?.severity == .error
              && problem("Dustman.lua", .endsEarly)?.path.last == .string("junkName"))
        check("a long list is reported", problem("LibDebugLogger.lua", .longList)?.path == [.string("LibDebugLoggerLog")])
        check("a variable the manifest doesn't declare is reported", problem("LibDebugLogger.lua", .unknownVariable) != nil
              && problem("LibDebugLogger.lua", .missingVariable) != nil)
        check("a key with a different type for one character is reported",
              problem("WritWorthy.lua", .typeMismatch)?.path.last == .string("writCount")
              && problem("WritWorthy.lua", .typeMismatch)?.path[3] == .string("8796093079837777"))
        check("problems are listed by file", problems.map(\.file) == problems.map(\.file).sorted { $0.localizedStandardCompare($1) == .orderedAscending },
              "\(problems.map(\.file))")
        check("clean files have no problems", !problems.contains { $0.file == "ZO_Ingame.lua" || $0.file == "GS00Data.lua" })
        check("companion Lua errors appear in Problems",
              problem(CompanionData.fileName, .luaError)?.message.contains("WizardsWardrobe") == true
              && problem(CompanionData.fileName, .luaError)?.message.contains("12") == true)
        check("an addon that didn't load is a problem",
              problem(CompanionData.fileName, .didntLoad)?.message.contains("LibLazyCrafting") == true)
        // S-052 Health in plain words: one finding per cause, every raw problem in exactly one.
        let findings = model.gameFolder.healthFindings
        @MainActor func finding(with problem: SVProblem?) -> HealthFinding? {
            problem.flatMap { p in findings.first { $0.problems.contains(p) } }
        }
        let grouped = findings.flatMap(\.problems)
        check("every raw problem is in exactly one finding", grouped.count == model.gameFolder.allProblems.count
              && Set(grouped.map(\.id)) == Set(model.gameFolder.allProblems.map(\.id)), "\(grouped.count) of \(model.gameFolder.allProblems.count)")
        check("findings run worst tier first", findings.map(\.tier) == findings.map(\.tier).sorted(), "\(findings.map(\.tier))")
        if let early = problem("Dustman.lua", .endsEarly) {
            let damaged = finding(with: early)
            check("a file that ends early is one Damaged finding offering its backups",
                  damaged?.cause == .damagedFile && damaged?.action == .restoreFromBackup(files: ["Dustman.lua"]))
        }
        let ignored = finding(with: problem("LibDebugLogger.lua", .missingVariable))
        check("undeclared names join the missing variable in one finding",
              ignored?.cause == .ignoredData && ignored?.problems.contains { $0.kind == .unknownVariable } == true)
        let runaway = finding(with: problem("HarvestMapAD.lua", .longList))
        check("a large file with a long list is one finding that keeps growing, in the size tier",
              runaway?.cause == .runawayData && runaway?.tier == .size && runaway?.problems.contains { $0.kind == .largeFile } == true,
              "\(String(describing: runaway?.cause))")
        check("files not in use are one Clean Up finding per cause",
              findings.filter { $0.cause == .removedAddonLeftovers || $0.cause == .copiesAndStrays }.allSatisfy {
                  if case .cleanUp = $0.action { true } else { false }
              })
        if let long = problem("LibDebugLogger.lua", .longList) {
            check("a long list alone offers Show in Inspector", finding(with: long)?.action == .showInInspector(problemID: long.id))
            await model.gameFolder.revealProblem(long)
            check("Show in Inspector opens the file at the problem", model.gameFolder.inspectorFile == "LibDebugLogger.lua"
                  && model.gameFolder.inspectorSelectedNode?.key == .string("LibDebugLoggerLog"))
        }
        // S-058 Problems from other tabs: a link where a finding names an addon or character, never the problem itself.
        let writWorthy = model.gameFolder.findings(aboutFile: "WritWorthy.lua", in: findings)
        check("an addon's card links to the findings about it", writWorthy.contains { $0.cause == .mixedTypes }
              && writWorthy.allSatisfy(\.isMain), "\(writWorthy.map(\.title))")
        check("a file nothing is wrong with has no link", model.gameFolder.findings(aboutFile: "ZO_Ingame.lua", in: findings).isEmpty)
        check("the companion's card has no link for what it reports about other addons",
              model.gameFolder.findings(aboutFile: CompanionData.fileName, in: findings).isEmpty)
        let masisiProblems = model.gameFolder.findings(aboutCharacter: "8796093036412335", in: findings)
        check("a character's page links to what's broken for them", !masisiProblems.isEmpty && masisiProblems.allSatisfy { $0.tier == .broken },
              "\(masisiProblems.map(\.title))")
        if let first = writWorthy.first {
            model.gameFolder.showFinding(first.id)
            check("following a link opens Problems with that finding selected",
                  model.sidebar == .gameFolder && model.gameFolder.tab == .problems && model.gameFolder.selectedFinding?.id == first.id)
            model.gameFolder.problemsSelection = nil
        }
        // S-059 Installed links: an addon's icons open its files in the Inspector and its problems in Problems.
        let linkIndex = model.gameFolder.addonLinkIndex()
        let writLinks = linkIndex.links(for: ["WritWorthy"])
        check("an installed addon links to its SavedVariables files", writLinks.files == ["WritWorthy.lua"], "\(writLinks.files)")
        check("an installed addon counts the problems about it", writLinks.findings.map(\.id) == writWorthy.map(\.id),
              "\(writLinks.findings.map(\.title))")
        let noLinks = linkIndex.links(for: ["NoSuchAddon"])
        check("an addon with no files and no problems shows no icons", noLinks.files.isEmpty && noLinks.findings.isEmpty)
        model.gameFolder.showFiles(of: "WritWorthy", dirs: ["WritWorthy"])
        check("Show Files narrows the Inspector to the addon's files",
              model.gameFolder.tab == .inspector && model.gameFolder.inspectorFiles.map(\.name) == ["WritWorthy.lua"])
        for _ in 0..<50 where model.gameFolder.inspectorFile != "WritWorthy.lua" { try? await Task.sleep(for: .milliseconds(100)) }
        check("Show Files opens the addon's first file", model.gameFolder.inspectorFile == "WritWorthy.lua")
        model.gameFolder.inspectorAddonFilter = nil
        check("Show All Files lists every file again", model.gameFolder.inspectorFiles.count > 1)
        // Opening Game Folder may read the files again; the filter waits for nothing, so wait for the read here.
        await model.gameFolder.load()
        model.gameFolder.showProblems(of: "WritWorthy", dirs: ["WritWorthy"])
        let shownForWrit = model.gameFolder.healthFindings.filter { model.gameFolder.problemsAddonFilter?.matches($0) ?? true }
        check("Show Problems narrows Problems to the addon's findings",
              model.gameFolder.tab == .problems && !shownForWrit.isEmpty
              && shownForWrit.allSatisfy { $0.addonFolders.contains("writworthy") }
              && model.gameFolder.selectedFinding?.id == writWorthy.first?.id,
              "tab \(model.gameFolder.tab) shown \(shownForWrit.map(\.title)) selected \(model.gameFolder.selectedFinding?.title ?? "none") expected \(writWorthy.first?.title ?? "none")")
        if let first = writWorthy.first { model.gameFolder.showFinding(first.id) }
        check("a link to one finding clears the addon filter", model.gameFolder.problemsAddonFilter == nil)
        model.gameFolder.problemsSelection = nil
        // Data kept for a character no file names is a Clean up finding, with Find Everywhere as its button.
        let nameless = "8796093079837777"
        let isNameless: (HealthFinding) -> Bool = { f in f.cause == HealthFinding.Cause.unknownCharacter && f.characterIDs == Set([nameless]) }
        if let unknown = findings.first(where: isNameless) {
            let inCleanUp: Bool = unknown.tier == .clutter && unknown.isMain
            let onlyUnknown: Bool = unknown.problems.allSatisfy { $0.kind == .unknownCharacter }
            let findsIt: Bool = unknown.action == HealthFinding.Action.findCharacter(id: nameless)
            check("an unknown character's data is a Clean up finding", inCleanUp && onlyUnknown && findsIt,
                  "\(unknown.title) \(unknown.problems.map(\.file))")
            if let action = unknown.action { model.gameFolder.run(action, in: unknown) }
            for _ in 0..<50 where model.gameFolder.inspectorResults == nil { try? await Task.sleep(for: .milliseconds(100)) }
            check("Find Everywhere lists where the unknown character's data is",
                  model.gameFolder.tab == .inspector && (model.gameFolder.inspectorResults?.isEmpty == false))
            model.gameFolder.clearFind()
        } else {
            check("an unknown character's data is a Clean up finding", false, "\(findings.map(\.title))")
        }
        check("Problems summary counts findings by tier",
              model.gameFolder.healthSummary(findings).contains(HealthFinding.Tier.broken.title)
              && model.gameFolder.healthSummary(findings).contains(HealthFinding.Tier.clutter.title), model.gameFolder.healthSummary(findings))

        // S-052: Restore from Backup puts back only the damaged file, from a backup that has a good copy.
        let saved = model.gameFolderURL.appending(path: "SavedVariables")
        let dustURL = saved.appending(path: "Dustman.lua"), harvestURL = saved.appending(path: "HarvestMap.lua")
        if let broken = try? Data(contentsOf: dustURL), let harvestBefore = try? Data(contentsOf: harvestURL) {
            let good = "Dustman_SavedVars =\n{\n    [\"Default\"] = { [\"@SOLAEGIS\"] = { [\"$AccountWide\"] = { [\"junkName\"] = \"Mudcrab Chitin\" } } },\n}\n"
            try? good.write(to: dustURL, atomically: true, encoding: .utf8)
            await model.backUp()
            try? broken.write(to: dustURL)
            try? "HarvestMap_SavedVars = { [\"changed\"] = true }\n".write(to: harvestURL, atomically: true, encoding: .utf8)
            let harvestNow = try? Data(contentsOf: harvestURL)
            if let damaged = finding(with: problem("Dustman.lua", .endsEarly)), let action = damaged.action { model.gameFolder.run(action, in: damaged) }
            check("Restore from Backup opens Backups on the damaged file", model.sidebar == .backups && model.backupFocus == "Dustman.lua")
            for _ in 0..<100 where model.backupsHoldingFocus == nil { try? await Task.sleep(for: .milliseconds(100)) }
            let newest = model.backups.first
            check("Backups lists the backups that hold the file",
                  newest.map { model.backupsHoldingFocus?.contains($0.id) == true } == true, "\(String(describing: model.backupsHoldingFocus))")
            if let newest { await model.restoreFile("Dustman.lua", from: newest) }
            check("Restore This File puts back only that file, after saving what was there",
                  (try? String(contentsOf: dustURL, encoding: .utf8)) == good && (try? Data(contentsOf: harvestURL)) == harvestNow
                  && model.backupFocus == nil && model.backupError == nil, model.backupError ?? model.backupMessage ?? "")
            check("the damaged-file finding goes once the file is whole",
                  !model.gameFolder.healthFindings.contains { $0.cause == .damagedFile && $0.problems.contains { $0.file == "Dustman.lua" } },
                  "\(model.gameFolder.healthFindings.map(\.title))")
            // Later checks read the seed as it was: the damaged Dustman.lua and the real HarvestMap.lua.
            try? broken.write(to: dustURL)
            try? harvestBefore.write(to: harvestURL)
            await model.gameFolder.scan()
            await model.gameFolder.load()
        } else {
            check("Restore from Backup opens Backups on the damaged file", false, "no Dustman.lua in the seed")
        }
    }

    /// SavedVariables owners, files not in use, and Clean Up (S-029).
    static func tidy(_ model: AppModel) async {
        // S-029 Tidy SavedVariables
        @MainActor func owner(_ name: String) -> SavedVariablesFile.Owner? { model.gameFolder.savedVariables.first { $0.name == name }?.owner }
        check("a SavedVariables file belongs to its installed addon", owner("HarvestMap.lua") == .addon("HarvestMap"))
        check("an addon nested inside another counts as installed", owner("HarvestMapAD.lua") == .addon("HarvestMapAD"))
        check("the game's own files are never cleaned up", owner("ZO_Ingame.lua") == .game)
        check("a file no installed addon uses is flagged", owner("EsoSocial.lua") == SavedVariablesFile.Owner.none)
        check("a copy inside SavedVariables is flagged", owner("HarvestMap.lua.bak-20261024") == .copy)
        check("files sort by name", model.gameFolder.savedVariables.map(\.name) == model.gameFolder.savedVariables.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending })

        // Problems: files not in use, cleaned up from the Problems tab.
        let sv = model.gameFolderURL.appending(path: "SavedVariables")
        let copy = sv.appending(path: "WritWorthy copy.lua")
        try? "WritWorthy_SavedVars = {}\n".write(to: copy, atomically: true, encoding: .utf8)
        let staleFile = sv.appending(path: "HarvestMapAD.lua")
        let staleDate = try? FileManager.default.attributesOfItem(atPath: staleFile.path)[.modificationDate]
        try? FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-200 * 86_400)], ofItemAtPath: staleFile.path)
        await model.gameFolder.scan()
        @MainActor func fileProblem(_ name: String) -> SVProblem.Kind? { model.gameFolder.fileProblems.first { $0.file == name }?.kind }
        check("a copy named like “X copy.lua” is a problem", owner("WritWorthy copy.lua") == .copy && fileProblem("WritWorthy copy.lua") == .copyFile)
        check("a file no installed addon uses is a problem", fileProblem("EsoSocial.lua") == .unusedFile)
        check("a backup inside SavedVariables is a problem", fileProblem("HarvestMap.lua.bak-20261024") == .copyFile)
        check("an addon's file not written in months is a problem", fileProblem("HarvestMapAD.lua") == .staleFile)
        check("items beside AddOns the game doesn't make are problems", fileProblem("SavedVariables.bak-prune-20261006") == .strayItem)
        check("files in use and the game's files are not problems", fileProblem("HarvestMap.lua") == nil && fileProblem("ZO_Ingame.lua") == nil)
        check("the Problems count includes files not in use", model.gameFolder.allProblems.count == model.gameFolder.fileProblems.count + (model.gameFolder.svProblems?.count ?? 0)
              && model.gameFolder.allProblems.prefix(model.gameFolder.fileProblems.count).allSatisfy(\.kind.isFileNotInUse))
        model.gameFolder.askToCleanUp(model.gameFolder.fileProblems)
        check("Clean Up All asks first, for every file not in use", model.gameFolder.pendingTrash?.urls.count == model.gameFolder.fileProblems.count)
        model.gameFolder.pendingTrash = nil
        model.simulatesRunningGame = true
        model.gameFolder.askToCleanUp(model.gameFolder.fileProblems.filter { $0.file == "WritWorthy copy.lua" })
        if let request = model.gameFolder.pendingTrash { await model.gameFolder.moveToTrash(request) }
        check("cleaning up a problem refuses while ESO runs", FileManager.default.fileExists(atPath: copy.path))
        model.simulatesRunningGame = false
        model.gameFolder.askToCleanUp(model.gameFolder.fileProblems.filter { $0.file == "WritWorthy copy.lua" })
        if let request = model.gameFolder.pendingTrash { await model.gameFolder.moveToTrash(request) }
        check("cleaning up a problem moves just that file to the Trash", !FileManager.default.fileExists(atPath: copy.path)
              && fileProblem("WritWorthy copy.lua") == nil && FileManager.default.fileExists(atPath: staleFile.path))
        if let staleDate { try? FileManager.default.setAttributes([.modificationDate: staleDate], ofItemAtPath: staleFile.path) }
        await model.gameFolder.scan()

        model.simulatesRunningGame = true
        model.gameFolder.askToTidy()
        if let request = model.gameFolder.pendingTrash { await model.gameFolder.moveToTrash(request) }
        check("Clean Up refuses while ESO runs", model.gameFolder.errorMessage != nil
              && FileManager.default.fileExists(atPath: model.gameFolderURL.appending(path: "SavedVariables/EsoSocial.lua").path))
        model.simulatesRunningGame = false
        let backupsBefore = model.backups.count
        model.gameFolder.askToTidy()
        let tidying = model.gameFolder.pendingTrash?.urls.map(\.lastPathComponent).sorted() ?? []
        if let request = model.gameFolder.pendingTrash { await model.gameFolder.moveToTrash(request) }
        check("Clean Up offers what no addon uses and the copies", tidying.contains("EsoSocial.lua") && tidying.contains("HarvestMap.lua.bak-20261024")
              && !tidying.contains("ZO_Ingame.lua") && !tidying.contains("HarvestMap.lua"), "\(tidying)")
        check("Clean Up backs up first, then moves the files to the Trash", model.gameFolder.tidyableSavedVariables.isEmpty
              && model.backups.count >= backupsBefore && model.gameFolder.message != nil
              && FileManager.default.fileExists(atPath: model.gameFolderURL.appending(path: "SavedVariables/HarvestMap.lua").path),
              model.gameFolder.errorMessage ?? "")
        if let copies = model.gameFolder.gameScan?.copies {
            await model.gameFolder.moveToTrash(TrashRequest(title: "", urls: copies.map(\.url), bytes: 0))
            check("copies beside AddOns can go to the Trash", model.gameFolder.gameScan?.copies.isEmpty == true)
        }
    }
}
