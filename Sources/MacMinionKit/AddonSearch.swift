import Foundation

/// AI search over the catalog: the model turns a request into keywords and categories, the catalog is
/// filtered by them, and the model picks the best matches from that short list with a reason each.
public enum AddonSearch {
    public static let maxResults = 8
    public static let candidateCount = 60

    public static func keywordPrompt(_ query: String, categories: [AddonCategory]) -> String {
        let list = categories.sorted { $0.title < $1.title }.map { "\($0.id): \($0.title)" }.joined(separator: "\n")
        return """
        A player wants Elder Scrolls Online addons for this: "\(query)"
        Give search words that would appear in the names or descriptions of matching addons on ESOUI, and the \
        categories they would be in. Answer in exactly two lines and nothing else:
        keywords: <8 to 12 single words or short phrases, comma-separated>
        categories: <up to 3 category ids from the list, comma-separated>

        Categories:
        \(list)
        """
    }

    public struct Plan: Sendable, Equatable {
        public var keywords: [String]
        public var categories: [Int]
    }

    public static func parsePlan(_ answer: String, query: String) -> Plan {
        var plan = Plan(keywords: [], categories: [])
        for line in answer.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " *-"))
            let values = parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'.*"))) }
            if key.hasPrefix("keyword") { plan.keywords = values.filter { !$0.isEmpty }.map { $0.lowercased() } }
            if key.hasPrefix("categor") { plan.categories = values.compactMap { Int($0.filter(\.isNumber)) } }
        }
        // The request's own words always count.
        let own = query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 3 && !stopWords.contains($0) }
        plan.keywords = Array(NSOrderedSet(array: plan.keywords + own)) as? [String] ?? plan.keywords + own
        return plan
    }

    static let stopWords: Set<String> = ["addon", "addons", "something", "that", "with", "want", "need", "help", "make", "better",
                                         "which", "would", "could", "there", "this", "from", "into", "when", "what", "like", "shows"]

    /// Catalog entries that match the plan, best first: name hits count most, then descriptions, then category.
    public static func candidates(catalog: [CatalogAddon], plan: Plan, blurbs: [Int: String], excluded: Set<Int>,
                                  limit: Int = candidateCount) -> [CatalogAddon] {
        let categories = Set(plan.categories)
        let scored: [(CatalogAddon, Double)] = catalog.compactMap { addon in
            guard !excluded.contains(addon.id) else { return nil }
            let name = addon.name.lowercased()
            let blurb = blurbs[addon.id]?.lowercased() ?? ""
            var score = 0.0
            for word in plan.keywords where !word.isEmpty {
                if name.contains(word) { score += 3 }
                if blurb.contains(word) { score += 1 }
            }
            if categories.contains(addon.categoryID) { score += 1.5 }
            guard score > 0 else { return nil }
            return (addon, score + log10(Double(max(addon.downloadsMonthly, 1))) * 0.3)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    public static func pickPrompt(_ query: String, candidates: [AddonRecommender.Entry], installed: Set<Int>, taste: Taste) -> String {
        let list = candidates.map { c in
            "\(c.id): \(c.name) [\(c.category)\(installed.contains(c.id) ? ", installed" : ""), \(c.monthly) downloads this month]"
                + (c.blurb.isEmpty ? "" : " \(c.blurb)")
        }.joined(separator: "\n")
        return """
        A player wants Elder Scrolls Online addons for this: "\(query)"
        \(taste.promptLines)
        From the candidates below, pick up to \(maxResults) that best do what the player asked, best first. \
        Only pick addons that really fit the request. Prefer well-known, maintained addons.
        Answer with one line per pick and nothing else, in exactly this form:
        <id> | <one sentence on how it does what the player asked>

        Candidates:
        \(list)
        """
    }
}
