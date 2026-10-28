import AppKit
import Foundation
import MacMinionKit

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, installed, updates, findMore, backups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .installed: "Installed"
        case .updates: "Updates"
        case .findMore: "Find More"
        case .backups: "Backups"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .installed: "puzzlepiece.extension"
        case .updates: "arrow.down.circle"
        case .findMore: "magnifyingglass"
        case .backups: "clock.arrow.circlepath"
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

/// How Installed is ordered inside each section.
enum InstalledSort: String, CaseIterable, Identifiable {
    case name, author, newest, downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Name"
        case .author: "Author"
        case .newest: "Recently Updated on ESOUI"
        case .downloads: "Most Downloaded"
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
    /// The Customize Overview sheet is open.
    var customizingOverview = false
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
    var sort: CatalogSort = .downloads
    /// Find More's filters. `category` is part of them.
    var findMoreFilter = BrowseFilter()
    var category: Int? {
        get { findMoreFilter.category }
        set { findMoreFilter.category = newValue }
    }

    // Installed filters
    var installedFilter = BrowseFilter()
    var installedSearch = ""
    var installedSort: InstalledSort = .name

    // Installed
    private(set) var installed: [InstalledAddon] = []
    private(set) var unmatched: [UnmatchedFolder] = []
    private(set) var state = SavedState()
    private(set) var details: [Int: AddonDetails] = [:]
    /// Bytes on disk in the AddOns folder, after a scan.
    private(set) var addonsSize: Int64?
    /// Every library installed addons ask for (DependsOn, OptionalDependsOn) that isn't in AddOns.
    private(set) var allMissingLibraries: [MissingLibrary] = []

    /// The ones to show: an optional library with a thumbs down stays hidden; a required one always shows,
    /// since the addon that needs it won't load without it.
    var missingLibraries: [MissingLibrary] {
        allMissingLibraries.filter { $0.required || rating($0.addon.id) != .down }
    }
    private(set) var installingLibraries = false
    /// True once AddOns was read and matched since launch.
    private(set) var hasScanned = false
    /// Launch finished loading: the first scan ran, or there was no catalog to scan against.
    private(set) var startupDone = false
    var isReady: Bool { hasScanned || startupDone }
    private(set) var scanError: String?

    // Work in progress
    private(set) var busy: Set<Int> = []
    var errors: [Int: String] = [:]
    private(set) var batch: (done: Int, total: Int)?
    var pendingRemoval: InstalledAddon?
    /// A folder not on ESOUI, waiting for the user to confirm its removal.
    var pendingFolderRemoval: UnmatchedFolder?

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
    /// One-line descriptions by ESOUI id, for suggestions. Saved, since descriptions rarely change.
    private(set) var blurbs: [Int: String] = Store.loadBlurbs()
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

    /// The newest game version the catalog mentions, for "works with the current game version".
    var currentGame: GameVersion? { CurrentGame.current(in: catalog) }

    /// Installed, after the search box, filters, and sort.
    var filteredInstalled: [InstalledAddon] {
        let query = installedSearch.trimmingCharacters(in: .whitespaces)
        let cats = installedFilter.category.map { AddonCategory.descendants(of: $0, in: categories) }
        let game = installedFilter.compatibleOnly ? currentGame?.version : nil
        var list = installed.filter { a in
            (query.isEmpty || a.catalog.name.localizedStandardContains(query) || a.catalog.author.localizedStandardContains(query)
                || a.record.dirs.contains { $0.localizedStandardContains(query) })
                && installedFilter.matches(a.catalog, installed: a, rating: rating(a.id), categories: cats, currentGame: game)
        }
        switch installedSort {
        case .name: list.sort { $0.catalog.name.localizedStandardCompare($1.catalog.name) == .orderedAscending }
        case .author: list.sort { $0.catalog.author.localizedStandardCompare($1.catalog.author) == .orderedAscending }
        case .newest: list.sort { $0.catalog.date > $1.catalog.date }
        case .downloads: list.sort { $0.catalog.downloads > $1.catalog.downloads }
        }
        return list
    }

    /// Folders not on ESOUI have no category, status, or rating: they show only while no filter is on.
    var filteredUnmatched: [UnmatchedFolder] {
        guard !installedFilter.isActive else { return [] }
        let query = installedSearch.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? unmatched : unmatched.filter { $0.title.localizedStandardContains(query) || $0.folder.localizedStandardContains(query) }
    }

