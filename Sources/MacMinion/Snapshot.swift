import AppKit
import IOKit.pwr_mgt
import MacMinionKit
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots ~/Applications/MacMinion.app/Contents/MacOS/MacMinion
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=all,starred limits the pages. Add "settings" to include Settings.
/// Add APP_ACCENT=<id> to see the pages in another accent.
/// The main window is set to its default size, 1180 x 760, whatever size it was left at; APP_SNAPSHOT_SIZE=1600x900
/// picks another. Each page is also captured at the minimum size as <page>-min-<mode>.png. When the window does
/// not keep a size it was given (something on the Mac tiles it or puts it back), the run says so, captures at the
/// size it has, and writes no -min pictures.
enum Snapshot {
    /// Captures taken while the window was not the key window: they show dimmed controls and gray traffic lights.
    private static var inactive = 0

    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Print each line at once, so a run that hangs still shows how far it got.
        setvbuf(stdout, nil, _IOLBF, 0)
        // Snapshots never run against the real database.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            // A fixed size, so every run shows the same layout. The window can take a moment to exist.
            var mainWindow = Self.mainWindow
            for _ in 1...20 where mainWindow == nil {
                try? await Task.sleep(for: .milliseconds(250))
                mainWindow = Self.mainWindow
            }
            if mainWindow == nil { print("SNAPSHOT warning: no main window to size") }
            // The window remembers its frame, so put back the one it had before quitting.
            let frameBefore = mainWindow?.frame
            let size = requestedSize(env["APP_SNAPSHOT_SIZE"]) ?? MainWindow.standard
            let sized = await resize(mainWindow, to: size)
            if !sized, let mainWindow {
                print("SNAPSHOT warning: the window stays \(Int(mainWindow.frame.width)) x \(Int(mainWindow.frame.height)), not \(Int(size.width)) x \(Int(size.height)). Something on this Mac sets its size; pictures show that size, with none at the minimum size.")
            }
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in SidebarItem.allCases where only?.contains(page.rawValue) ?? true {
                    // Show the detail column (or inspector) too: an addon with an update where the page has one.
                    let first = switch page {
                    case .overview, .backups, .gameFolder: nil as Int?
                    case .updates, .installed: model.updates.first?.id ?? model.installed.first?.id
                    case .findMore: model.findMoreResults.first?.id
                    }
                    model.open(page, selecting: first)
                    // Dark Find More shows the filter chips.
                    if page == .findMore { model.findMoreFilter = mode == "dark" ? BrowseFilter(recency: .month, hideLibraries: true) : BrowseFilter() }
                    try? await Task.sleep(for: .seconds(1.2))
                    await capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                    // The same page at the smallest size the window allows.
                    if sized, await resize(mainWindow, to: MainWindow.minimum) {
                        await capture(to: "\(dir)/\(page.rawValue)-min-\(mode).png")
                        await resize(mainWindow, to: size)
                    }
                    // Installed filtered to one creator, from their name on a card (S-065).
                    if page == .installed {
                        model.installedFilter.author = "ziggr"
                        try? await Task.sleep(for: .seconds(1))
                        await capture(to: "\(dir)/installed-author-\(mode).png")
                        model.installedFilter.author = nil
                    }
                    // Installed as a list too, with each addon's file and problem icons (S-059).
                    if page == .installed {
                        let layout = model.prefs.installedLayout
                        model.prefs.installedLayout = layout == .grid ? .list : .grid
                        try? await Task.sleep(for: .seconds(1.2))
                        await capture(to: "\(dir)/installed-\(layout == .grid ? "list" : "grid")-\(mode).png")
                        model.prefs.installedLayout = layout
                    }
                    // Backups helping put back one damaged file, as Problems' Restore from Backup opens it.
                    if page == .backups {
                        model.focusBackups(on: "Dustman.lua")
                        try? await Task.sleep(for: .seconds(1.5))
                        await capture(to: "\(dir)/backups-restore-file-\(mode).png")
                        model.backupFocus = nil
                    }
                    // The Game Folder page: characters and addons first, then the rest.
                    if page == .gameFolder {
                        let masisi = "8796093036412335"
                        for (name, path) in [("character", [ExplorerLevel.grid, .character(masisi)]),
                                             ("character-addon", [.grid, .character(masisi), .characterAddon(id: masisi, file: "WritWorthy.lua")]),
                                             ("setting", [.grid, .addon("WritWorthy.lua"), .setting(file: "WritWorthy.lua", key: "Auto craft")]),
                                             ("compare", [.grid, .character(masisi), .compare(masisi, "8798292071293572")]),
                                             ("account", [.grid, .account("@SOLAEGIS")]),
                                             ("server", [.grid, .account("@SOLAEGIS"), .server(account: "@SOLAEGIS", server: "NA Megaserver")])] {
                            model.gameFolder.explorerPath = path
                            try? await Task.sleep(for: .seconds(1.2))
                            await capture(to: "\(dir)/gameFolder-\(name)-\(mode).png")
                        }
                        // Reading SavedVariables, part way through.
                        model.gameFolder.explorerPath = [.grid]
                        model.gameFolder.readIsCurrent = false
                        model.gameFolder.progress = ("Finding where each ID is used…", 0.45)
                        try? await Task.sleep(for: .seconds(1))
                        await capture(to: "\(dir)/gameFolder-loading-\(mode).png")
                        model.gameFolder.progress = nil
                        model.gameFolder.readIsCurrent = true
                        // One addon across every character, from an addon's name in the grid.
                        model.gameFolder.explorerPath = [.grid, .addon("WritWorthy.lua")]
                        try? await Task.sleep(for: .seconds(1.2))
                        await capture(to: "\(dir)/gameFolder-addon-\(mode).png")
                        model.gameFolder.explorerPath = [.grid]
                        // The game's settings files as forms, one setting edited (S-062).
                        model.gameFolder.gameSettingsKind = .user
                        model.gameFolder.tab = .gameSettings
                        model.gameFolder.loadGameSettings()
                        if let fps = model.gameFolder.gameSettings[.user]?.fields.first(where: { $0.key == "BACKGROUND_FPS_LIMIT" }) {
                            model.gameFolder.setGameSetting(fps, in: .user, to: "30")
                        }
                        try? await Task.sleep(for: .seconds(1))
                        await capture(to: "\(dir)/gameFolder-game-settings-\(mode).png")
                        model.gameFolder.gameSettingsDrafts = [:]
                        model.gameFolder.gameSettingsKind = .addOns
                        try? await Task.sleep(for: .seconds(1))
                        await capture(to: "\(dir)/gameFolder-game-settings-addons-\(mode).png")
                        model.gameFolder.gameSettingsKind = .user
                        // The Inspector as it first opens, before a file is chosen.
                        model.gameFolder.inspectorFile = nil
                        model.gameFolder.tab = .inspector
                        try? await Task.sleep(for: .seconds(1))
                        await capture(to: "\(dir)/gameFolder-inspector-empty-\(mode).png")
                        // The Inspector, opened on a character's table.
                        await model.gameFolder.inspect("WritWorthy.lua")
                        // Settings as you'd read them, for the whole file.
                        model.gameFolder.inspectorReadable = true
                        try? await Task.sleep(for: .seconds(1.5))
                        await capture(to: "\(dir)/gameFolder-inspector-settings-\(mode).png")
                        // Names from the addon's source: its settings panel, and a table keyed by game constants.
                        // A sample answer from AI, as a guess beside the panel's names.
                        model.gameFolder.applyAINames(["goldBudget": "Gold budget in thousands"], file: "WritWorthy.lua", folder: "WritWorthy",
                                           version: Manifest.read(folder: model.addonsFolder.appending(path: "WritWorthy"))?.version ?? "", parent: "$AccountWide")
                        model.gameFolder.inspectorFocus = [.string("WritWorthy_SavedVars"), .string("NA Megaserver"), .string("@SOLAEGIS"), .string("$AccountWide")]
                        try? await Task.sleep(for: .seconds(1.2))
                        await capture(to: "\(dir)/gameFolder-inspector-source-\(mode).png")
                        model.gameFolder.inspectorFocus.append(.string("byType"))
                        try? await Task.sleep(for: .seconds(1.2))
                        await capture(to: "\(dir)/gameFolder-inspector-constants-\(mode).png")
                        model.gameFolder.inspectorFocus = []
                        model.gameFolder.inspectorReadable = false
                        model.gameFolder.inspectorFocus = [.string("WritWorthy_SavedVars"), .string("NA Megaserver"), .string("@SOLAEGIS")]
                        try? await Task.sleep(for: .seconds(1))
                        await capture(to: "\(dir)/gameFolder-inspector-\(mode).png")
                        model.gameFolder.inspectorFocus.append(.string("8796093036412335"))
                        try? await Task.sleep(for: .seconds(1))
                        await capture(to: "\(dir)/gameFolder-inspector-character-\(mode).png")
                        // Find: every place Masisi appears.
                        model.gameFolder.inspectorQuery = "Masisi"
                        await model.gameFolder.find("Masisi")
                        try? await Task.sleep(for: .seconds(1))
                        await capture(to: "\(dir)/gameFolder-inspector-find-\(mode).png")
                        model.gameFolder.clearFind()
                        await model.gameFolder.showConnections(SVTarget(.character, "8796093036412335"))
                        try? await Task.sleep(for: .seconds(1.2))
                        await capture(to: "\(dir)/gameFolder-inspector-connections-\(mode).png")
                        model.gameFolder.closeConnections()
                        model.gameFolder.inspectorReadable = true
                        model.gameFolder.tab = .problems
                        try? await Task.sleep(for: .seconds(1))
                        await capture(to: "\(dir)/gameFolder-problems-\(mode).png")
                        // The same page with More open and the first card's raw checks showing.
                        model.gameFolder.problemsMoreExpanded = true
                        if let first = model.gameFolder.healthFindings.first(where: \.isMain) { model.gameFolder.problemsExpanded = [first.id] }
                        try? await Task.sleep(for: .seconds(1))
                        await capture(to: "\(dir)/gameFolder-problems-expanded-\(mode).png")
                        model.gameFolder.problemsMoreExpanded = false
                        model.gameFolder.problemsExpanded = []
                        // From an installed addon's icons (S-059): Problems and the Inspector narrowed to one addon.
                        if let dustman = model.installed.first(where: { $0.catalog.name == "Dustman" }) {
                            model.gameFolder.showProblems(of: dustman.catalog.name, dirs: dustman.record.dirs)
                            try? await Task.sleep(for: .seconds(1))
                            await capture(to: "\(dir)/gameFolder-problems-addon-\(mode).png")
                            model.gameFolder.problemsAddonFilter = nil
                        }
                        if let harvest = model.installed.first(where: { $0.catalog.name.hasPrefix("HarvestMap") }) {
                            model.gameFolder.showFiles(of: harvest.catalog.name, dirs: harvest.record.dirs)
                            try? await Task.sleep(for: .seconds(1.5))
                            await capture(to: "\(dir)/gameFolder-inspector-addon-\(mode).png")
                            model.gameFolder.inspectorAddonFilter = nil
                        }
                        model.gameFolder.tab = .characters
                        model.gameFolder.explorerPath = [.grid]
                    }
                    // The Customize Overview sheet, over the Overview.
                    if page == .overview {
                        model.customizingOverview = true
                        try? await Task.sleep(for: .seconds(1))
                        let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                        await capture(to: "\(dir)/customize-\(mode).png", window: main?.attachedSheet)
                        model.customizingOverview = false
                        try? await Task.sleep(for: .seconds(0.5))
                    }
                }
            }
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        // The menu bar item has a window too; Settings is the titled one.
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet && $0.styleMask.contains(.titled) }
                        await capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                        // The OpenAI section, standing for both keyed providers.
                        if tab == .ai {
                            let provider = model.prefs.aiProvider
                            model.prefs.aiProvider = .openai
                            try? await Task.sleep(for: .seconds(0.8))
                            await capture(to: "\(dir)/settings-ai-openai-\(mode).png", window: settings)
                            model.prefs.aiProvider = provider
                        }
                    }
                }
            }
            if let mainWindow, let frameBefore { mainWindow.setFrame(frameBefore, display: false) }
            if inactive > 0 {
                print("SNAPSHOT warning: \(inactive) captures show an inactive window. Another app kept the focus; leave the Mac alone and run again.")
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    private static func capture(to path: String, window: NSWindow? = nil) async {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Becoming active takes a moment, and macOS can refuse it while someone is using another app.
        for _ in 1...20 where !(NSApp.isActive && window.isKeyWindow) {
            try? await Task.sleep(for: .milliseconds(100))
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
        if NSApp.isActive && window.isKeyWindow {
            // Let the window redraw as the key window.
            try? await Task.sleep(for: .milliseconds(150))
        } else {
            inactive += 1
        }
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            try? await Task.sleep(for: .seconds(0.5))
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.canBecomeMain && !$0.isSheet && $0.identifier?.rawValue.contains("main") == true }
            ?? NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
    }

    /// "1600x900" as a size, or nil.
    private static func requestedSize(_ text: String?) -> CGSize? {
        guard let parts = text?.lowercased().split(separator: "x").map({ Double($0) }), parts.count == 2,
              let width = parts[0], let height = parts[1], width >= MainWindow.minimum.width, height >= MainWindow.minimum.height else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Sets the window's size and keeps it on screen. False when the window did not keep that size.
    @discardableResult
    private static func resize(_ window: NSWindow?, to size: CGSize) async -> Bool {
        guard let window else { return false }
        window.setContentSize(size)
        window.center()
        try? await Task.sleep(for: .seconds(0.8))
        // At the minimum the window keeps room for the toolbar, so it can end up a little taller than asked.
        let now = window.contentView?.bounds.size ?? .zero
        return abs(now.width - size.width) < 1 && now.height >= size.height && now.height <= size.height + 100
    }
}
