import AppKit
import MacMinionKit
import SwiftUI

// One list of actions behind the Addons menu, the menu bar item, the Dock menu, and `macminion://` links
// (S-071), so a new action shows up in every place at once.

extension AppLink.Action {
    var title: String {
        switch self {
        case .checkForUpdates: String(localized: "Check for Updates")
        case .updateAll: String(localized: "Update All")
        case .backUp: String(localized: "Back Up Now")
        }
    }

    /// The same rule everywhere the action appears.
    @MainActor func isEnabled(_ model: AppModel) -> Bool {
        switch self {
        case .checkForUpdates: !model.offline
        case .updateAll: !model.updates.isEmpty && model.batch == nil
        case .backUp: model.backupBusy == nil
        }
    }

    /// Runs the action when it's enabled; otherwise does nothing, as a disabled menu item would.
    @MainActor func run(_ model: AppModel) async {
        guard isEnabled(model) else { return }
        switch self {
        case .checkForUpdates: await model.refresh()
        case .updateAll: await model.updateAll()
        case .backUp: await model.backUp()
        }
    }
}

/// A menu button for one action; the caller adds its keyboard shortcut.
struct ActionButton: View {
    let action: AppLink.Action
    let model: AppModel

    var body: some View {
        Button(action.title) { Task { await action.run(model) } }
            .disabled(!action.isEnabled(model))
    }
}

extension SidebarItem {
    /// The page's name in a `macminion://open/<page>` link.
    var linkName: String {
        switch self {
        case .findMore: "find-more"
        case .gameFolder: "game-folder"
        default: rawValue
        }
    }

    init?(linkName: String) {
        guard let page = Self.allCases.first(where: { $0.linkName == linkName }) else { return nil }
        self = page
    }
}

/// Opens a `macminion://` link: actions run in the background, pages and addons show the window.
@MainActor enum AppLinks {
    /// What a link did, for the self-test.
    enum Outcome: Equatable { case ran(AppLink.Action), opened(SidebarItem, addon: Int?), refused }

    @discardableResult
    static func open(_ url: URL, model: AppModel, showWindow: Bool = true) async -> Outcome {
        switch AppLink(url: url) {
        case .action(let action)?:
            // URL-triggered Update All must opt in with ?confirm=1; menu and Dock call Action.run directly.
            if action == .updateAll, !urlConfirmsDestructiveAction(url) { return .refused }
            await action.run(model)
            return .ran(action)
        case .open(let name)?:
            guard let page = SidebarItem(linkName: name) else { return .refused }
            model.open(page)
            if showWindow { MainWindowOpener.show() }
            return .opened(page, addon: nil)
        case .addon(let id)?:
            let page: SidebarItem = model.installed.contains { $0.id == id } ? .installed : .findMore
            model.open(page, selecting: id)
            if showWindow { MainWindowOpener.show() }
            return .opened(page, addon: id)
        case nil:
            return .refused
        }
    }

    /// True when the URL carries `confirm=1` or `confirm=true` (case-insensitive).
    static func urlConfirmsDestructiveAction(_ url: URL) -> Bool {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        return items.contains {
            $0.name.lowercased() == "confirm" && ($0.value == "1" || $0.value?.lowercased() == "true")
        }
    }
}

/// Brings the main window back from outside SwiftUI (a link, the Dock menu), even after it was closed.
@MainActor enum MainWindowOpener {
    /// Kept from the first view that appears; it opens the window scene after its window has closed.
    static var openWindow: OpenWindowAction?

    static func show() {
        if let window = NSApp.windows.first(where: \.isMainWindowScene) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: "main")
        }
        NSApp.activate()
    }
}

extension View {
    /// Keeps the scene's window opener for `MainWindowOpener`.
    func keepsWindowOpener() -> some View { modifier(KeepWindowOpener()) }
}

private struct KeepWindowOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear { MainWindowOpener.openWindow = openWindow }
    }
}

/// The Dock icon's menu: the same actions as the Addons menu and the menu bar item, so none is reachable
/// only from the menu bar.
@MainActor enum DockMenu {
    static func make(_ model: AppModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        DockMenuTarget.shared.model = model
        for action in AppLink.Action.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(DockMenuTarget.run(_:)), keyEquivalent: "")
            item.target = DockMenuTarget.shared
            item.representedObject = action.rawValue
            item.isEnabled = action.isEnabled(model)
            menu.addItem(item)
        }
        return menu
    }
}

/// Runs the Dock menu's actions: an item's represented object is its action's link name.
final class DockMenuTarget: NSObject {
    static let shared = DockMenuTarget()
    weak var model: AppModel?

    @objc func run(_ item: NSMenuItem) {
        guard let model, let name = item.representedObject as? String, let action = AppLink.Action(rawValue: name) else { return }
        Task { await action.run(model) }
    }
}
