import Foundation

/// A `macminion://` link, so scripts, Raycast, Stream Deck, and Shortcuts' Open URL can reach the app:
///
///     macminion://action/check-for-updates    check ESOUI for updates
///     macminion://action/update-all           install every pending update
///     macminion://action/back-up              back up the AddOns and SavedVariables folders now
///     macminion://open/<page>                 show a page: overview, installed, updates, find-more, backups, game-folder
///     macminion://addon/<ESOUI id>            show one addon
public enum AppLink: Equatable, Sendable {
    case action(Action)
    case open(page: String)
    case addon(Int)

    public static let scheme = "macminion"

    /// What a link can do without showing a window. The menus and the Dock menu run the same ones.
    public enum Action: String, CaseIterable, Sendable {
        case checkForUpdates = "check-for-updates"
        case updateAll = "update-all"
        case backUp = "back-up"
    }

    /// Sidebar pages by their link name.
    public static let pages = ["overview", "installed", "updates", "find-more", "backups", "game-folder"]

    /// Nil for another scheme, an unknown action or page, or an addon ID that isn't a number.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1 else { return nil }
        let value = parts[0].lowercased()
        switch host {
        case "action":
            guard let action = Action(rawValue: value) else { return nil }
            self = .action(action)
        case "open":
            guard Self.pages.contains(value) else { return nil }
            self = .open(page: value)
        case "addon":
            guard let id = Int(value), id > 0 else { return nil }
            self = .addon(id)
        default:
            return nil
        }
    }

    public var url: URL {
        switch self {
        case .action(let a): URL(string: "\(Self.scheme)://action/\(a.rawValue)")!
        case .open(let page): URL(string: "\(Self.scheme)://open/\(page)")!
        case .addon(let id): URL(string: "\(Self.scheme)://addon/\(id)")!
        }
    }
}
