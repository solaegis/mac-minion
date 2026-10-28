import AppKit
import Combine
import Sparkle
import SwiftUI

/// MacMinion's own updates, through Sparkle 2. The feed (SUFeedURL) and the public EdDSA key
/// (SUPublicEDKey) are in Info.plist; an update installs only when its EdDSA signature checks out.
/// Not started in test or snapshot runs, or when the binary runs outside its .app.
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    let controller: SPUStandardUpdaterController
    @Published private(set) var canCheckForUpdates = false

    /// False in test and snapshot runs (APP_STORE in /tmp) and without a feed URL (swift run).
    static var enabled: Bool {
        !Store.isOverridden && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
    }

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: Self.enabled, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    var updater: SPUUpdater { controller.updater }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    /// "0.5 (42)".
    static var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }
}

/// "Check for MacMinion Updates…" in the app menu. Named apart from the addon "Check for Updates" (Command-R).
struct CheckForAppUpdatesButton: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Button("Check for MacMinion Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}

/// Settings > Updates: MacMinion's own version and update settings, next to the addon ones.
struct AppUpdateSettings: View {
    @ObservedObject private var app = AppUpdater.shared
    @State private var automaticChecks = AppUpdater.shared.updater.automaticallyChecksForUpdates
    @State private var automaticDownloads = AppUpdater.shared.updater.automaticallyDownloadsUpdates

    var body: some View {
        Section {
            LabeledContent("Version", value: AppUpdater.versionString)
            // Set the updater only when the person changes a toggle (Sparkle's preferences guide).
            Toggle("Check for MacMinion updates automatically", isOn: $automaticChecks)
                .onChange(of: automaticChecks) { app.updater.automaticallyChecksForUpdates = automaticChecks }
            Toggle("Download and install them automatically", isOn: $automaticDownloads)
                .disabled(!automaticChecks)
                .onChange(of: automaticDownloads) { app.updater.automaticallyDownloadsUpdates = automaticDownloads }
            HStack {
                Button("Check Now") { app.checkForUpdates() }
                    .disabled(!app.canCheckForUpdates)
                Spacer()
                Link("Release Notes", destination: Docs.releases)
            }
        } header: {
            Text("MacMinion")
        } footer: {
            Text("Updates come from GitHub and install only when their signature matches the key built into MacMinion.")
                .foregroundStyle(.secondary)
        }
    }
}

/// The documentation site (GitHub Pages) and where each part of the app is explained.
enum Docs {
    static let base = URL(string: "https://solaegis.github.io/mac-minion/")!
    static let releases = URL(string: "https://github.com/solaegis/mac-minion/releases")!
    static let issues = URL(string: "https://github.com/solaegis/mac-minion/issues")!

    static func page(_ name: String, _ anchor: String? = nil) -> URL {
        var url = base.appending(path: name)
        if let anchor { url = URL(string: url.absoluteString + "#" + anchor) ?? url }
        return url
    }

    static var home: URL { base }
    static var cli: URL { page("cli.html") }

    static func page(for sidebar: SidebarItem?) -> URL {
        switch sidebar ?? .overview {
        case .overview: page("overview.html")
        case .installed, .findMore: page("browsing.html")
        case .updates: page("updates.html")
        case .backups: page("backups.html")
        }
    }

    static func page(for tab: SettingsTab) -> URL {
        switch tab {
        case .ai: page("ai.html")
        case .backups: page("backups.html")
        default: page("settings.html", tab.rawValue)
        }
    }

    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// The Help menu: the docs, the page for what's on screen, the CLI reference, releases, and issues.
struct HelpCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("MacMinion Help") { Docs.open(Docs.home) }
                .keyboardShortcut("?", modifiers: .command)
            Button("Help for This Page") { Docs.open(Docs.page(for: model.sidebar)) }
            Button("Command-Line Reference") { Docs.open(Docs.cli) }
            Divider()
            Button("Release Notes") { Docs.open(Docs.releases) }
            Button("Report an Issue") { Docs.open(Docs.issues) }
        }
    }
}
