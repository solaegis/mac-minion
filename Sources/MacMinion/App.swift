import AppKit
import MacMinionKit
import SwiftUI

// MacMinion
//   MacMinion                      the app
//   APP_STORE=<dir> MacMinion      keep state, the catalog cache, and AddOns in another folder (tests, experiments)
//   APP_SNAPSHOT=<dir> MacMinion   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 MacMinion           fill an empty /tmp store with a sample catalog and AddOns folder (tools/snap.sh)
//   MacMinion --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> MacMinion      run with another accent from Theme.all (UI/Theme.swift)
//   APP_LANGUAGE=<code> MacMinion  force UI language (en, de, fr, es, ru) for snapshots and tests
//   APP_GRID=1 MacMinion           draw the 8 pt grid and the layout probes over the window
//   APP_AT_LOGIN=1 MacMinion       start as if opened at login: menu bar only, no window

struct MacMinionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    /// Owned by the delegate, so checks start at launch even when no window opens.
    private var model: AppModel { delegate.model }
    /// MacMinion's own updates (Sparkle). Created at launch so scheduled checks run.
    private let appUpdater = AppUpdater.shared

    var body: some Scene {
        Window("MacMinion", id: "main") {
            ContentView()
                .environment(model)
                .noInitialFocus()
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: MainWindow.minimum.width, minHeight: MainWindow.minimum.height)
        }
        .defaultSize(width: MainWindow.standard.width, height: MainWindow.standard.height)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(after: .toolbar) {
                Button("Show as Grid") { model.setLayout(.grid) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Show as List") { model.setLayout(.list) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Clear Filters") { model.sidebar == .findMore ? model.clearFindMoreFilters() : model.clearInstalledFilters() }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                    .disabled(model.sidebar != .installed && model.sidebar != .findMore)
                Divider()
                PageViewCommands(model: model)
                Divider()
                AppearanceCommands()
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) { CheckForAppUpdatesButton() }
            AddonCommands(model: model)
            HelpCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: Binding(get: { model.prefs.showMenuBarItem }, set: { model.prefs.showMenuBarItem = $0 })) {
            MenuBarMenu()
                .environment(model)
        } label: {
            let count = model.updates.count
            Image(nsImage: MinionGlyph.menuBar)
            if count > 0 { Text("\(count)") }
        }
    }
}

struct AddonCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Addons") {
            Button("Check for Updates") { Task { await model.refresh() } }
                .keyboardShortcut("r")
                .disabled(model.offline)
            Button("Update All") { Task { await model.updateAll() } }
                .keyboardShortcut("u") // hig: ok no Format menu, so Command-U is free for Update All
                .disabled(model.updates.isEmpty || model.batch != nil)
            Button("Back Up Now") { Task { await model.backUp() } }
                .keyboardShortcut("b") // hig: ok no Format menu, so Command-B is free for Back Up Now
                .disabled(model.backupBusy != nil)
            Button("Summarize Pending Updates") { Task { await model.digestUpdates() } }
                .keyboardShortcut("u", modifiers: [.command, .option])
                .disabled(model.updates.isEmpty || !model.prefs.aiEnabled)
            Divider()
            SelectedAddonCommands(model: model)
            Divider()
            BackupCommands(model: model)
            Divider()
            Button("Clean Up SavedVariables…") {
                model.open(.gameFolder)
                model.gameFolder.tab = .problems
                Task { await model.gameFolder.scan(); model.gameFolder.askToTidy() }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(model.backupBusy != nil)
            Button("Clean Up Files Not in Use…") {
                model.open(.gameFolder)
                model.gameFolder.tab = .problems
                Task { await model.gameFolder.scan(); model.gameFolder.askToCleanUp(model.gameFolder.fileProblems) }
            }
            .keyboardShortcut("t", modifiers: [.command, .option, .shift])
            .disabled(model.backupBusy != nil || model.gameIsRunning)
            Divider()
            let selected = model.selectedAddonLinks
            Button("Show Files in Inspector") { if let selected { model.gameFolder.showFiles(of: selected.name, dirs: selected.dirs) } }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(selected?.links.files.isEmpty ?? true)
            Button("Show Problems for Addon") { if let selected { model.gameFolder.showProblems(of: selected.name, dirs: selected.dirs) } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(selected?.links.findings.isEmpty ?? true)
            Button("Show Addons by Creator") { if let author = model.selectedAuthor { model.showAddons(by: author) } }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(model.selectedAuthor == nil)
            Divider()
            Button("Show AddOns Folder in Finder") { model.showInFinder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Show Game Folder in Finder") { model.gameFolder.showInFinder() }
                .keyboardShortcut("g", modifiers: [.command, .option])
        }
        CommandMenu("Inspector") {
            InspectorCommands(model: model)
        }
    }
}

struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let count = model.updates.count
        Text(count == 0 ? String(localized: "All addons are up to date") : String(localized: "\(count) updates available"))
        Button("Update All") { Task { await model.updateAll() } }
            .disabled(count == 0 || model.batch != nil)
        Button("Check for Updates") { Task { await model.refresh() } }
        Divider()
        Button("Open MacMinion") {
            openWindow(id: "main")
            NSApp.activate()
        }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit MacMinion") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceController.applySaved()
        if LaunchMode.atLogin && model.prefs.showMenuBarItem {
            // Opened at login: stay in the menu bar and check quietly.
            NSApp.setActivationPolicy(.accessory)
            DispatchQueue.main.async { NSApp.windows.filter(\.isMainWindowScene).forEach { $0.close() } }
        } else {
            // Started from a terminal, the process is not a foreground app yet.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        watchWindows()
        Task { await Launch.run(model) }
    }

    /// The menu bar item keeps checking for updates after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }

    // MARK: Dock icon

    /// With the menu bar item on, MacMinion leaves the Dock while no window is open; it comes back
    /// with the first window. With the item off, the Dock icon stays, so the app is never out of reach.
    private func updateDockIcon(closing: NSWindow? = nil) {
        let hasWindow = NSApp.windows.contains { $0 !== closing && $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized) }
        let policy: NSApplication.ActivationPolicy = hasWindow || !model.prefs.showMenuBarItem ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular { NSApp.activate() }
    }

    private func watchWindows() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.updateDockIcon() }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated { self.updateDockIcon(closing: window) }
        }
        watchMenuBarSetting()
    }

    private func watchMenuBarSetting() {
        withObservationTracking { _ = model.prefs.showMenuBarItem } onChange: {
            Task { @MainActor in
                self.updateDockIcon()
                self.watchMenuBarSetting()
            }
        }
    }
}

/// Startup work that runs once, whether or not the window opens.
enum Launch {
    private static var task: Task<Void, Never>?

    /// Starts the agent socket and the model. Later callers wait for the first run to finish.
    static func run(_ model: AppModel) async {
        if task == nil {
            task = Task {
                AgentRouter.model = model
                AgentSocket.listen { await AgentRouter.handle($0) }
                await SeedData.insertIfRequested(into: model)
                await model.start()
            }
        }
        await task?.value
    }
}

/// How this process was started.
enum LaunchMode {
    /// True when macOS opened MacMinion as a login item (Settings > General > Open at login).
    static let atLogin: Bool = {
        if ProcessInfo.processInfo.environment["APP_AT_LOGIN"] == "1" { return true }
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }()
}

private extension NSWindow {
    /// The main MacMinion window; SwiftUI names it after the scene's id.
    var isMainWindowScene: Bool { identifier?.rawValue.hasPrefix("main") == true }
}

/// Where the data lives: ~/Library/Application Support/MacMinion/
///   state.json        install records (what was installed, which version, ignored)
///   catalog.json      the last ESOUI file list
///   categories.json   the last ESOUI category list
///   blurbs.json       one-line addon descriptions, for suggestions
///   ai-key-names.json names AI gave SavedVariables keys, per addon version
/// The main window's sizes. Snapshots are taken at both.
enum MainWindow {
    /// How it opens the first time.
    static let standard = CGSize(width: 1180, height: 760)
    /// The smallest it gets.
    static let minimum = CGSize(width: 860, height: 520)
}

enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var directory: URL {
        let dir: URL
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            dir = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            dir = URL.applicationSupportDirectory.appending(path: "MacMinion", directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var stateURL: URL { directory.appending(path: "state.json") }
    private static var catalogURL: URL { directory.appending(path: "catalog.json") }
    private static var categoriesURL: URL { directory.appending(path: "categories.json") }

    static func loadState() -> SavedState {
        guard let data = try? Data(contentsOf: stateURL) else { return SavedState() }
        return (try? JSONDecoder().decode(SavedState.self, from: data)) ?? SavedState()
    }

    static func saveState(_ state: SavedState) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(state) { try? data.write(to: stateURL, options: .atomic) }
    }

    struct CachedCatalog: Sendable {
        var addons: [CatalogAddon]
        var categories: [AddonCategory]
        var date: Date?
    }

    static func loadCatalog() async -> CachedCatalog? {
        let a = catalogURL, c = categoriesURL
        return await Task.detached {
            guard let data = try? Data(contentsOf: a), let addons = try? MMOUIClient.decodeCatalog(data) else { return nil }
            let categories = (try? Data(contentsOf: c)).flatMap { try? MMOUIClient.decodeCategories($0) } ?? []
            let date = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return CachedCatalog(addons: addons, categories: categories, date: date)
        }.value
    }

    private static var aiNamesURL: URL { directory.appending(path: "ai-key-names.json") }

    static func loadAINames() -> SVAINameCache {
        (try? Data(contentsOf: aiNamesURL)).flatMap { try? JSONDecoder().decode(SVAINameCache.self, from: $0) } ?? SVAINameCache()
    }

    static func saveAINames(_ cache: SVAINameCache) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(cache) { try? data.write(to: aiNamesURL, options: .atomic) }
    }

    private static var blurbsURL: URL { directory.appending(path: "blurbs.json") }

    static func loadBlurbs() -> [Int: String] {
        (try? Data(contentsOf: blurbsURL)).flatMap { try? JSONDecoder().decode([Int: String].self, from: $0) } ?? [:]
    }

    static func saveBlurbs(_ blurbs: [Int: String]) {
        if let data = try? JSONEncoder().encode(blurbs) { try? data.write(to: blurbsURL, options: .atomic) }
    }

    static func saveCatalog(addons: Data, categories: Data) {
        try? addons.write(to: catalogURL, options: .atomic)
        try? categories.write(to: categoriesURL, options: .atomic)
    }
}
