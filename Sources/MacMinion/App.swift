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
//   APP_GRID=1 MacMinion           draw the 8 pt grid and the layout probes over the window

struct MacMinionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("MacMinion", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 860, minHeight: 520)
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(after: .toolbar) {
                Button("Show as Grid") { model.setLayout(.grid) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Show as List") { model.setLayout(.list) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .newItem) {}
            AddonCommands(model: model)
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
            Image(systemName: count > 0 ? "puzzlepiece.extension.fill" : "puzzlepiece.extension")
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
                .keyboardShortcut("u")
                .disabled(model.updates.isEmpty || model.batch != nil)
            Button("Summarize Pending Updates") { Task { await model.digestUpdates() } }
                .keyboardShortcut("u", modifiers: [.command, .option])
                .disabled(model.updates.isEmpty || !model.prefs.aiEnabled)
            Divider()
            Button("Show AddOns Folder in Finder") { model.showInFinder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }
}

struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let count = model.updates.count
        Text(count == 0 ? "All addons are up to date" : "\(count) update\(count == 1 ? "" : "s") available")
        Button("Update All") { Task { await model.updateAll() } }
            .disabled(count == 0 || model.batch != nil)
        Button("Check for Updates") { Task { await model.refresh() } }
        Divider()
        Button("Open MacMinion") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Quit MacMinion") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// The menu bar item keeps checking for updates after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the data lives: ~/Library/Application Support/MacMinion/
///   state.json        install records (what was installed, which version, ignored)
///   catalog.json      the last ESOUI file list
///   categories.json   the last ESOUI category list
///   blurbs.json       one-line addon descriptions, for suggestions
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
