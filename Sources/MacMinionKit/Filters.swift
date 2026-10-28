import Foundation

/// How recently an addon was updated on ESOUI.
public enum Recency: String, CaseIterable, Sendable, Identifiable {
    case any, week, month, quarter, year

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .any: "Any Time"
        case .week: "Past Week"
        case .month: "Past Month"
        case .quarter: "Past 3 Months"
        case .year: "Past Year"
        }
    }

    var days: Double? {
        switch self {
        case .any: nil
        case .week: 7
        case .month: 31
        case .quarter: 92
        case .year: 366
        }
    }
}

public enum RatingFilter: String, CaseIterable, Sendable, Identifiable {
    case any, liked, unrated, hideDisliked, disliked

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .any: "Any Rating"
        case .liked: "Thumbs Up"
        case .unrated: "Not Rated"
        case .hideDisliked: "Hide Thumbs Down"
        case .disliked: "Thumbs Down"
        }
    }

    public func matches(_ rating: Rating?) -> Bool {
        switch self {
        case .any: true
        case .liked: rating == .up
        case .unrated: rating == nil
        case .hideDisliked: rating != .down
        case .disliked: rating == .down
        }
    }
}

/// The filters on Installed and Find More. Each one left at its default lets everything through.
public struct BrowseFilter: Sendable, Equatable {
    public var category: Int?
    public var status: AddonStatus?
    public var rating: RatingFilter = .any
    public var recency: Recency = .any
    /// Only addons whose compatibility lists the current game version.
    public var compatibleOnly = false
    public var hideLibraries = false

    public init(category: Int? = nil, status: AddonStatus? = nil, rating: RatingFilter = .any, recency: Recency = .any,
                compatibleOnly: Bool = false, hideLibraries: Bool = false) {
        self.category = category; self.status = status; self.rating = rating; self.recency = recency
        self.compatibleOnly = compatibleOnly; self.hideLibraries = hideLibraries
    }

    public var isActive: Bool { self != BrowseFilter() }

    /// `categories` are the category and every category under it, already expanded.
    public func matches(_ addon: CatalogAddon, installed: InstalledAddon?, rating: Rating?, categories: Set<Int>?,
                        currentGame: String?, now: Date = .now) -> Bool {
        if let categories, !categories.contains(addon.categoryID) { return false }
        if let status, installed?.status != status { return false }
        if !self.rating.matches(rating) { return false }
        if let days = recency.days, now.timeIntervalSince(addon.date) > days * 86_400 { return false }
        if compatibleOnly, let currentGame, !addon.compatibility.contains(where: { VersionText.same($0.version, currentGame) }) { return false }
        if hideLibraries, addon.categoryID == AddonCategory.librariesID { return false }
        return true
    }
}

public enum CurrentGame {
    /// The newest game version any catalog entry says it works with: "12.1.0" sorts above "12.0.0" and "9.3.0".
    public static func current(in catalog: [CatalogAddon]) -> GameVersion? {
        var best: GameVersion?
        for addon in catalog {
            for v in addon.compatibility where best.map({ v.version.compare($0.version, options: .numeric) == .orderedDescending }) ?? true {
                best = v
            }
        }
        return best
    }
}
