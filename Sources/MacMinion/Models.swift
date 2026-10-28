import AppKit
import Foundation
import MacMinionKit

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, installed, updates, findMore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .installed: "Installed"
        case .updates: "Updates"
        case .findMore: "Find More"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .installed: "puzzlepiece.extension"
        case .updates: "arrow.down.circle"
        case .findMore: "magnifyingglass"
        }
    }
}

/// What the detail column shows.
enum Selection: Hashable {
    case addon(Int)
    case folder(String)
}

enum CatalogSort: String, CaseIterable, Identifiable {
    case downloads, monthly, favorites, newest, name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: "Most Downloaded"
        case .monthly: "Popular This Month"
        case .favorites: "Most Favorited"
        case .newest: "Recently Updated"
        case .name: "Name"
        }
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    var sidebar: SidebarItem? = .overview
    var selection: Selection?
    /// Selected after the next page change (the Overview opens an addon on another page).
    var pendingSelection: Selection?
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    // Catalog
    private(set) var catalog: [CatalogAddon] = []
    private(set) var categories: [AddonCategory] = []
    private(set) var catalogDate: Date?
    private(set) var isRefreshing = false
    var refreshError: String?
    var search = ""
    var category: Int?
    var sort: CatalogSort = .downloads

    // Installed
    private(set) var installed: [InstalledAddon] = []
    private(set) var unmatched: [UnmatchedFolder] = []
    private(set) var state = SavedState()
    private(set) var details: [Int: AddonDetails] = [:]
    /// Bytes on disk in the AddOns folder, after a scan.
    private(set) var addonsSize: Int64?

    // Work in progress
    private(set) var busy: Set<Int> = []
    var errors: [Int: String] = [:]
    private(set) var batch: (done: Int, total: Int)?
    var pendingRemoval: InstalledAddon?

    // Settings
    var addonsFolder: URL {
        didSet {
            if !Store.isOverridden { UserDefaults.standard.set(addonsFolder.path, forKey: "addons.path") }
            Task { await rescan() }
        }
    }
    let prefs = Preferences()

    // AI
    private(set) var summaries: [Int: String] = [:]
    private(set) var summarizing: Set<Int> = []
    var summaryErrors: [Int: String] = [:]
    private(set) var digest: String?
    private(set) var isDigesting = false
    var digestError: String?
    var showDigest = false
    private(set) var isSuggesting = false
    var suggestError: String?
    /// Update ids already announced, so a notification only fires for new ones.
    private var notified: Set<Int> = []

    /// Seed and test runs use canned data and never touch the network.
    let offline: Bool
    private let client = MMOUIClient()
    private var started = false

    init(offline: Bool = Store.isOverridden) {
        self.offline = offline
        if Store.isOverridden {
            addonsFolder = Store.directory.appending(path: "AddOns", directoryHint: .isDirectory)
        } else if let path = UserDefaults.standard.string(forKey: "addons.path") {
            addonsFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            addonsFolder = AddonsLocation.live
        }
        state = Store.loadState()
    }

    // MARK: Derived lists

    var updates: [InstalledAddon] { installed.filter { $0.status == .updateAvailable } }

    var history: [HistoryEvent] { state.history }

    func installed(_ id: Int) -> InstalledAddon? { installed.first { $0.id == id } }

    func catalogAddon(_ id: Int) -> CatalogAddon? { catalog.first { $0.id == id } }

    var findMoreResults: [CatalogAddon] {
        var list = catalog
        if let category {
            let ids = AddonCategory.descendants(of: category, in: categories)
            list = list.filter { ids.contains($0.categoryID) }
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            list = list.filter {
                $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || $0.author.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
        switch sort {
        case .downloads: list.sort { $0.downloads > $1.downloads }
        case .monthly: list.sort { $0.downloadsMonthly > $1.downloadsMonthly }
        case .favorites: list.sort { $0.favorites > $1.favorites }
        case .newest: list.sort { $0.date > $1.date }
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return list
    }

    var statusLine: String {
        if let batch { return "Updating \(min(batch.done + 1, batch.total)) of \(batch.total)…" }
        if isRefreshing { return "Checking ESOUI…" }
        if refreshError != nil { return "Couldn't refresh the catalog" }
        guard let catalogDate else { return "Catalog not loaded" }
        return "\(catalog.count.formatted()) addons · updated \(catalogDate.formatted(.relative(presentation: .named)))"
    }

    // MARK: Start and refresh

    func start() async {
        guard !started else { return }
        started = true
        if !Store.isOverridden { importFromMinionIfNeeded() }
        if let cached = await Store.loadCatalog() {
            catalog = cached.addons
            categories = cached.categories
            catalogDate = cached.date
        }
        await rescan()
        guard !offline else { return }
        await refresh()
        Task { await checkLoop() }
    }

    /// Downloads the catalog again, rescans AddOns, and installs updates when that is turned on.
    func refresh() async {
        guard !offline, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            async let addonData = client.catalogData()
            async let categoryData = client.categoriesData()
            let (a, c) = try await (addonData, categoryData)
            let decoded = try await Task.detached { (try MMOUIClient.decodeCatalog(a), try MMOUIClient.decodeCategories(c)) }.value
            catalog = decoded.0
            categories = decoded.1
            catalogDate = .now
            refreshError = nil
            details = [:]
            Store.saveCatalog(addons: a, categories: c)
        } catch {
            refreshError = error.localizedDescription
        }
        await rescan()
        let fresh = updates.filter { !notified.contains($0.id) }
        if prefs.notifyUpdates, !fresh.isEmpty, !prefs.autoUpdate {
            Notifier.updatesReady(fresh.map { Usage.shortName($0.catalog.name) })
        }
        notified = Set(updates.map(\.id))
        if prefs.autoUpdate, !updates.isEmpty { await updateAll() }
    }

    /// Checks ESOUI on the interval chosen in Settings.
    private func checkLoop() async {
        var last = Date.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            let due = last.addingTimeInterval(Double(prefs.checkInterval.rawValue) * 60)
            if prefs.checkAutomatically, Date.now >= due {
                await refresh()
                last = .now
            }
        }
    }

    /// Reads the AddOns folder again and matches it to the catalog.
    func rescan() async {
        guard !catalog.isEmpty else { return }
        let folder = addonsFolder
        let (folders, size) = await Task.detached { (AddonMatcher.scan(folder), Usage.size(of: folder)) }.value
        addonsSize = size
        let result = AddonMatcher.match(folders: folders, catalog: catalog, records: state.records)
        installed = result.installed
        unmatched = result.unmatched
        state.records = result.records
        save()
    }

    // MARK: Install, update, remove

    func loadDetails(_ id: Int) async throws -> AddonDetails {
        if let cached = details[id] { return cached }
        let fetched = try await client.details(for: id)
        details[id] = fetched
        return fetched
    }

    /// Installs or updates one addon. Errors are kept per addon.
    func install(_ id: Int) async {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        errors[id] = nil
        defer { busy.remove(id) }
        do {
            let info = try await loadDetails(id)
            let previous = state.records[id] ?? installed(id)?.record
            let previousVersion = previous?.version ?? installed(id)?.installedVersion
            var record = try await Installer(addons: addonsFolder).install(info)
            record.ignored = previous?.ignored ?? false
            state.records[id] = record
            state.record([HistoryEvent(date: .now, addonID: id, name: catalogAddon(id)?.name ?? "Addon \(id)", version: info.version,
                                       previousVersion: previousVersion, kind: previous == nil ? .install : .update)])
            save()
            await rescan()
        } catch {
            errors[id] = error.localizedDescription
        }
    }

    /// Updates every addon with an update, as many at a time as Settings allows.
    func updateAll() async {
        let ids = updates.map(\.id)
        guard batch == nil, !ids.isEmpty else { return }
        batch = (0, ids.count)
        defer { batch = nil }
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            for _ in 0..<min(prefs.concurrentUpdates, ids.count) {
                let id = ids[next]
                next += 1
                group.addTask { await self.install(id) }
            }
            while await group.next() != nil {
                batch?.done += 1
                if next < ids.count {
                    let id = ids[next]
                    next += 1
                    group.addTask { await self.install(id) }
                }
            }
        }
    }

    func setIgnored(_ id: Int, _ ignored: Bool) {
        state.records[id]?.ignored = ignored
        save()
        Task { await rescan() }
    }

    /// Moves the addon's folders to the Trash.
    func remove(_ addon: InstalledAddon) async {
        do {
            try Installer(addons: addonsFolder).remove(addon.record.dirs)
            state.records[addon.id] = nil
            state.record([HistoryEvent(date: .now, addonID: addon.id, name: addon.catalog.name, version: addon.installedVersion, kind: .remove)])
            if selection == .addon(addon.id), sidebar != .findMore { selection = nil }
            save()
            await rescan()
        } catch {
            errors[addon.id] = error.localizedDescription
        }
    }

    /// Grid or list for the page on screen (Installed or Find More).
    func setLayout(_ layout: BrowseLayout) {
        switch sidebar {
        case .installed: prefs.installedLayout = layout
        case .findMore: prefs.findMoreLayout = layout
        default: break
        }
    }

    /// Opens a page with one addon selected.
    func open(_ page: SidebarItem, selecting id: Int? = nil) {
        pendingSelection = id.map { .addon($0) }
        if sidebar == page {
            selection = pendingSelection
            pendingSelection = nil
        } else {
            sidebar = page
        }
    }

    func showInFinder(_ dir: String? = nil) {
        let url = dir.map { addonsFolder.appending(path: $0) } ?? addonsFolder
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: AI

    /// What changed between the installed version and the latest, from the changelog.
    func summarize(_ id: Int) async {
        guard !summarizing.contains(id), let addon = catalogAddon(id) else { return }
        summarizing.insert(id)
        summaryErrors[id] = nil
        defer { summarizing.remove(id) }
        do {
            let info = try await loadDetails(id)
            let part = ChangelogText.since(installed(id)?.installedVersion, in: BBCode.plainText(info.changelog),
                                           limit: changelogLimit)
            let prompt = AIPrompts.changes(name: addon.name, installed: installed(id)?.installedVersion,
                                           latest: addon.version, changelog: part.text, shortened: part.shortened)
            summaries[id] = nil
            // The text appears as the model writes it.
            summaries[id] = try await AIClient(config: prefs.aiConfig).stream(system: AIPrompts.system, prompt: prompt) { text in
                await MainActor.run { self.summaries[id] = text }
            }
        } catch {
            summaries[id] = nil
            summaryErrors[id] = error.localizedDescription
        }
    }

    /// Changelog characters sent per addon. Local models get less, so the prompt fits their context window.
    private var changelogLimit: Int { prefs.aiProvider == .claude ? 60_000 : 12_000 }

    /// Who writes the summaries, for the card and the CLI.
    var aiSource: String {
        switch prefs.aiProvider {
        case .claude: prefs.claudeModel.title
        case .ollama: "\(prefs.ollamaModel) on Ollama"
        case .off: "the assistant"
        }
    }

    /// One digest of every pending update.
    func digestUpdates() async {
        guard !isDigesting, !updates.isEmpty else { return }
        showDigest = true
        isDigesting = true
        digestError = nil
        digest = nil
        defer { isDigesting = false }
        do {
            var items: [(name: String, installed: String?, latest: String, changelog: String)] = []
            let share = max(1_500, changelogLimit / max(updates.count, 1))
            for addon in updates {
                let info = try await loadDetails(addon.id)
                let part = ChangelogText.since(addon.installedVersion, in: BBCode.plainText(info.changelog), limit: share)
                items.append((addon.catalog.name, addon.installedVersion, addon.catalog.version, part.text))
            }
            digest = try await AIClient(config: prefs.aiConfig).stream(system: AIPrompts.system, prompt: AIPrompts.digest(items)) { text in
                await MainActor.run { self.digest = text }
            }
        } catch {
            digestError = error.localizedDescription
        }
    }

    /// Sends a tiny request to check the AI settings. Returns the answer or throws.
    func testAI() async throws -> String {
        try await AIClient(config: prefs.aiConfig).complete(system: "Answer in five words or fewer.",
                                                           prompt: "Say hello to an Elder Scrolls Online player.")
    }

    // MARK: Suggestions

    /// Saved suggestions still worth showing: in the catalog and not installed since.
    var suggestions: [(addon: CatalogAddon, reason: String)] {
        state.suggestions.compactMap { s in
            guard installed(s.id) == nil, let addon = catalogAddon(s.id) else { return nil }
            return (addon, s.reason)
        }
    }

    var suggestionsDate: Date? { state.suggestionsDate }

    /// Suggestions are a week old, or there are none: the Overview asks again on its own.
    var suggestionsStale: Bool {
        guard let date = state.suggestionsDate else { return true }
        return Date.now.timeIntervalSince(date) > 7 * 86_400 || suggestions.isEmpty
    }

    /// Asks the AI which uninstalled addons would add something to what is installed.
    func suggestAddons() async {
        guard !isSuggesting, !catalog.isEmpty else { return }
        isSuggesting = true
        suggestError = nil
        defer { isSuggesting = false }
        let candidates = AddonRecommender.candidates(catalog: catalog, installed: Set(installed.map(\.id)))
        let prompt = AddonRecommender.prompt(installed: installed.map { Usage.shortName($0.catalog.name) },
                                             candidates: candidates, categories: categories)
        do {
            let answer = try await AIClient(config: prefs.aiConfig).complete(system: AIPrompts.recommendSystem, prompt: prompt)
            let picks = AddonRecommender.parse(answer, candidates: Set(candidates.map(\.id)))
            guard !picks.isEmpty else { throw AIError.empty }
            state.suggestions = picks
            state.suggestionsDate = .now
            save()
        } catch AIError.empty {
            suggestError = "\(aiSource) didn't name any of the candidates. Try again, or pick another model."
        } catch {
            suggestError = error.localizedDescription
        }
    }

    /// Snapshot mode shows a finished summary.
    func setSampleSummary(_ text: String, for id: Int) { summaries[id] = text }

    /// Snapshot mode shows suggestions without asking a model.
    func setSampleSuggestions(_ suggestions: [AddonSuggestion]) {
        state.suggestions = suggestions
        state.suggestionsDate = .now.addingTimeInterval(-3_600)
    }

    // MARK: Minion

    /// Takes the install records from the Java Minion, once.
    func importFromMinionIfNeeded(force: Bool = false) {
        guard force || !state.importedFromMinion || !state.importedMinionHistory, let game = MinionImport.read() else { return }
        for (id, record) in game.records where state.records[id]?.version == nil {
            state.records[id] = record
        }
        state.importedFromMinion = true
        // Minion's auto-update log becomes the start of the history, once.
        if !state.importedMinionHistory || force {
            state.history.removeAll(where: \.fromMinion)
            state.record(game.history)
            state.importedMinionHistory = true
        }
        if UserDefaults.standard.string(forKey: "addons.path") == nil, let path = game.addonPath,
           FileManager.default.fileExists(atPath: path) {
            addonsFolder = URL(fileURLWithPath: path, isDirectory: true)
        }
        save()
        Task { await rescan() }
    }

    // MARK: Seed and test support

    func load(catalog: [CatalogAddon], categories: [AddonCategory], details: [Int: AddonDetails], records: [Int: InstallRecord],
              history: [HistoryEvent] = []) async {
        self.catalog = catalog
        self.categories = categories
        self.details = details
        self.catalogDate = .now.addingTimeInterval(-120)
        state.records = records
        state.history = []
        state.record(history)
        await rescan()
    }

    private func save() { Store.saveState(state) }
}

/// The standard ESO AddOns folders.
enum AddonsLocation {
    static var documents: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents/Elder Scrolls Online") }
    static var live: URL { documents.appending(path: "live/AddOns", directoryHint: .isDirectory) }
    static var pts: URL { documents.appending(path: "pts/AddOns", directoryHint: .isDirectory) }
}
