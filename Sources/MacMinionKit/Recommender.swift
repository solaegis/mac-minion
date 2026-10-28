import Foundation

/// One addon the assistant suggests, and why.
public struct AddonSuggestion: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let reason: String

    public init(id: Int, reason: String) {
        self.id = id
        self.reason = reason
    }
}

/// Suggestions from installed addons: picks candidates from the catalog, asks the AI which would add
/// something, and keeps only answers that name a real candidate.
public enum AddonRecommender {
    /// How many catalog entries the AI chooses from. Enough variety, small enough for a local model.
    public static let candidateCount = 60
    public static let maxSuggestions = 6

    /// Popular addons that aren't installed and aren't libraries, weighted toward the categories the
    /// player already uses most.
    public static func candidates(catalog: [CatalogAddon], installed: Set<Int>, limit: Int = candidateCount) -> [CatalogAddon] {
        let open = catalog.filter { !installed.contains($0.id) && $0.categoryID != AddonCategory.librariesID }
        var counts: [Int: Int] = [:]
        for addon in catalog where installed.contains(addon.id) { counts[addon.categoryID, default: 0] += 1 }
        let favorite = counts.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        var picked: [CatalogAddon] = []
        var seen = Set<Int>()
        func take(_ list: some Sequence<CatalogAddon>, _ n: Int) {
            for addon in list.prefix(n) where seen.insert(addon.id).inserted { picked.append(addon) }
        }
        let popular = open.sorted { $0.downloadsMonthly > $1.downloadsMonthly }
        for category in favorite { take(popular.filter { $0.categoryID == category }, limit / 6) }
        take(popular.filter { !seen.contains($0.id) }, limit - picked.count)
        return Array(picked.prefix(limit))
    }

    public static func prompt(installed: [String], candidates: [CatalogAddon], categories: [AddonCategory]) -> String {
        let names = Dictionary(categories.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        let list = candidates.map { c in
            "\(c.id): \(c.name) by \(c.author) (\(names[c.categoryID] ?? "Other"), \(c.downloadsMonthly) downloads this month)"
        }.joined(separator: "\n")
        return """
        The player has these Elder Scrolls Online addons installed:
        \(installed.joined(separator: ", "))

        From the candidates below, pick up to \(maxSuggestions) that would add something valuable the player doesn't \
        already have. Skip any candidate that does the same job as an installed addon. Prefer well-known, maintained addons.
        Answer with one line per pick and nothing else, in exactly this form:
        <id> | <one sentence on what it adds, naming an installed addon it works with when there is one>

        Candidates:
        \(list)
        """
    }

    /// Lines like "1360 | Adds price history to the guild store." Unknown ids and repeats are dropped.
    public static func parse(_ answer: String, candidates: Set<Int>) -> [AddonSuggestion] {
        var out: [AddonSuggestion] = []
        var seen = Set<Int>()
        for raw in answer.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "•*-` "))
            guard let match = line.firstMatch(of: /^\[?(\d+)\]?\s*[|:–—-]\s*(.+)$/),
                  let id = Int(match.1), candidates.contains(id), seen.insert(id).inserted else { continue }
            out.append(AddonSuggestion(id: id, reason: String(match.2).trimmingCharacters(in: .whitespaces)))
            if out.count == maxSuggestions { break }
        }
        return out
    }
}
