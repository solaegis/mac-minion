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
            check("search matches authors, ignoring case", Set(model.findMoreResults.map(\.id)) == [7, 695])
            model.search = ""
            model.category = 23
            check("a category includes its children", model.findMoreResults.count == 8, "\(model.findMoreResults.count)")
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
