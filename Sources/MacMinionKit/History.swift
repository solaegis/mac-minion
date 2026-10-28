import Foundation

/// One install, update, or removal, from MacMinion or imported from Minion.
public struct HistoryEvent: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case install, update, remove }

    public var id = UUID()
    public var date: Date
    public var addonID: Int?
    public var name: String
    public var version: String?
    public var previousVersion: String?
    public var kind: Kind
    public var fromMinion = false

    public init(date: Date, addonID: Int?, name: String, version: String?, previousVersion: String? = nil,
                kind: Kind, fromMinion: Bool = false) {
        self.date = date; self.addonID = addonID; self.name = name; self.version = version
        self.previousVersion = previousVersion; self.kind = kind; self.fromMinion = fromMinion
    }
}

/// Numbers for the Overview page.
public enum Usage {
    public struct WeekCount: Sendable, Hashable, Identifiable {
        public var id: Date { start }
        public let start: Date
        public let count: Int
    }

    public struct NameCount: Sendable, Hashable, Identifiable {
        public var id: String { name }
        public let name: String
        public let count: Int

        public init(name: String, count: Int) {
            self.name = name
            self.count = count
        }
    }

    /// Installs and updates per week, oldest first, ending with the current week. Weeks with none count 0.
    public static func weekly(_ events: [HistoryEvent], weeks: Int, now: Date = .now, calendar: Calendar = .current) -> [WeekCount] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let starts = (0..<weeks).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
        var counts: [Date: Int] = [:]
        for e in events where e.kind != .remove {
            if let start = calendar.dateInterval(of: .weekOfYear, for: e.date)?.start { counts[start, default: 0] += 1 }
        }
        return starts.map { WeekCount(start: $0, count: counts[$0] ?? 0) }
    }

    /// The addons updated most often, most first.
    public static func mostUpdated(_ events: [HistoryEvent], limit: Int) -> [NameCount] {
        var counts: [String: Int] = [:]
        for e in events where e.kind == .update { counts[e.name, default: 0] += 1 }
        return counts.map { NameCount(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            .prefix(limit).map { $0 }
    }

    /// ESOUI names carry long tags in parentheses: "pChat (Chat customization & help…)" -> "pChat".
    public static func shortName(_ name: String) -> String {
        let cut = name.firstIndex(of: "(").map { name[..<$0] } ?? name[...]
        let trimmed = cut.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : trimmed
    }

    /// Bytes on disk under a folder.
    public static func size(of folder: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
