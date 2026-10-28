import AppKit
import MacMinionKit

/// Self-test for agents: runs the app's real functions on the seeded /tmp store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/MacMinion-self ~/Applications/MacMinion.app/Contents/MacOS/MacMinion --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a folder in /tmp")
            finish(code: 1)
            return
        }
        Task {
            @MainActor func status(_ id: Int) -> AddonStatus? { model.installed(id)?.status }

            // S-001, S-002
            check("the seeded catalog loads", model.catalog.count == SeedData.samples.count)
            check("installed addons are matched by folder", model.installed.count == 5, "\(model.installed.count)")
            check("a folder without a catalog entry is unmatched", model.unmatched.map(\.folder) == ["EsoVendorJunk"])
            check("an older recorded version is an update", status(7) == .updateAvailable)
            check("a matching manifest version is up to date", status(97) == .upToDate)
            check("ignored addons are not updates", status(1146) == .ignored && !model.updates.contains { $0.id == 1146 })
            check("the update count leaves out ignored addons", model.updates.count == 2, "\(model.updates.count)")

            // S-012 Overview
            check("the seeded history loads newest first", model.history.first?.date ?? .distantPast >= model.history.last?.date ?? .now)
            check("weekly counts cover 26 weeks", Usage.weekly(model.history, weeks: 26).count == 26)
            let historyBefore = model.history.count

            // S-023 Libraries: what installed addons ask for and lack, required first.
            check("missing libraries are found", model.missingLibraries.map(\.folder) == ["LibLazyCrafting", "LibDebugLogger"])
            check("a DependsOn library is flagged required", model.missingLibraries.first?.required == true
                  && model.missingLibraries.last?.wantedBy == ["HarvestMap", "WritWorthy"])

            // S-003
            await model.install(7)
            check("an update is added to the history", model.history.count == historyBefore + 1
                  && model.history.first?.kind == .update && model.history.first?.previousVersion == "2.0 r42")
            check("Update installs the latest version", status(7) == .upToDate, model.errors[7] ?? "")
            let manifest = Manifest.read(folder: model.addonsFolder.appending(path: "LibAddonMenu-2.0"))
            check("the new folder is on disk", manifest?.version == "2.0 r43")

            // S-004
            await model.updateAll()
            check("Update All clears every update", model.updates.isEmpty)

            // S-005
            model.search = "merchant"
            check("search matches names", model.findMoreResults.map(\.id) == [1360])
            model.search = "SIRINSIDIATOR"
            check("search matches authors, ignoring case", Set(model.findMoreResults.map(\.id)) == [695, 2275])
            check("Find More leaves out installed addons", !model.findMoreResults.contains { model.installed($0.id) != nil }
                  && Set(model.catalogResults(includeInstalled: true).map(\.id)) == [7, 695, 2275])
            model.search = ""
            model.category = 23
            check("a category includes its children", model.catalogResults(includeInstalled: true).count == 8,
                  "\(model.catalogResults(includeInstalled: true).count)")
            model.category = nil
            await model.install(695)
            check("a new install is logged as an install", model.history.first?.kind == .install && model.history.first?.addonID == 695)
            check("Install adds a new addon", status(695) == .upToDate, model.errors[695] ?? "")

            // S-007
            model.setIgnored(695, true)
            try? await Task.sleep(for: .seconds(0.3))
            check("Ignore Updates is saved", Store.loadState().records[695]?.ignored == true)
            model.setIgnored(695, false)

            // S-006
            if let addon = model.installed(695) {
                await model.remove(addon)
            }
            check("Remove takes the addon off the list", model.installed(695) == nil)
            check("a removal is logged", model.history.first?.kind == .remove)
            check("the history is saved", Store.loadState().history.count == model.history.count)
            check("the AddOns size is measured", (model.addonsSize ?? 0) > 0)
            check("Remove moves its folder out of AddOns",
                  !FileManager.default.fileExists(atPath: model.addonsFolder.appending(path: "AwesomeGuildStore").path))

            // S-013 AI: an unconfigured provider explains itself instead of sending anything.
            model.prefs.aiProvider = .claude
            model.prefs.claudeKey = ""
            await model.summarize(7)
            check("Claude without a key asks for one", model.summaryErrors[7] == "Add a Claude API key in Settings.")
            model.prefs.aiProvider = .ollama
            model.prefs.ollamaModel = ""
            await model.summarize(7)
            check("Ollama without a model asks for one", model.summaryErrors[7] == "Choose an Ollama model in Settings.")
            check("settings stay in memory in test runs", Preferences().aiProvider == .off)

            // S-019 Suggestions: the seeded picks show until installed, and checking never calls a model.
            check("seeded suggestions show on the Overview", model.suggestions.map(\.addon.id) == [1360, 1536, 1245])
            check("updates check once a day by default", Preferences().checkInterval == .day)
            await model.loadBlurbs([1360, 7])
            check("descriptions for suggestions come from addon details", model.blurbs[1360]?.hasPrefix("Master Merchant 3.0 by") == true)

            // S-020 Thumbs: down hides a suggestion and keeps it out of candidates; both go into prompts.
            model.setRating(1360, .down)
            model.setRating(57, .up)
            check("thumbs down hides a suggestion", !model.suggestions.contains { $0.addon.id == 1360 })
            check("thumbs down is left out of AI candidates", model.disliked == [1360])
            check("ratings reach the prompts", model.taste == Taste(liked: ["HarvestMap"], disliked: ["Master Merchant 3.0"]))
            check("ratings are saved", Store.loadState().ratings == [1360: .down, 57: .up])
            model.setRating(1360, nil)
            check("a second click clears the rating", model.rating(1360) == nil)

            // S-021 Versions: an older release installs from the archive and is pinned.
            let versions = (try? await model.loadVersions(57)) ?? []
            check("the archive lists releases newest first", versions.map(\.version) == ["3.16.5", "3.16.4", "3.15.9"])
            if let old = versions.last {
                await model.install(57, version: old)
                let harvest = model.installed(57)
                check("an older version installs", harvest?.installedVersion == "3.15.9", model.errors[57] ?? "")
                check("an older version is pinned", harvest?.status == .ignored)
                await model.install(57, version: versions.first)
                check("installing the latest unpins it", model.installed(57)?.status == .upToDate)
            }

            // S-022 AI search: sample results show; with no provider set it explains instead of sending.
            check("search results show on the Overview", model.searchResults.map(\.addon.id) == [1536, 1605])

            model.setRating(2275, .down)
            check("an optional library with a thumbs down is hidden", !model.missingLibraries.contains { $0.folder == "LibDebugLogger" })
            model.setRating(1594, .down)
            check("a required library shows even with a thumbs down", model.missingLibraries.contains { $0.folder == "LibLazyCrafting" })
            model.setRating(2275, nil)
            model.setRating(1594, nil)
            await model.installLibraries()
            check("Install All installs the missing libraries", model.missingLibraries.isEmpty
                  && model.installed(2275) != nil && model.installed(1594) != nil)

            // S-024 Filters
            model.installedFilter.status = .ignored
            check("Installed filters by status", model.filteredInstalled.map(\.id) == [1146] && model.filteredUnmatched.isEmpty)
            model.installedFilter = BrowseFilter(category: AddonCategory.librariesID)
            check("Installed filters by category", Set(model.filteredInstalled.map(\.id)) == [7, 1146, 2275, 1594])
            model.clearInstalledFilters()
            model.installedSearch = "vendor"
            check("Installed search finds folders not on ESOUI", model.filteredInstalled.isEmpty && model.filteredUnmatched.map(\.folder) == ["EsoVendorJunk"])
            model.clearInstalledFilters()
            model.installedSort = .downloads
            check("Installed sorts by downloads", model.filteredInstalled.first?.id == 7)
            model.installedSort = .name
            model.findMoreFilter.hideLibraries = true
            check("Find More hides libraries", !model.findMoreResults.contains { $0.categoryID == AddonCategory.librariesID })
            model.findMoreFilter = BrowseFilter(recency: .week)
            check("Find More filters by update age", model.findMoreResults.allSatisfy { Date.now.timeIntervalSince($0.date) <= 7 * 86_400 })
            model.clearFindMoreFilters()
            check("Clear Filters turns everything off", !model.findMoreFilter.isActive && !model.installedFiltered)

            // S-025 Overview sections
            let prefs = model.prefs
            check("the Overview starts in the default order", prefs.overviewOrder == OverviewSection.allCases)
            prefs.moveOverview(.popular, by: -99)
            check("a section moves to the top", prefs.visibleOverview.first == .popular)
            prefs.moveOverview(.banner, by: 1)
            check("a section moves down one", prefs.overviewOrder.prefix(3) == [.popular, .libraries, .banner])
            prefs.setOverview(.stats, visible: false)
            check("a hidden section leaves the Overview", !prefs.visibleOverview.contains(.stats) && prefs.overviewOrder.contains(.stats))
            prefs.resetOverview()
            check("Reset restores every section in order", prefs.visibleOverview == OverviewSection.allCases)

            // S-026 Backups in Minion's format
            check("Minion's backups are listed: a dated one and the first one", model.backups.map(\.kind) == [.snapshot, .initial])
            await model.backUp()
            let today = model.backups.first
            check("Back Up Now writes today's zip and addon list", today?.name == MinionBackup.dayFormat.string(from: .now)
                  && today?.addonIDs.count == model.installed.count && model.backups.count == 3, model.backupError ?? "")
            let harvestVars = model.gameFolder.appending(path: "SavedVariables/HarvestMap.lua")
            let original = try? String(contentsOf: harvestVars, encoding: .utf8)
            try? "HarvestMap_SavedVars = { broken }".write(to: harvestVars, atomically: true, encoding: .utf8)
            if let today { await model.restore(today, options: .init(files: true, reinstallMissing: false, removeOthers: false)) }
            check("Restore brings SavedVariables back", (try? String(contentsOf: harvestVars, encoding: .utf8)) == original, model.backupError ?? "")
            check("Restore first saves what was there", FileManager.default.fileExists(atPath: model.restoreSafetyFolder.path))
            if let dustman = model.installed(97) { await model.remove(dustman) }
            await model.install(695)
            if let today { await model.restore(today, options: .init(files: false, reinstallMissing: true, removeOthers: true)) }
            check("Restore installs addons missing from the backup's list", model.installed(97) != nil, model.backupMessage ?? "")
            check("Restore can remove addons not on the list", model.installed(695) == nil)
            if let initial = model.backups.first(where: { $0.kind == .initial }) {
                await model.restore(initial, options: .init(files: true, reinstallMissing: false, removeOthers: false))
                let dustman = Manifest.read(folder: model.addonsFolder.appending(path: "Dustman"))
                check("Minion's first backup restores AddOns folders", dustman?.version == "5.0")
            }
            model.prefs.backupsToKeep = 1
            model.pruneBackups()
            model.loadBackups()
            check("Old backups beyond the number to keep go to the Trash, the first one stays",
                  model.backups.map(\.kind) == [.snapshot, .initial])
            model.prefs.backupsToKeep = 10

            // S-015 Layout
            check("Installed and Find More open as grids", model.prefs.installedLayout == .grid && model.prefs.findMoreLayout == .grid)
            model.sidebar = .installed
            model.setLayout(.list)
            check("the layout switch changes the page on screen", model.prefs.installedLayout == .list && model.prefs.findMoreLayout == .grid)
            model.setLayout(.grid)
            check("Find More features four results above a grid of equal cards", FindMoreGrid.featuredCount == 4)
            check("the accent is Minion Blue by default", ThemeStore.defaultID == "minion"
                  && Theme.all.first { $0.id == "minion" }?.shades?.base == 0x007AFF)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
