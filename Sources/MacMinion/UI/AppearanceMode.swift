import AppKit
import SwiftUI

/// Light, dark, or the Mac's own mode. Settings > Appearance, the button next
/// to the sidebar's Settings gear, and MacMinion > Appearance all set it.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbolName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// Control-Command-1, 2, 3 in the app menu.
    var shortcut: KeyEquivalent {
        switch self {
        case .system: "1"
        case .light: "2"
        case .dark: "3"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// The one place that saves and applies the mode. Views read the same key
/// with `@AppStorage(AppearanceController.key)` and write through `binding`.
///
/// The mode is set on `NSApp.appearance`, not with `.preferredColorScheme`:
/// on macOS, `.preferredColorScheme(nil)` doesn't reliably hand a window back
/// to the system mode once it was forced light or dark, and it misses menus,
/// sheets, and the Settings window. `NSApp.appearance = nil` follows the Mac
/// live, everywhere.
enum AppearanceController {
    static let key = "appearancePreference"

    static var saved: AppearancePreference {
        UserDefaults.standard.string(forKey: key).flatMap(AppearancePreference.init) ?? .system
    }

    static func apply(_ preference: AppearancePreference) {
        // Snapshot mode forces light, then dark, on its own.
        guard ProcessInfo.processInfo.environment["APP_SNAPSHOT"] == nil else { return }
        NSApp.appearance = preference.nsAppearance
    }

    /// At launch, and when Settings opens.
    static func applySaved() { apply(saved) }

    /// Saves the new value and applies it at once.
    static func binding(_ stored: Binding<AppearancePreference>) -> Binding<AppearancePreference> {
        Binding(get: { stored.wrappedValue },
                set: { stored.wrappedValue = $0; apply($0) })
    }
}

/// The icon button beside the Settings gear: its symbol shows the current mode.
struct AppearanceMenu: View {
    @AppStorage(AppearanceController.key) private var preference = AppearancePreference.system

    var body: some View {
        Menu {
            Picker("Appearance", selection: AppearanceController.binding($preference)) {
                ForEach(AppearancePreference.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("Appearance", systemImage: preference.symbolName)
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Appearance: \(preference.title)")
    }
}

/// MacMinion > Appearance, next to Settings…. Toggles rather than a Picker so
/// each mode can carry its own shortcut; they show the same checkmark.
struct AppearanceCommands: View {
    @AppStorage(AppearanceController.key) private var preference = AppearancePreference.system

    var body: some View {
        let selection = AppearanceController.binding($preference)
        Menu("Appearance") {
            ForEach(AppearancePreference.allCases) { mode in
                Toggle(isOn: Binding(get: { selection.wrappedValue == mode },
                                     set: { if $0 { selection.wrappedValue = mode } })) {
                    Label(mode.title, systemImage: mode.symbolName)
                }
                .keyboardShortcut(mode.shortcut, modifiers: [.control, .command])
            }
        }
    }
}
