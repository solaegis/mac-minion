import AppKit
import MacMinionKit

extension SelfTest {
    /// Removing a folder not on ESOUI, Sparkle, the agent socket, and the companion (S-027, S-028, S-042, S-047).
    static func app(_ model: AppModel) async {
        // S-027 Remove from a tile, including folders not on ESOUI
        if let folder = model.unmatched.first {
            await model.removeFolder(folder)
            check("a folder not on ESOUI can be removed", !model.unmatched.contains(folder)
                  && !FileManager.default.fileExists(atPath: model.addonsFolder.appending(path: folder.folder).path))
        }

        // Relaunch opens where you left off: the page, the selection, and the Game Folder tab.
        let suite = "macminion.selftest.window"
        if let defaults = UserDefaults(suiteName: suite) {
            defaults.removePersistentDomain(forName: suite)
            check("a first launch opens Overview with nothing selected", WindowState.load(from: defaults) == WindowState())
            WindowState.save(page: .gameFolder, to: defaults)
            WindowState.save(selection: .folder("Name: with a colon"), to: defaults)
            WindowState.save(gameFolderTab: .problems, to: defaults)
            check("the page, selection, and Game Folder tab come back",
                  WindowState.load(from: defaults) == WindowState(page: .gameFolder, selection: .folder("Name: with a colon"), gameFolderTab: .problems))
            WindowState.save(selection: .addon(7), to: defaults)
            check("a selected addon comes back", WindowState.load(from: defaults).selection == .addon(7))
            WindowState.save(selection: nil, to: defaults)
            defaults.set("gone", forKey: "window.page")
            check("a page this version doesn't have opens Overview", WindowState.load(from: defaults) == WindowState(gameFolderTab: .problems))
            check("a damaged selection is dropped", Selection(saved: "addon:x") == nil && Selection(saved: "folder:") == nil && Selection(saved: "") == nil)
            defaults.removePersistentDomain(forName: suite)
        }
        check("test runs don't read or write the real window state", WindowState.store == nil && WindowState.saved == WindowState())

        // S-028 App updates: Sparkle is configured but never starts in test runs.
        check("Sparkle has a feed URL and public key", Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
              == "https://solaegis.github.io/mac-minion/appcast.xml"
              && (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?.count == 44)
        check("Sparkle doesn't run in test runs", !AppUpdater.enabled)

        // The agent socket: a CLI that hangs up early must not quit the app.
        var pair: [Int32] = [-1, -1]
        if socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 {
            check("the agent socket accepts this Mac user", AgentSocket.isSameUser(pair[0]))
            AgentSocket.prepare(pair[0])
            close(pair[1])
            let sent = Darwin.write(pair[0], "reply\n", 6)
            let failure = errno
            close(pair[0])
            check("a reply to a CLI that hung up fails quietly", sent == -1 && failure == EPIPE, "\(sent) \(failure)")
        }

        // S-042 / S-047 Companion: recommend when missing, install from the bundled copy.
        if model.companionInstalled {
            try? FileManager.default.removeItem(at: model.addonsFolder.appending(path: CompanionData.folderName))
            await model.rescan()
            check("the companion is recommended when it is not installed", model.needsCompanion && !model.companionInstalled)
            await model.installCompanion()
            check("Install copies the companion into AddOns", model.companionInstalled && model.companionError == nil
                  && FileManager.default.fileExists(atPath: model.addonsFolder.appending(path: "\(CompanionData.folderName)/\(CompanionData.folderName).txt").path),
                  model.companionError ?? "")
            check("the companion leaves the recommended list once installed", !model.needsCompanion)
        }
    }

    /// Layout, accent, appearance, language, and translated text (S-015).
    static func appearance(_ model: AppModel) async {
        // S-015 Layout
        check("Installed and Find More open as grids", model.prefs.installedLayout == .grid && model.prefs.findMoreLayout == .grid)
        model.sidebar = .installed
        model.setLayout(.list)
        check("the layout switch changes the page on screen", model.prefs.installedLayout == .list && model.prefs.findMoreLayout == .grid)
        model.setLayout(.grid)
        check("Find More features four results above a grid of equal cards", FindMoreGrid.featuredCount == 4)
        check("the accent is Minion Blue by default", ThemeStore.defaultID == "minion"
              && Theme.all.first { $0.id == "minion" }?.shades?.base == 0x007AFF)
        check("appearance maps System to the Mac's mode, Light to Aqua, Dark to Dark Aqua",
              AppearancePreference.system.nsAppearance == nil
              && AppearancePreference.light.nsAppearance?.name == .aqua
              && AppearancePreference.dark.nsAppearance?.name == .darkAqua
              && AppearancePreference(rawValue: "bogus") == nil)
        let previousLanguage = LanguageController.saved
        let previousAppleLanguages = UserDefaults.standard.array(forKey: "AppleLanguages")
        defer {
            if let previousAppleLanguages {
                UserDefaults.standard.set(previousAppleLanguages, forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
            UserDefaults.standard.set(previousLanguage.rawValue, forKey: LanguageController.key)
        }
        LanguageController.apply(.de)
        check("German language override writes AppleLanguages",
              LanguageController.hasAppLanguageOverride
              && (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first == "de")
        LanguageController.apply(.system)
        check("system language clears AppleLanguages override",
              !LanguageController.hasAppLanguageOverride)
        check("language preference parses shipped locales",
              LanguagePreference(rawValue: "fr") == .fr
              && LanguagePreference(rawValue: "bogus") == nil
              && LanguagePreference.system.appleLanguageCode == nil
              && LanguagePreference.de.appleLanguageCode == "de")

        // Game Folder text reads from the catalog, plural forms included.
        func translated(_ key: String, _ language: String) -> String? {
            guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
            return bundle.localizedString(forKey: key, value: nil, table: nil)
        }
        check("Problems buttons are translated", translated("Show Backups", "de") == "Backups anzeigen",
              translated("Show Backups", "de") ?? "no de.lproj")
        let russianErrors = translated("%lld errors", "ru").map { String(format: $0, locale: Locale(identifier: "ru"), 5) }
        check("Problems counts use Russian plural forms", russianErrors == "5 ошибок", russianErrors ?? "no ru.lproj")
    }
}
