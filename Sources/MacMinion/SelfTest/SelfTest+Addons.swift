import AppKit
import MacMinionKit

extension SelfTest {
    /// Catalog, installed addons, updates, search, install, ignore, and remove (S-001 to S-007, S-012, S-023).
    static func installs(_ model: AppModel) async {
        @MainActor func status(_ id: Int) -> AddonStatus? { model.installed(id)?.status }

        // S-001, S-002
        check("the seeded catalog loads", model.catalog.count == SeedData.samples.count)
        check("installed addons are matched by folder", model.installed.count == 5, "\(model.installed.count)")
        check("a folder without a catalog entry is unmatched", model.unmatched.map(\.folder) == ["EsoVendorJunk"])
        check("the companion addon is identified as installed", model.companionInstalled
              && model.companionManifest?.title == "ESO Mac Minion")
        check("the companion is not listed as not on ESOUI", !model.unmatched.contains { $0.folder == CompanionData.folderName })
        check("the companion is not recommended while it is installed", !model.needsCompanion)
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
    }

    /// AI providers and their keys (S-013, S-027).
    static func ai(_ model: AppModel) async {
        // S-013 AI: an unconfigured provider explains itself instead of sending anything.
        model.prefs.aiProvider = .claude
        model.prefs.removeKey(for: .claude)
        await model.summarize(7)
        check("Claude without a key asks for one", model.summaryErrors[7] == "Add a Claude API key in Settings.")

        // S-027 OpenAI: a third provider, its key per provider and only in memory in test runs.
        model.prefs.aiProvider = .openai
        model.prefs.removeKey(for: .openai)
        await model.summarize(7)
        check("OpenAI without a key asks for one", model.summaryErrors[7] == "Add an OpenAI API key in Settings.")
        check("OpenAI defaults to GPT-6 Astra", model.prefs.aiConfig.model == "gpt-6-astra")
        check("a saved key belongs to its provider", model.prefs.saveKey("sk-selftest-1", for: .openai)
              && model.prefs.apiKey(for: .openai) == "sk-selftest-1" && model.prefs.apiKey(for: .claude).isEmpty)
        check("a key is never saved for Ollama", !model.prefs.saveKey("x", for: .ollama))
        check("keys stay out of UserDefaults", !UserDefaults.standard.dictionaryRepresentation().values
              .contains { ($0 as? String) == "sk-selftest-1" })
        check("keys stay out of new Preferences in test runs", Preferences().apiKey(for: .openai).isEmpty)
        model.prefs.removeKey(for: .openai)
        check("Remove Key forgets it", model.prefs.apiKey(for: .openai).isEmpty)
        check("OpenAI summaries name the model", model.aiSource == "GPT-6 Astra on OpenAI")
        model.prefs.aiProvider = .ollama
        model.prefs.ollamaModel = ""
        await model.summarize(7)
        check("Ollama without a model asks for one", model.summaryErrors[7] == "Choose an Ollama model in Settings.")
        check("settings stay in memory in test runs", Preferences().aiProvider == .off)
    }

    /// Suggestions, thumbs, older versions, and AI search (S-019 to S-022).
    static func suggestions(_ model: AppModel) async {
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
    }

    /// Missing libraries: hidden, grouped under what they break, and installed (S-023, S-052).
    static func libraries(_ model: AppModel) async {
        model.setRating(2275, .down)
        check("an optional library with a thumbs down is hidden", !model.missingLibraries.contains { $0.folder == "LibDebugLogger" })
        model.setRating(1594, .down)
        check("a required library shows even with a thumbs down", model.missingLibraries.contains { $0.folder == "LibLazyCrafting" })
        model.setRating(2275, nil)
        model.setRating(1594, nil)
        await model.gameFolder.scan()
        await model.gameFolder.load()
        if let didnt = (model.gameFolder.svProblems ?? []).first(where: { $0.kind == .didntLoad }) {
            // S-052: the addon that didn't load is grouped under the library it's missing, which one button installs.
            let finding = model.gameFolder.healthFindings.first { $0.problems.contains(didnt) }
            check("Didn't load is grouped under its missing library, with Install",
                  finding?.cause == .missingLibraries && finding?.tier == .broken
                  && finding?.action == .installLibraries(folders: ["LibLazyCrafting"]), "\(String(describing: finding?.action))")
            await model.gameFolder.openProblem(didnt)
            check("double-clicking Didn't load shows it and installs nothing",
                  !model.installingLibraries && model.missingLibraries.contains { $0.folder == "LibLazyCrafting" })
        } else {
            check("Didn't load offers Install for its missing library", false, "no didntLoad problem")
        }
        await model.installLibraries()
        check("Install All installs the missing libraries", model.missingLibraries.isEmpty
              && model.installed(2275) != nil && model.installed(1594) != nil)
    }

    /// Filters, sorting, and the Overview's sections (S-024, S-025).
    static func browse(_ model: AppModel) async {
        // S-024 Filters
        model.installedFilter.status = .ignored
        check("Installed filters by status", model.filteredInstalled.map(\.id) == [1146] && model.filteredUnmatched.isEmpty)
        model.installedFilter = BrowseFilter(category: AddonCategory.librariesID)
        check("Installed filters by category", Set(model.filteredInstalled.map(\.id)) == [7, 1146, 2275, 1594])
        model.clearInstalledFilters()
        model.installedSearch = "vendor"
        check("Installed search finds folders not on ESOUI", model.filteredInstalled.isEmpty && model.filteredUnmatched.map(\.folder) == ["EsoVendorJunk"]
              && !model.showCompanion)
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
    }

    /// A creator's name filters the page to their addons (S-065).
    static func creators(_ model: AppModel) async {
        // S-065 A creator's name filters the page to their addons: installed ones on Installed, all on Find More.
        model.open(.installed)
        model.showAddons(by: "shinni")
        check("a creator's name filters Installed to their addons",
              model.filteredInstalled.map(\.catalog.name) == ["HarvestMap"] && model.installedFilter.author == "shinni",
              "\(model.filteredInstalled.map(\.catalog.name))")
        model.installedFilter.author = nil
        model.open(.findMore)
        model.showAddons(by: "Shinni")
        check("on Find More it shows all their work, installed too",
              !model.findMoreResults.isEmpty && model.findMoreResults.allSatisfy { $0.author == "Shinni" }
              && model.findMoreResults.contains { $0.name == "HarvestMap" })
        model.findMoreFilter.author = nil
        model.open(.gameFolder)
    }
}
