import Foundation
import MacMinionKit
import Observation

/// What the Game Folder pages know about SavedVariables: the last full read, whether it is current,
/// and the read under way. `AppModel` owns one, as `gameFolder`.
@Observable
final class GameFolderModel {
    /// The store this belongs to: where the files are, whether the game runs, and the companion's snapshot.
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) { self.app = app }

    /// The last full SavedVariables read, set in one step when a read finishes (`readFiles`).
    var lastRead: SavedVariablesRead?
    /// False from when the SavedVariables files change until they are read again (`AppModel.scanGameFolder`).
    var readIsCurrent = false
    /// The read of the files as they are now; nil before the first read and after the files change.
    var current: SavedVariablesRead? { readIsCurrent ? lastRead : nil }
    var names: SVNameIndex? { current?.names }
    var references: SVReferenceIndex? { current?.references }
    /// What looks wrong inside SavedVariables files, errors first (S-039).
    var svProblems: [SVProblem]? { current?.problems }
    /// What takes space in SavedVariables (S-040).
    var usage: SVUsage? { current?.usage }
    /// Addons' settings per character (S-054).
    var matrix: SettingsMatrix? { current?.matrix }
    /// Each installed addon that saves, by lowercased folder name -> its folder.
    var addonFolders: [String: URL]? { current?.addonFolders }
    // The next four come from the last read even after the files change, so Problems keeps its groups
    // and the character cards keep their servers while the files are read again.
    /// When the last full SavedVariables read finished.
    var readAt: Date? { lastRead?.at }
    /// Accounts, characters, addons, and where they meet: what Problems groups by (S-052).
    var graph: SVGraph? { lastRead?.graph }
    /// SavedVariables file -> the AddOns folder it ships in, for grouping the space map (S-048).
    var topFolders: [String: String]? { lastRead?.topFolders }
    /// MacMinion Companion's character roster, when the addon has written one (S-049).
    var roster: [String: CompanionCharacter]? { lastRead?.roster }

    /// What reading SavedVariables is doing, while it reads, for the progress bar.
    var progress: (step: String, fraction: Double)?
    /// The read under way, so pages that open at the same time wait for it instead of reading again.
    @ObservationIgnored var loading: Task<Void, Never>?
    /// Goes up when the SavedVariables files change, so a read of the old ones isn't kept.
    @ObservationIgnored var generation = 0
    /// Each file's results from the last read, so the next one parses only files that changed.
    @ObservationIgnored var readCache = SVFolderRead.Cache()
    /// Last few parsed trees for Find, Connections, and the Inspector (Step 11).
    @ObservationIgnored var documents = SVDocumentCache(capacity: 4)

    // MARK: Inspector (GameFolderModel+Inspector.swift)

    /// The file open in the Inspector, its bytes, and the rows of the table it shows.
    var inspectorFile: String?
    var inspectorData = Data()
    var inspectorDocument: SVDocument?
    /// Where the Inspector is in the open file. Its rows are kept, not computed, so a 79 000-row table
    /// isn't walked again on every render.
    var inspectorCursor = SVTableCursor()
    /// The open file's variables.
    var inspectorRoots: [SVNode] {
        get { inspectorCursor.roots }
        set { inspectorCursor.roots = newValue }
    }
    /// The table the Inspector shows, as a path from the file's variables; empty for the variables.
    var inspectorFocus: [LuaKey] {
        get { inspectorCursor.focus }
        set { inspectorCursor.focus = newValue }
    }
    /// The rows the Inspector shows: the focused table's entries, or the file's variables.
    var inspectorRows: [SVNode] { inspectorCursor.rows }
    var inspectorSelection: SVNode.ID?
    var inspectorBusy = false
    var inspectorRaw: SVNode?
    /// Settings as you'd read them (S-050), or the tree of keys and values.
    var inspectorReadable = true

    // MARK: Find (GameFolderModel+Find.swift)

    /// The find field's text, its results (nil when not finding), and a request to focus it (Command-F).
    var inspectorQuery = ""
    var inspectorResults: [SVFindResult]?
    var inspectorFindMessage: String?
    var inspectorFindRequested = false

    // MARK: Names from source and AI (GameFolderModel+SourceNames.swift)

    /// SavedVariables file -> what its addon's Lua source says its keys mean (docs/SOURCE-NAMES.md).
    var inspectorSourceNames: [String: SVSourceNames] = [:]
    /// Names AI gave saved keys, per addon version, kept between launches.
    var aiKeyNames = Store.loadAINames()
    /// AI is reading the open table's source.
    var aiNamingBusy = false

    // MARK: Problems (GameFolderModel+Problems.swift)

    /// SavedVariables files and items beside AddOns that nothing uses, from the last scan.
    var fileProblems: [SVProblem] = []
    /// The finding selected on Problems, which the Game Folder menu's Fix and Details items act on.
    var problemsSelection: HealthFinding.ID?
    /// Findings whose raw problems are shown.
    var problemsExpanded: Set<HealthFinding.ID> = []
    /// True when More (findings with nothing to press) is open.
    var problemsMoreExpanded = false
    /// One addon's files in the Inspector's list, from its icon on Installed; nil shows every file.
    var inspectorAddonFilter: AddonFilter?
    /// One addon's findings on Problems, from its icon on Installed; nil shows them all.
    var problemsAddonFilter: AddonFilter?

    // MARK: Connections (GameFolderModel+Connections.swift)

    /// The connections map on screen (S-051), and the IDs it came from, for Back.
    var inspectorConnections: SVNeighborhood?
    var connectionsBack: [SVTarget] = []

    // MARK: Characters (GameFolderModel+Characters.swift)

    /// Where the Characters or Addons explorer is, outermost first (S-053 to S-056).
    var explorerPath: [ExplorerLevel] = [.grid]
    /// The Compare Characters sheet is open (S-057).
    var choosingComparison = false
    /// The character whose differences Compare is asking to clone to the other (S-060).
    var cloneSource: String?
    /// Character pairs backed up before their first copy this run, so each click doesn't make a backup.
    @ObservationIgnored var copyBackedUp: Set<String> = []

    // MARK: Game Settings (GameFolderModel+GameSettings.swift)

    /// The game's settings files on Files > Game Settings, as last read, and the edits not saved yet (S-062).
    var gameSettings: [GameSettingsFile.Kind: GameSettingsFile] = [:]
    var gameSettingsDrafts: [GameSettingsFile.Kind: [Int: String]] = [:]
    var gameSettingsKind: GameSettingsFile.Kind = .user

    // MARK: Files (GameFolderModel+Files.swift)

    /// What the last scan found beside AddOns, and each SavedVariables file with who owns it.
    var gameScan: GameFolderScan?
    var savedVariables: [SavedVariablesFile] = []
    /// The Game Folder tab on screen.
    var tab: GameFolderTab = WindowState.saved.gameFolderTab {
        didSet { WindowState.save(gameFolderTab: tab, to: WindowState.store) }
    }
    /// What the last change did, or why it didn't happen, for the page's banner.
    var message: String?
    var errorMessage: String?
    /// The files a Clean Up is asking to move to the Trash.
    var pendingTrash: TrashRequest?

    /// Reads every SavedVariables file and the libraries' data files once, for names and for where
    /// each ID appears; kept until the files change.
    func load() async {
        // Until everything is read from the current files: wait for a read under way, or start one.
        var reads = 0
        while current == nil {
            if let running = loading {
                await running.value
            } else {
                // The read clears itself before anyone waiting on it wakes, so they never wait on a finished read.
                let load = Task {
                    await readFiles()
                    loading = nil
                }
                loading = load
                await load.value
            }
            // The files keep changing under every read: stop rather than read forever.
            reads += 1
            if reads >= 3 { break }
        }
    }

    /// Reads every SavedVariables file and builds what the Game Folder pages show, reporting each step.
    /// Two passes over the files, each on every core, with only a few files' trees in memory at once,
    /// parsing only files that changed since the last read (`SVFolderRead`).
    private func readFiles() async {
        let files = savedVariables.filter { $0.name.hasSuffix(".lua") }.map(\.url), addons = app.addonsFolder
        let started = generation
        progress = (String(localized: "Reading \(files.count) SavedVariables files…"), 0)
        defer { progress = nil }
        let report: @Sendable (String, Double) async -> Void = { step, fraction in
            await MainActor.run { self.progress = (step, fraction) }
        }
        let cache = readCache
        // The companion reads the globals it's asked for at the next login. Ask only while ESO is closed:
        // the game rewrites its SavedVariables when it saves.
        let mayAskCompanion = !app.gameIsRunning
        let (read, newCache, addonIndex) = await Task.detached {
            let addonIndex = SavedVariablesAudit.index(addons)
            let declarations = addonIndex.savers.mapValues(\.variables)
            if mayAskCompanion, let folder = files.first?.deletingLastPathComponent() {
                _ = try? CompanionRequests.write(svGlobals: CompanionRequests.svGlobals(from: declarations), savedVariables: folder)
            }
            let (read, newCache) = await SVFolderRead.read(files, addons: addons, declarations: declarations,
                                                           manifests: addonIndex.manifests, cache: cache, report: report)
            return (read, newCache, addonIndex)
        }.value
        // Each part is stamped with the size and date its file had when read, so keeping it is safe even if
        // the files changed again since: those files are read again next time.
        readCache = newCache
        retainParsedDocuments(files)
        // The files changed while reading: the caller reads again.
        guard started == generation else { return }
        app.companionSnapshot = read.snapshot ?? app.companionSnapshot
        lastRead = SavedVariablesRead(read, topFolders: addonIndex.topFolders, addonFolders: addonIndex.savers.mapValues(\.url))
        readIsCurrent = true
    }

    /// Drops cached trees whose size or date no longer match the files on disk.
    func retainParsedDocuments(_ urls: [URL]? = nil) {
        let urls = urls ?? savedVariables.filter { $0.name.hasSuffix(".lua") }.map(\.url)
        let stamps = Dictionary(uniqueKeysWithValues: urls.map { ($0.lastPathComponent, SVDocumentCache.Stamp(url: $0)) })
        documents.retain(matching: stamps)
    }
}
