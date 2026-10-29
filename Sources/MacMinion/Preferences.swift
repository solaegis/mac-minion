import Foundation
import CoreGraphics
import MacMinionKit
import UserNotifications

/// How often MacMinion checks ESOUI on its own.
enum CheckInterval: Int, CaseIterable, Identifiable {
    case halfHour = 30, hour = 60, threeHours = 180, sixHours = 360, twelveHours = 720, day = 1_440

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .halfHour: "Every 30 Minutes"
        case .hour: "Every Hour"
        case .threeHours: "Every 3 Hours"
        case .sixHours: "Every 6 Hours"
        case .twelveHours: "Every 12 Hours"
        case .day: "Once a Day"
        }
    }
}

/// How Installed and Find More show their addons.
enum BrowseLayout: String, CaseIterable, Identifiable {
    case grid, list

    var id: String { rawValue }
    var title: String { self == .grid ? "Grid" : "List" }
    var symbol: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

/// The size of one bento cell. Wide and large cards span two.
enum CardSize: String, CaseIterable, Identifiable {
    case compact, regular, large

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// The narrowest a one-cell card gets; the grid fits as many columns as it can.
    var minWidth: CGFloat {
        switch self {
        case .compact: 168
        case .regular: 208
        case .large: 256
        }
    }

    var cellHeight: CGFloat {
        switch self {
        case .compact: 96
        case .regular: 112
        case .large: 132
        }
    }
}

/// How often MacMinion backs up settings and SavedVariables on its own.
enum BackupSchedule: String, CaseIterable, Identifiable {
    case off, daily, weekly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Never"
        case .daily: "Every Day"
        case .weekly: "Every Week"
        }
    }

    var days: Double? {
        switch self {
        case .off: nil
        case .daily: 1
        case .weekly: 7
        }
    }
}

/// The sections of the Overview, in their default order.
enum OverviewSection: String, CaseIterable, Identifiable {
    case banner, libraries, stats, recommended, search, history, activity, popular

    var id: String { rawValue }

    var title: String {
        switch self {
        case .banner: "Status Banner"
        case .libraries: "Libraries for Installed Addons"
        case .stats: "At a Glance"
        case .recommended: "Recommended for You"
        case .search: "AI Search"
        case .history: "Updates Installed & By Category"
        case .activity: "Recent Activity & Updated Most Often"
        case .popular: "Popular This Month"
        }
    }

    var symbol: String {
        switch self {
        case .banner: "rectangle.inset.filled"
        case .libraries: "books.vertical"
        case .stats: "square.grid.3x2"
        case .recommended: "sparkles"
        case .search: "sparkle.magnifyingglass"
        case .history: "chart.bar.xaxis"
        case .activity: "clock.arrow.circlepath"
        case .popular: "flame"
        }
    }

    /// When a visible section still stays out of sight.
    var note: String? {
        switch self {
        case .libraries: "Only while a library is missing"
        case .recommended, .search: "Only while an AI provider is set"
        default: nil
        }
    }
}

/// Settings people change in the Settings window. Saved to UserDefaults (API keys to the
/// Keychain), except in test and snapshot runs, which keep everything in memory.
@Observable
final class Preferences {
    private static var persists: Bool { !Store.isOverridden }
    private static let defaults = UserDefaults.standard

    // Updates
    var checkAutomatically: Bool { didSet { Self.save(checkAutomatically, "updates.check") } }
    var checkInterval: CheckInterval { didSet { Self.save(checkInterval.rawValue, "updates.interval") } }
    var autoUpdate: Bool { didSet { Self.save(autoUpdate, "updates.auto") } }
    var concurrentUpdates: Int { didSet { Self.save(concurrentUpdates, "updates.concurrent") } }
    var notifyUpdates: Bool {
        didSet {
            Self.save(notifyUpdates, "updates.notify")
            if notifyUpdates { Notifier.requestPermission() }
        }
    }

    // General
    var showMenuBarItem: Bool { didSet { Self.save(showMenuBarItem, "app.menuBar") } }

    // Backups
    /// The folder Minion keeps backups in (holds minion-backups/ and initial-backup/).
    var backupDir: String { didSet { Self.save(backupDir, "backup.dir") } }
    /// Minion's name for this game install, "ESO-1"; backups go in minion-backups/<id>.
    var backupGameID: String { didSet { Self.save(backupGameID, "backup.gameID") } }
    var backupSchedule: BackupSchedule { didSet { Self.save(backupSchedule.rawValue, "backup.schedule") } }
    /// Snapshots to keep; older ones go to the Trash. 0 keeps every one.
    var backupsToKeep: Int { didSet { Self.save(backupsToKeep, "backup.keep") } }

    var backupFolder: URL { URL(fileURLWithPath: (backupDir as NSString).expandingTildeInPath, isDirectory: true) }

