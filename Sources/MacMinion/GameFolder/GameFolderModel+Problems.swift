import AppKit
import MacMinionKit

/// Problems: what looks wrong, grouped into findings, and the links to them from other pages.
extension GameFolderModel {
    /// Clean-up findings plus what's wrong inside the files.
    var allProblems: [SVProblem] { fileProblems + (svProblems ?? []) }

    /// Asks before moving the files of these problems to the Trash; ESO must be closed and a backup comes first.
    func askToCleanUp(_ problems: [SVProblem]) {
        let files = problems.filter { $0.kind.isFileNotInUse && $0.url != nil }
        guard !files.isEmpty else { return }
        pendingTrash = TrashRequest(title: files.count == 1 ? "Move “\(files[0].file)” to the Trash?"
                                        : String(localized: "Move \(files.count) files not in use to the Trash?"),
                                    urls: files.compactMap(\.url), bytes: files.reduce(0) { $0 + $1.bytes })
    }

    /// Double-click on a problem: shows it, and never installs, updates, or trashes anything.
    /// A file problem shows in Finder; any other opens its place in the Inspector.
    func openProblem(_ problem: SVProblem) async {
        if let url = problem.url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            await revealProblem(problem)
        }
    }

    /// Opens the file a problem is in, at the place it names.
    func revealProblem(_ problem: SVProblem) async {
        await reveal(file: problem.file, path: problem.path)
    }

    /// Problems grouped by cause and ranked (S-052): what the Problems page lists.
    var healthFindings: [HealthFinding] {
        func folders(_ addons: [InstalledAddon]) -> Set<String> { Set(addons.flatMap { $0.record.dirs.map { $0.lowercased() } }) }
        let context = HealthFindings.Context(
            files: savedVariables, libraries: app.allMissingLibraries, graph: graph, companion: app.companionSnapshot,
            // Every folder with a manifest, unmatched ones too: a library can be installed without being on ESOUI.
            installed: folders(app.installed).union(topFolders.map { Set($0.keys) } ?? []), updatable: folders(app.updates))
        return HealthFindings.build(problems: allProblems, context: context)
    }

    /// "Broken in game: 2 · Clean up: 3" for the Problems summary strip; main findings only.
    func healthSummary(_ findings: [HealthFinding]) -> String {
        let main = findings.filter(\.isMain)
        let parts = HealthFinding.Tier.allCases.compactMap { tier -> String? in
            let count = main.filter { $0.tier == tier }.count
            return count == 0 ? nil : String(localized: "\(tier.title): \(count)")
        }
        return parts.isEmpty ? String(localized: "Nothing to fix") : parts.joined(separator: " · ")
    }

    /// The button's title for a finding's action.
    func title(for action: HealthFinding.Action) -> String {
        switch action {
        case .installLibraries(let folders):
            folders.count == 1 ? String(localized: "Install \(folders[0])") : String(localized: "Install \(folders.count) Libraries")
        case .update(let folders): folders.count == 1 ? String(localized: "Update") : String(localized: "Update \(folders.count)")
        case .showAddon: String(localized: "Show Addon")
        case .restoreFromBackup: String(localized: "Restore from Backup…")
        case .cleanUp: String(localized: "Move to Trash…")
        case .showInInspector: String(localized: "Show in Inspector")
        case .findCharacter: String(localized: "Find Everywhere")
        }
    }

    /// What the button's tooltip says, and why it's disabled when it is.
    func help(for action: HealthFinding.Action) -> String {
        switch action {
        case .installLibraries: String(localized: "Install the missing libraries from ESOUI")
        case .update: String(localized: "Install the update from ESOUI")
        case .showAddon: String(localized: "Show this addon on Installed")
        case .restoreFromBackup: String(localized: "Choose a backup to put back only this file")
        case .cleanUp: app.gameIsRunning ? String(localized: "Quit Elder Scrolls Online first") : String(localized: "Back up, then move this to the Trash")
        case .showInInspector: String(localized: "Open this place in the Inspector")
        case .findCharacter: String(localized: "Show every place this character's ID appears, in the Inspector")
        }
    }

    func isDisabled(_ action: HealthFinding.Action) -> Bool {
        switch action {
        case .cleanUp: app.gameIsRunning || app.backupBusy != nil
        case .installLibraries, .update: app.installingLibraries || app.batch != nil
        case .showAddon(let folder): app.installedAddon(folder: folder) == nil
        case .restoreFromBackup, .showInInspector, .findCharacter: false
        }
    }

    /// Runs a finding's action: install, update, open Installed or Backups, reveal, or ask to clean up.
    func run(_ action: HealthFinding.Action, in finding: HealthFinding) {
        switch action {
        case .installLibraries(let folders):
            let libs = app.libraries(for: folders)
            Task { await app.installLibraries(libs) }
        case .update(let folders):
            let ids = folders.compactMap { app.installedAddon(folder: $0)?.id }
            Task { for id in ids { await app.install(id) } }
        case .showAddon(let folder):
            if let addon = app.installedAddon(folder: folder) { app.open(.installed, selecting: addon.id) }
        case .restoreFromBackup(let files):
            if let file = files.first { app.focusBackups(on: file) } else { app.open(.backups) }
        case .cleanUp(let ids):
            askToCleanUp(allProblems.filter { ids.contains($0.id) })
        case .showInInspector(let id):
            if let problem = finding.problems.first(where: { $0.id == id }) { Task { await revealProblem(problem) } }
        case .findCharacter(let id):
            app.open(.gameFolder)
            Task { await findEverywhere(SVTarget(.character, id)) }
        }
    }

    /// The finding selected on Problems, while Problems shows.
    var selectedFinding: HealthFinding? {
        guard app.sidebar == .gameFolder, tab == .problems, let id = problemsSelection else { return nil }
        return healthFindings.first { $0.id == id }
    }

    /// Shows or hides the raw problems of a finding.
    func toggleDetails(_ id: HealthFinding.ID) {
        if problemsExpanded.contains(id) { problemsExpanded.remove(id) } else { problemsExpanded.insert(id) }
    }

    /// The findings to act on that concern the addon saving to this SavedVariables file.
    func findings(aboutFile file: String, in findings: [HealthFinding]) -> [HealthFinding] {
        let folder: String? = if case .addon(let addon)? = savedVariables.first(where: { $0.name == file })?.owner { addon.lowercased() } else { nil }
        return findings.filter { finding in
            // The companion's file reports on other addons; its problems aren't about the companion.
            finding.isMain && (folder.map(finding.addonFolders.contains) == true
                               || (!CompanionData.isCompanionFile(file) && finding.problems.contains { $0.file == file }))
        }
    }

    /// The findings to act on that name this character.
    func findings(aboutCharacter id: String, in findings: [HealthFinding]) -> [HealthFinding] {
        findings.filter { $0.isMain && $0.characterIDs.contains(id) }
    }

    /// Opens Problems with this finding selected.
    func showFinding(_ id: HealthFinding.ID) {
        problemsAddonFilter = nil
        app.open(.gameFolder)
        tab = .problems
        problemsSelection = id
    }

    /// The `.lua` files in the Inspector's list, one addon's while a filter is on.
    var inspectorFiles: [SavedVariablesFile] {
        let files = savedVariables.filter { $0.name.hasSuffix(".lua") }
        guard let filter = inspectorAddonFilter else { return files }
        return files.filter { file in
            if case .addon(let owner) = file.owner { filter.folders.contains(owner.lowercased()) } else { false }
        }
    }

    /// Each installed folder's SavedVariables files, and the findings to act on.
    func addonLinkIndex() -> AddonLinkIndex {
        var files: [String: [String]] = [:]
        for file in savedVariables where file.name.hasSuffix(".lua") && !CompanionData.isCompanionFile(file.name) {
            if case .addon(let owner) = file.owner { files[owner.lowercased(), default: []].append(file.name) }
        }
        return AddonLinkIndex(main: healthFindings.filter(\.isMain), files: files)
    }

    /// Reads the game folder for Installed's icons, once: until Game Folder was opened, nothing was read.
    func readGameFolderForLinks() async {
        if savedVariables.isEmpty { await scan() }
        await load()
    }

    /// Opens the Inspector with only this addon's files in its list, the first one open.
    func showFiles(of name: String, dirs: [String]) {
        if inspectorResults != nil { clearFind() }
        if inspectorConnections != nil { closeConnections() }
        inspectorAddonFilter = AddonFilter(name: name, dirs: dirs)
        app.open(.gameFolder)
        tab = .inspector
        let files = inspectorFiles.map(\.name)
        if let first = files.first, !files.contains(inspectorFile ?? "") {
            Task { await inspect(first) }
        }
    }

    /// Opens Problems with only this addon's findings, the first one selected.
    func showProblems(of name: String, dirs: [String]) {
        let filter = AddonFilter(name: name, dirs: dirs)
        problemsAddonFilter = filter
        app.open(.gameFolder)
        tab = .problems
        problemsSelection = healthFindings.first { $0.isMain && filter.matches($0) }?.id
    }
}
