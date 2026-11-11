import Foundation

/// Where the main window was at quit: the page, the selected addon or folder, and the Game Folder tab. The
/// next launch opens there. UI state only, never data. Test and snapshot runs neither read nor write it.
struct WindowState: Equatable {
    var page: SidebarItem = .overview
    var selection: Selection?
    var gameFolderTab: GameFolderTab = .characters

    /// The state this launch starts from.
    static let saved = Store.isOverridden ? WindowState() : load(from: .standard)
    /// Where changes are written, or nil in test and snapshot runs.
    static var store: UserDefaults? { Store.isOverridden ? nil : .standard }

    static func load(from defaults: UserDefaults) -> WindowState {
        WindowState(page: defaults.string(forKey: Key.page).flatMap(SidebarItem.init) ?? .overview,
                    selection: defaults.string(forKey: Key.selection).flatMap(Selection.init(saved:)),
                    gameFolderTab: defaults.string(forKey: Key.gameFolderTab).flatMap(GameFolderTab.init) ?? .characters)
    }

    static func save(page: SidebarItem?, to defaults: UserDefaults?) {
        defaults?.set(page?.rawValue, forKey: Key.page)
    }

    static func save(selection: Selection?, to defaults: UserDefaults?) {
        defaults?.set(selection?.saved, forKey: Key.selection)
    }

    static func save(gameFolderTab: GameFolderTab, to defaults: UserDefaults?) {
        defaults?.set(gameFolderTab.rawValue, forKey: Key.gameFolderTab)
    }

    private enum Key {
        static let page = "window.page"
        static let selection = "window.selection"
        static let gameFolderTab = "window.gameFolderTab"
    }
}

extension Selection {
    /// "addon:123" or "folder:Name", for UserDefaults.
    var saved: String {
        switch self {
        case .addon(let id): "addon:\(id)"
        case .folder(let name): "folder:\(name)"
        }
    }

    init?(saved: String) {
        let parts = saved.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        switch parts[0] {
        case "addon": if let id = Int(parts[1]) { self = .addon(id) } else { return nil }
        case "folder": self = .folder(parts[1])
        default: return nil
        }
    }
}