    // Overview
    /// Every section, in the order the Overview shows them.
    var overviewOrder: [OverviewSection] { didSet { Self.save(overviewOrder.map(\.rawValue), "overview.order") } }
    var overviewHidden: Set<OverviewSection> { didSet { Self.save(overviewHidden.map(\.rawValue).sorted(), "overview.hidden") } }

    var visibleOverview: [OverviewSection] { overviewOrder.filter { !overviewHidden.contains($0) } }

    func moveOverview(_ section: OverviewSection, by offset: Int) {
        guard let i = overviewOrder.firstIndex(of: section) else { return }
        let j = min(max(i + offset, 0), overviewOrder.count - 1)
        guard i != j else { return }
        overviewOrder.remove(at: i)
        overviewOrder.insert(section, at: j)
    }

    func moveOverview(from source: IndexSet, to destination: Int) {
        overviewOrder.move(fromOffsets: source, toOffset: destination)
    }

    func setOverview(_ section: OverviewSection, visible: Bool) {
        if visible { overviewHidden.remove(section) } else { overviewHidden.insert(section) }
    }

    func resetOverview() {
        overviewOrder = OverviewSection.allCases
        overviewHidden = []
    }

    // Layout
    var installedLayout: BrowseLayout { didSet { Self.save(installedLayout.rawValue, "layout.installed") } }
    var findMoreLayout: BrowseLayout { didSet { Self.save(findMoreLayout.rawValue, "layout.findMore") } }
    var cardSize: CardSize { didSet { Self.save(cardSize.rawValue, "layout.cardSize") } }
    /// Addons with updates get wide cards at the top of Installed.
    var featureUpdates: Bool { didSet { Self.save(featureUpdates, "layout.featureUpdates") } }
    /// Libraries get their own section at the end of Installed.
    var groupLibraries: Bool { didSet { Self.save(groupLibraries, "layout.groupLibraries") } }
    /// The most popular results in Find More get large cards.
    var featurePopular: Bool { didSet { Self.save(featurePopular, "layout.featurePopular") } }
    var showThumbnails: Bool { didSet { Self.save(showThumbnails, "layout.thumbnails") } }

    // AI
    var aiProvider: AIProvider { didSet { Self.save(aiProvider.rawValue, "ai.provider") } }
    var ollamaURL: String { didSet { Self.save(ollamaURL, "ai.ollama.url") } }
    var ollamaModel: String { didSet { Self.save(ollamaModel, "ai.ollama.model") } }
    var claudeModel: String { didSet { Self.save(claudeModel, "ai.claude.model") } }
    var openAIModel: String { didSet { Self.save(openAIModel, "ai.openai.model") } }
    /// Saved keys, read from the Keychain at launch. Change them with `saveKey` and `removeKey`.
    private(set) var claudeKey: String
    private(set) var openAIKey: String
    /// Last model lists fetched from each provider, for offline use. Model IDs only, never keys.
    var cachedModels: [AIProvider: [String]] {
        didSet { Self.save(Dictionary(uniqueKeysWithValues: cachedModels.map { ($0.key.rawValue, $0.value) }), "ai.models") }
    }
    var summarizeOnOpen: Bool { didSet { Self.save(summarizeOnOpen, "ai.summarizeOnOpen") } }
    /// Measured Ollama speeds on this Mac, by model, from Settings > AI > Benchmark.
    var modelSpeeds: [String: ModelSpeed] {
        didSet { if Self.persists, let data = try? JSONEncoder().encode(modelSpeeds) { Self.defaults.set(data, forKey: "ai.ollama.speeds") } }
    }