    var installedFiltered: Bool { installedFilter.isActive || !installedSearch.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Categories with at least one installed addon, and how many.
    var installedCategories: [(category: AddonCategory, count: Int)] {
        let counts = Dictionary(grouping: installed, by: \.catalog.categoryID).mapValues(\.count)
        return categories.compactMap { c in counts[c.id].map { (c, $0) } }.sorted { $0.category.title < $1.category.title }
    }

    func clearInstalledFilters() {
        installedFilter = BrowseFilter()
        installedSearch = ""
    }

    func clearFindMoreFilters() {
        findMoreFilter = BrowseFilter()
        search = ""
    }

    var updates: [InstalledAddon] { installed.filter { $0.status == .updateAvailable } }

    var history: [HistoryEvent] { state.history }

    func installed(_ id: Int) -> InstalledAddon? { installed.first { $0.id == id } }

    func catalogAddon(_ id: Int) -> CatalogAddon? { catalog.first { $0.id == id } }

    /// Find More: catalog addons that aren't installed, filtered and sorted as the toolbar says.
    var findMoreResults: [CatalogAddon] { catalogResults(includeInstalled: false) }

    func catalogResults(includeInstalled: Bool) -> [CatalogAddon] {
        let have = Set(installed.map(\.id))
        var list = includeInstalled ? catalog : catalog.filter { !have.contains($0.id) }
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
        var rest = findMoreFilter
        rest.category = nil
        if rest.isActive {
            let game = currentGame?.version
            list = list.filter { rest.matches($0, installed: nil, rating: rating($0.id), categories: nil, currentGame: game) }
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
        if scanError != nil { return "Can't read the AddOns folder" }
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
        // With a cached catalog the first scan is done; without one, only after the download.
        if offline || hasScanned { startupDone = true }
        guard !offline else { return }
        await refresh()
        startupDone = true
        loadBackups()
        await backUpIfDue()
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
            await backUpIfDue()
        }
    }

    /// Reads the AddOns folder again and matches it to the catalog.
    func rescan() async {
        guard !catalog.isEmpty else { return }
        let folder = addonsFolder
        let (scanned, nested, size) = await Task.detached {
            (AddonMatcher.scan(folder), AddonMatcher.nested(folder), Usage.size(of: folder))
        }.value
        guard let folders = scanned else {
            // Keep every record: a folder we can't read says nothing about what is installed.
            scanError = "Can't read the AddOns folder at \(folder.path). Check that it exists and that MacMinion may open Documents."
            return
        }
        scanError = nil
        addonsSize = size
        let result = AddonMatcher.match(folders: folders, catalog: catalog, records: state.records)
        installed = result.installed
        unmatched = result.unmatched
        allMissingLibraries = LibraryAdvisor.missing(folders: folders, nested: nested, catalog: catalog)
        // An empty folder with records on file is more likely a wrong folder than a mass uninstall: keep them.
        if !folders.isEmpty || state.records.isEmpty { state.records = result.records }
        hasScanned = true
        save()
    }

    /// Waits for the first scan after launch, so agents and suggestions never see an empty list by accident.
    func waitUntilReady(seconds: Double = 30) async {
        let deadline = Date.now.addingTimeInterval(seconds)
        while !isReady, Date.now < deadline { try? await Task.sleep(for: .milliseconds(200)) }
    }

    // MARK: Install, update, remove

    func loadDetails(_ id: Int) async throws -> AddonDetails {
        if let cached = details[id] { return cached }
        let fetched = try await client.details(for: id)
        details[id] = fetched
        return fetched
    }

    /// Installs or updates one addon. Errors are kept per addon.
    /// Installs the latest release, or `version` from the ESOUI archive. An older version is pinned:
    /// its updates are ignored until the player installs the latest again.
    func install(_ id: Int, version: ArchivedVersion? = nil) async {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        errors[id] = nil
        defer { busy.remove(id) }
        do {
            let latest = try await loadDetails(id)
            let older = version.flatMap { VersionText.same($0.version, latest.version) ? nil : $0 }
            let info = older.map { v in
                AddonDetails(id: id, version: v.version, md5: "", fileName: "\(id)-\(v.aid).zip",
                             downloadURL: archiveURL(id: id, aid: v.aid))
            } ?? latest
            let previous = state.records[id] ?? installed(id)?.record
            let previousVersion = previous?.version ?? installed(id)?.installedVersion
            var record = try await Installer(addons: addonsFolder).install(info)
            record.ignored = older != nil || (version == nil ? previous?.ignored ?? false : false)
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

    /// Installs the given missing libraries, or all of them, one after another.
    func installLibraries(_ libraries: [MissingLibrary]? = nil) async {
        guard !installingLibraries else { return }
        installingLibraries = true
        defer { installingLibraries = false }
        for library in libraries ?? missingLibraries { await install(library.addon.id) }
    }

    func setIgnored(_ id: Int, _ ignored: Bool) {
        state.records[id]?.ignored = ignored
        save()
        Task { await rescan() }
    }

    /// Moves the addon's folders to the Trash.
    /// Moves a folder that isn't on ESOUI to the Trash.
    func removeFolder(_ folder: UnmatchedFolder) async {
        do {
            try Installer(addons: addonsFolder).remove([folder.folder])
            if selection == .folder(folder.folder) { selection = nil }
            await rescan()
        } catch {
            scanError = "Couldn't move \(folder.folder) to the Trash: \(error.localizedDescription)"
        }
    }

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

    // MARK: Backups

    /// Backups in Minion's folder, newest first, then Minion's initial backup.
    private(set) var backups: [Backup] = []
    private(set) var backupBusy: String?
    var backupError: String?
    var backupMessage: String?
    var pendingRestore: Backup?

    /// The folder AddOns sits in (`.../live`): SavedVariables and the settings files are here.
    var gameFolder: URL { addonsFolder.deletingLastPathComponent() }

    func loadBackups() {
        backups = MinionBackup.list(backupDir: prefs.backupFolder, gameID: prefs.backupGameID)
    }

    /// Writes today's backup, Minion style, then trims old ones to the number Settings keeps.
    func backUp() async {
        guard backupBusy == nil else { return }
        backupBusy = "Backing up…"
        backupError = nil
        defer { backupBusy = nil }
        let game = gameFolder, ids = installed.map(\.id), dir = prefs.backupFolder, gameID = prefs.backupGameID
        do {
            let made = try await Task.detached { try MinionBackup.create(gameFolder: game, addonIDs: ids, backupDir: dir, gameID: gameID) }.value
            backupMessage = "Backed up \(ids.count) addons and their settings (\(made.bytes.formatted(.byteCount(style: .file))))."
            pruneBackups()
        } catch {
            backupError = "The backup failed: \(error.localizedDescription)"
        }
        loadBackups()
    }

    /// Moves snapshots beyond the number to keep to the Trash. The initial backup is never touched.
    func pruneBackups() {
        let keep = prefs.backupsToKeep
        guard keep > 0 else { return }
        let snapshots = MinionBackup.list(backupDir: prefs.backupFolder, gameID: prefs.backupGameID).filter { $0.kind == .snapshot }
        for old in snapshots.dropFirst(keep) { trash(old) }
    }

    func deleteBackup(_ backup: Backup) {
        trash(backup)
        loadBackups()
    }

    private func trash(_ backup: Backup) {
        for url in [backup.zip, backup.addonList].compactMap({ $0 }) { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }

    /// Backs up on the schedule in Settings, when the newest backup is old enough.
    func backUpIfDue() async {
        guard let days = prefs.backupSchedule.days, isReady, !installed.isEmpty else { return }
        loadBackups()
        let newest = backups.first { $0.kind == .snapshot }?.date ?? .distantPast
        if Date.now.timeIntervalSince(newest) >= days * 86_400 - 3_600 { await backUp() }
    }

    struct RestoreOptions: Equatable {
        /// SavedVariables and the settings files (or AddOns folders, for an initial backup).
        var files = true
        /// Install addons on the backup's list that aren't installed.
        var reinstallMissing = true
        /// Move installed addons that aren't on the list to the Trash.
        var removeOthers = false
    }

    /// True while Elder Scrolls Online runs; it rewrites SavedVariables when it quits.
    var gameIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            let name = (app.localizedName ?? "").lowercased(), id = (app.bundleIdentifier ?? "").lowercased()
            return name.contains("elder scrolls") || name == "eso" || name.hasPrefix("eso64") || id.contains("zenimax")
        }
    }

    /// Where a restore first saves what is there now, so a restore can itself be undone.
    var restoreSafetyFolder: URL { Store.directory.appending(path: "restore-safety", directoryHint: .isDirectory) }

    /// Restores a backup: its files (SavedVariables and settings, or AddOns folders for an initial
    /// backup), then the addons on its list. Saves the current state first.
    func restore(_ backup: Backup, options: RestoreOptions) async {
        guard backupBusy == nil else { return }
        backupBusy = "Saving what you have now…"
        backupError = nil
        defer { backupBusy = nil }
        let fm = FileManager.default
        let game = gameFolder, ids = installed.map(\.id), safety = restoreSafetyFolder, addons = addonsFolder
        do {
            _ = try await Task.detached { try MinionBackup.create(gameFolder: game, addonIDs: ids, backupDir: safety, gameID: "before-restore") }.value
            var restoredFiles = 0
            if options.files, let zip = backup.zip {
                backupBusy = "Restoring files…"
                let work = fm.temporaryDirectory.appending(path: "MacMinion-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
                defer { try? fm.removeItem(at: work) }
                let files = try await Task.detached { try MinionBackup.unpack(zip, into: work, gameFolder: game) }.value
                // A full AddOns backup replaces whole addon folders, so files from a newer version don't linger.
                let addonFolders = Set(files.compactMap { f -> String? in
                    let rel = f.destination.path.dropFirst(game.path.count + 1).split(separator: "/")
                    return rel.count > 2 && rel[0] == "AddOns" ? String(rel[1]) : nil
                })
                for folder in addonFolders where fm.fileExists(atPath: addons.appending(path: folder).path) {
                    try fm.trashItem(at: addons.appending(path: folder), resultingItemURL: nil)
                }
                for f in files {
                    try fm.createDirectory(at: f.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: f.destination.path) { try fm.removeItem(at: f.destination) }
                    try fm.copyItem(at: f.source, to: f.destination)
                    restoredFiles += 1
                }
            }
            await rescan()
            let list = Set(backup.addonIDs)
            var installedCount = 0, removed = 0
            if !list.isEmpty, options.reinstallMissing {
                let missing = list.filter { installed($0) == nil && catalogAddon($0) != nil }.sorted()
                for (n, id) in missing.enumerated() {
                    backupBusy = "Installing \(n + 1) of \(missing.count)…"
                    await install(id)
                    if errors[id] == nil { installedCount += 1 }
                }
            }
            if !list.isEmpty, options.removeOthers {
                for addon in installed where !list.contains(addon.id) {
                    await remove(addon)
                    removed += 1
                }
            }
            let parts = [restoredFiles > 0 ? "\(restoredFiles) files restored" : nil,
                         installedCount > 0 ? "\(installedCount) addons installed" : nil,
                         removed > 0 ? "\(removed) moved to the Trash" : nil].compactMap { $0 }
            backupMessage = parts.isEmpty ? "Nothing needed restoring." : parts.joined(separator: ", ") + "."
        } catch {
            backupError = "The restore stopped: \(error.localizedDescription). What you had before is saved in \(safety.path)."
        }
        loadBackups()
    }

    // MARK: Ratings

    func rating(_ id: Int) -> Rating? { state.ratings[id] }

    /// Thumbs up, down, or neither. Down also takes the addon out of suggestions and search results.
    func setRating(_ id: Int, _ rating: Rating?) {
        state.ratings[id] = rating
        if rating == .down { searchResults.removeAll { $0.addon.id == id } }
        save()
    }

    var disliked: Set<Int> { Set(state.ratings.filter { $0.value == .down }.keys) }

    /// What the player rated, by name, for prompts.
    var taste: Taste {
        func names(_ r: Rating) -> [String] {
            state.ratings.filter { $0.value == r }.keys.compactMap { catalogAddon($0).map { Usage.shortName($0.name) } }.sorted()
        }
        return Taste(liked: names(.up), disliked: names(.down))
    }

    // MARK: Versions

    /// Archived releases by addon, newest first, from its ESOUI page.
    private(set) var archives: [Int: [ArchivedVersion]] = [:]
    /// Test runs install archived versions from local zips: aid -> file.
    private var localArchives: [Int: URL] = [:]

    func loadVersions(_ id: Int) async throws -> [ArchivedVersion] {
        if let known = archives[id] { return known }
        guard !offline else { return [] }
        let list = try await ESOUIArchive.versions(for: id)
        archives[id] = list
        return list
    }

    private func archiveURL(id: Int, aid: Int) -> URL {
        localArchives[aid] ?? ESOUIArchive.downloadURL(id: id, aid: aid)
    }

    func setSampleArchives(_ list: [ArchivedVersion], for id: Int, files: [Int: URL]) {
        archives[id] = list
        localArchives.merge(files) { _, new in new }
    }

    // MARK: AI search

    var searchQuery = ""
    private(set) var searchResults: [(addon: CatalogAddon, reason: String)] = []
    private(set) var searchStage: String?
    var searchError: String?
    private(set) var searchedFor: String?

    /// Finds catalog addons for a request in plain words: the AI picks keywords and categories, the
    /// catalog is filtered by them, then the AI chooses the best matches, steered by thumbs up and down.
    func aiSearch(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, searchStage == nil, !catalog.isEmpty else { return }
        searchError = nil
        searchResults = []
        searchedFor = query
        defer { searchStage = nil }
        let client = AIClient(config: prefs.aiConfig)
        do {
            searchStage = "Working out what to look for…"
            let plan = AddonSearch.parsePlan(
                try await client.complete(system: AIPrompts.recommendSystem, prompt: AddonSearch.keywordPrompt(query, categories: categories)),
                query: query)
            var found = AddonSearch.candidates(catalog: catalog, plan: plan, blurbs: blurbs, excluded: disliked)
            guard !found.isEmpty else { throw AIError.empty }
            searchStage = "Reading \(found.count) addons…"
            await loadBlurbs(found.map(\.id))
            // With descriptions in hand, score again so description matches count.
            found = AddonSearch.candidates(catalog: catalog, plan: plan, blurbs: blurbs, excluded: disliked)
            let titles = Dictionary(categories.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
            let entries = found.map { c in
                AddonRecommender.Entry(id: c.id, name: c.name, category: titles[c.categoryID] ?? "Other",
                                       blurb: blurbs[c.id] ?? "", monthly: c.downloadsMonthly)
            }
            searchStage = "Choosing the best matches…"
            let answer = try await client.complete(system: AIPrompts.recommendSystem,
                                                   prompt: AddonSearch.pickPrompt(query, candidates: entries,
                                                                                  installed: Set(installed.map(\.id)), taste: taste))
            let picks = AddonRecommender.parse(answer, candidates: Set(found.map(\.id)), limit: AddonSearch.maxResults)
            guard !picks.isEmpty else { throw AIError.empty }
            searchResults = picks.compactMap { p in catalogAddon(p.id).map { ($0, p.reason) } }
        } catch AIError.empty {
            searchError = "Nothing in the catalog matched. Try other words."
        } catch {
            searchError = error.localizedDescription
        }
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
        searchError = nil
        searchedFor = nil
    }

    /// Snapshot mode shows search results without asking a model.
    func setSampleSearch(_ query: String, _ picks: [AddonSuggestion]) {
        searchQuery = query
        searchedFor = query
        searchResults = picks.compactMap { p in catalogAddon(p.id).map { ($0, p.reason) } }
    }

    // MARK: Suggestions

    /// Saved suggestions still worth showing: in the catalog and not installed since.
    var suggestions: [(addon: CatalogAddon, reason: String)] {
        state.suggestions.compactMap { s in
            guard installed(s.id) == nil, rating(s.id) != .down, let addon = catalogAddon(s.id) else { return nil }
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
        await waitUntilReady()
        guard hasScanned, !installed.isEmpty else {
            suggestError = scanError ?? "No installed addons to base suggestions on yet."
            return
        }
        // Any catalog entry that installs into a folder already on disk is a fork or variant of something installed.
        let onDisk = Set(installed.flatMap(\.record.dirs) + unmatched.map(\.folder))
        let candidates = AddonRecommender.candidates(catalog: catalog, installed: Set(installed.map(\.id)).union(disliked),
                                                     folders: onDisk)
        // Installed addons describe themselves in their manifest when they can; the rest come from ESOUI.
        let ownWords = Dictionary(installed.compactMap { a in a.manifest?.description.map { (a.id, $0) } }, uniquingKeysWith: { a, _ in a })
        await loadBlurbs(installed.map(\.id).filter { ownWords[$0] == nil } + candidates.map(\.id))
        let titles = Dictionary(categories.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        let have = installed.map { a in
            AddonRecommender.Entry(id: a.id, name: Usage.shortName(a.catalog.name), category: titles[a.catalog.categoryID] ?? "Other",
                                   blurb: ownWords[a.id].map { AddonRecommender.blurb($0) } ?? blurbs[a.id] ?? "")
        }
        let offer = candidates.map { c in
            AddonRecommender.Entry(id: c.id, name: c.name, category: titles[c.categoryID] ?? "Other",
                                   blurb: blurbs[c.id] ?? "", monthly: c.downloadsMonthly)
        }
        let prompt = AddonRecommender.prompt(installed: have, candidates: offer, taste: taste)
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

    /// Fills `blurbs` for these ids from ESOUI, a few batched requests; offline runs use loaded details.
    func loadBlurbs(_ ids: [Int]) async {
        let missing = Array(Set(ids.filter { blurbs[$0] == nil }))
        guard !missing.isEmpty else { return }
        var fetched: [AddonDetails] = missing.compactMap { details[$0] }
        if !offline, let more = try? await client.details(for: missing.filter { details[$0] == nil }) { fetched += more }
        for d in fetched {
            details[d.id] = d
            blurbs[d.id] = AddonRecommender.blurb(d.description)
        }
        Store.saveBlurbs(blurbs)
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
