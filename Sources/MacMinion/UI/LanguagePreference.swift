import AppKit
import SwiftUI

/// App UI language: follow the Mac, or force one of the shipped locales.
/// Changing the override writes `AppleLanguages` and needs a relaunch to apply.
enum LanguagePreference: String, CaseIterable, Identifiable {
    case system
    case en
    case de
    case fr
    case es
    case ru

    var id: String { rawValue }

    /// Native name for the picker (not translated through the catalog).
    var displayName: String {
        switch self {
        case .system: String(localized: "Match System")
        case .en: "English"
        case .de: "Deutsch"
        case .fr: "Français"
        case .es: "Español"
        case .ru: "Русский"
        }
    }

    /// BCP-47 code written to `AppleLanguages`, or nil for system.
    var appleLanguageCode: String? {
        switch self {
        case .system: nil
        case .en: "en"
        case .de: "de"
        case .fr: "fr"
        case .es: "es"
        case .ru: "ru"
        }
    }
}

/// Saves the language preference and applies `AppleLanguages` at launch.
enum LanguageController {
    static let key = "languagePreference"
    private static let appleLanguagesKey = "AppleLanguages"

    static var saved: LanguagePreference {
        UserDefaults.standard.string(forKey: key).flatMap(LanguagePreference.init) ?? .system
    }

    /// At launch, before the first window draws localized strings.
    /// `APP_LANGUAGE=<code>` (de, fr, es, ru, en) forces a locale for snapshots and tests.
    static func applySaved() {
        if let code = ProcessInfo.processInfo.environment["APP_LANGUAGE"],
           let forced = LanguagePreference(rawValue: code), forced != .system {
            apply(forced)
            return
        }
        apply(saved)
    }

    static func apply(_ preference: LanguagePreference) {
        let defaults = UserDefaults.standard
        if let code = preference.appleLanguageCode {
            defaults.set([code], forKey: appleLanguagesKey)
            return
        }
        // Clearing must drop the app-domain override only. `object(forKey:)`
        // still sees the global Language & Region list afterward — that is correct.
        defaults.removeObject(forKey: appleLanguagesKey)
        if let id = Bundle.main.bundleIdentifier,
           var domain = defaults.persistentDomain(forName: id) {
            domain.removeValue(forKey: appleLanguagesKey)
            defaults.setPersistentDomain(domain, forName: id)
        }
    }

    /// True when this app has forced a language (not merely inheriting the Mac's).
    static var hasAppLanguageOverride: Bool {
        guard let id = Bundle.main.bundleIdentifier,
              let domain = UserDefaults.standard.persistentDomain(forName: id) else { return false }
        return domain[appleLanguagesKey] != nil
    }

    /// Saves the value; caller shows the relaunch prompt when it changed.
    static func binding(_ stored: Binding<LanguagePreference>) -> Binding<LanguagePreference> {
        Binding(
            get: { stored.wrappedValue },
            set: { newValue in
                stored.wrappedValue = newValue
                apply(newValue)
            }
        )
    }

    /// Relaunch this .app so Bundle localization picks up `AppleLanguages`.
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