    init() {
        let d = Self.persists ? Self.defaults : UserDefaults(suiteName: "MacMinion-test-\(UUID().uuidString)")!
        checkAutomatically = d.object(forKey: "updates.check") as? Bool ?? d.object(forKey: "updates.hourly") as? Bool ?? true
        checkInterval = CheckInterval(rawValue: d.integer(forKey: "updates.interval")) ?? .day
        autoUpdate = d.bool(forKey: "updates.auto")
        concurrentUpdates = min(max(d.object(forKey: "updates.concurrent") as? Int ?? 2, 1), 4)
        notifyUpdates = d.bool(forKey: "updates.notify")
        showMenuBarItem = d.object(forKey: "app.menuBar") as? Bool ?? true
        // Backups default to where Minion keeps its own, so both apps share them.
        let minion = Self.persists ? MinionImport.read() : nil
        backupDir = d.string(forKey: "backup.dir")
            ?? (Self.persists ? minion?.backupDir ?? "~/.minion" : Store.directory.appending(path: "minion").path)
        backupGameID = d.string(forKey: "backup.gameID") ?? minion?.uniqueID ?? "ESO-1"
        backupSchedule = BackupSchedule(rawValue: d.string(forKey: "backup.schedule") ?? "") ?? .weekly
        backupsToKeep = d.object(forKey: "backup.keep") as? Int ?? 10
        // Saved order first; sections added in a later version join at their default place.
        let saved = (d.stringArray(forKey: "overview.order") ?? []).compactMap(OverviewSection.init(rawValue:))
        var order = saved
        for section in OverviewSection.allCases where !order.contains(section) {
            let before = OverviewSection.allCases.prefix { $0 != section }.last.flatMap { order.firstIndex(of: $0) }
            order.insert(section, at: before.map { $0 + 1 } ?? 0)
        }
        overviewOrder = order
        overviewHidden = Set((d.stringArray(forKey: "overview.hidden") ?? []).compactMap(OverviewSection.init(rawValue:)))
        installedLayout = BrowseLayout(rawValue: d.string(forKey: "layout.installed") ?? "") ?? .grid
        findMoreLayout = BrowseLayout(rawValue: d.string(forKey: "layout.findMore") ?? "") ?? .grid
        cardSize = CardSize(rawValue: d.string(forKey: "layout.cardSize") ?? "") ?? .regular
        featureUpdates = d.object(forKey: "layout.featureUpdates") as? Bool ?? true
        groupLibraries = d.object(forKey: "layout.groupLibraries") as? Bool ?? true
        featurePopular = d.object(forKey: "layout.featurePopular") as? Bool ?? true
        showThumbnails = d.object(forKey: "layout.thumbnails") as? Bool ?? true
        aiProvider = AIProvider(rawValue: d.string(forKey: "ai.provider") ?? "") ?? .off
        ollamaURL = d.string(forKey: "ai.ollama.url") ?? AIConfig.defaultOllamaURL.absoluteString
        ollamaModel = d.string(forKey: "ai.ollama.model") ?? ""
        claudeModel = d.string(forKey: "ai.claude.model") ?? AnthropicProvider.defaultModelID
        openAIModel = d.string(forKey: "ai.openai.model") ?? OpenAIProvider.defaultModelID
        claudeKey = Self.persists ? (Self.keychain.key(for: .claude) ?? "") : ""
        openAIKey = Self.persists ? (Self.keychain.key(for: .openai) ?? "") : ""
        let models = d.dictionary(forKey: "ai.models") as? [String: [String]] ?? [:]
        cachedModels = Dictionary(uniqueKeysWithValues: models.compactMap { k, v in AIProvider(rawValue: k).map { ($0, v) } })
        summarizeOnOpen = d.bool(forKey: "ai.summarizeOnOpen")
        modelSpeeds = d.data(forKey: "ai.ollama.speeds").flatMap { try? JSONDecoder().decode([String: ModelSpeed].self, from: $0) } ?? [:]
    }

    var aiConfig: AIConfig {
        AIConfig(provider: aiProvider,
                 ollamaURL: URL(string: ollamaURL.trimmingCharacters(in: .whitespaces)) ?? AIConfig.defaultOllamaURL,
                 ollamaModel: ollamaModel,
                 claudeModel: claudeModel.trimmingCharacters(in: .whitespaces), claudeKey: claudeKey,
                 openAIModel: openAIModel.trimmingCharacters(in: .whitespaces), openAIKey: openAIKey)
    }

    private static let keychain = KeychainStore()

    func apiKey(for provider: AIProvider) -> String {
        switch provider {
        case .claude: claudeKey
        case .openai: openAIKey
        case .off, .ollama: ""
        }
    }

    /// Stores the key in the Keychain (in memory only in test runs). False when the Keychain refused it.
    @discardableResult
    func saveKey(_ key: String, for provider: AIProvider) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard provider.needsKey, !key.isEmpty else { return false }
        if Self.persists, !Self.keychain.save(key, for: provider) { return false }
        setKey(key, for: provider)
        return true
    }

    func removeKey(for provider: AIProvider) {
        if Self.persists { Self.keychain.remove(for: provider) }
        setKey("", for: provider)
    }

    private func setKey(_ key: String, for provider: AIProvider) {
        switch provider {
        case .claude: claudeKey = key
        case .openai: openAIKey = key
        case .off, .ollama: break
        }
    }

    var aiEnabled: Bool { aiProvider != .off }

    private static func save(_ value: Any, _ key: String) {
        if persists { defaults.set(value, forKey: key) }
    }
}

/// "3 addon updates are ready" banners.
enum Notifier {
    static func requestPermission() {
        guard !Store.isOverridden else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func updatesReady(_ names: [String]) {
        guard !Store.isOverridden, !names.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = names.count == 1 ? "1 addon update is ready" : "\(names.count) addon updates are ready"
        content.body = names.prefix(4).joined(separator: ", ") + (names.count > 4 ? ", and more" : "")
        let request = UNNotificationRequest(identifier: "updates", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
