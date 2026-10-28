import Foundation
import CoreGraphics
import MacMinionKit
import Security
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

/// Settings people change in the Settings window. Saved to UserDefaults (the Claude key to the
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
    var claudeModel: ClaudeModel { didSet { Self.save(claudeModel.rawValue, "ai.claude.model") } }
    var claudeKey: String { didSet { if Self.persists { Keychain.set(claudeKey, account: Keychain.claudeAccount) } } }
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
        claudeModel = ClaudeModel(rawValue: d.string(forKey: "ai.claude.model") ?? "") ?? .opus
        claudeKey = Self.persists ? (Keychain.get(account: Keychain.claudeAccount) ?? "") : ""
        summarizeOnOpen = d.bool(forKey: "ai.summarizeOnOpen")
        modelSpeeds = d.data(forKey: "ai.ollama.speeds").flatMap { try? JSONDecoder().decode([String: ModelSpeed].self, from: $0) } ?? [:]
    }

    var aiConfig: AIConfig {
        AIConfig(provider: aiProvider,
                 ollamaURL: URL(string: ollamaURL.trimmingCharacters(in: .whitespaces)) ?? AIConfig.defaultOllamaURL,
                 ollamaModel: ollamaModel, claudeModel: claudeModel,
                 claudeKey: claudeKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var aiEnabled: Bool { aiProvider != .off }

    private static func save(_ value: Any, _ key: String) {
        if persists { defaults.set(value, forKey: key) }
    }
}

/// The Claude API key lives in the login Keychain, never in UserDefaults or state.json.
enum Keychain {
    static let service = "com.solaegis.macminion"
    static let claudeAccount = "claude-api-key"

    static func get(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func set(_ value: String, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
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
