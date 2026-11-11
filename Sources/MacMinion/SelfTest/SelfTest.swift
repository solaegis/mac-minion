import AppKit
import MacMinionKit

/// Self-test for agents: runs the app's real functions on the seeded /tmp store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/MacMinion-self ~/Applications/MacMinion.app/Contents/MacOS/MacMinion --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic, in its area's file in SelfTest/.
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
        // The checks run on a /tmp store, so ESO being open for real doesn't block them.
        model.simulatesRunningGame = false
        Task {
            // Every area in this order: later ones use what earlier ones left on disk and in the model.
            await installs(model)
            await ai(model)
            await suggestions(model)
            await libraries(model)
            await browse(model)
            await backups(model)
            await gameFolderScan(model)
            await inspector(model)
            await problems(model)
            await space(model)
            await agentSV(model)
            await readable(model)
            await characterCards(model)
            await connections(model)
            await characters(model)
            await creators(model)
            await gameSettings(model)
            await accountsAndServers(model)
            await bigTable(model)
            await tidy(model)
            await app(model)
            await appearance(model)
            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
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
