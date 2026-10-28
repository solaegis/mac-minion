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
    /// `folders` are the folders on disk: an entry that installs into one of them is a fork or variant of
    /// something the player has, so it's left out too.
    public static func candidates(catalog: [CatalogAddon], installed: Set<Int>, folders: Set<String> = [],
                                  limit: Int = candidateCount) -> [CatalogAddon] {
        let open = catalog.filter {
            !installed.contains($0.id) && $0.categoryID != AddonCategory.librariesID && folders.isDisjoint(with: $0.dirs)
        }
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

    /// One addon as the model sees it: what it is and what it does.
    public struct Entry: Sendable, Equatable {
        public let id: Int
        public let name: String
        public let category: String
        public let blurb: String
        public let monthly: Int

        public init(id: Int, name: String, category: String, blurb: String, monthly: Int = 0) {
            self.id = id; self.name = name; self.category = category; self.blurb = blurb; self.monthly = monthly
        }
    }

    /// The installed addons grouped by category with what each does, then the candidates the same way.
    /// Knowing the job of each addon lets the model skip candidates that duplicate one the player has.
    public static func prompt(installed: [Entry], candidates: [Entry], taste: Taste = Taste()) -> String {
        let groups = Dictionary(grouping: installed, by: \.category).sorted { $0.key < $1.key }
        let have = groups.map { category, entries in
            "\(category):\n" + entries.map { "- \($0.name)\($0.blurb.isEmpty ? "" : ": \($0.blurb)")" }.joined(separator: "\n")
        }.joined(separator: "\n")
        let list = candidates.map { c in
            "\(c.id): \(c.name) [\(c.category), \(c.monthly) downloads this month]\(c.blurb.isEmpty ? "" : " \(c.blurb)")"
        }.joined(separator: "\n")
        return """
        The player has these Elder Scrolls Online addons installed, by category, with what each does:
        \(have)

        \(taste.promptLines)
        From the candidates below, pick up to \(maxSuggestions) that would add something valuable the player doesn't already have.
        Work out the job each candidate does first. Skip a candidate when an installed addon already does that job \
        (for example a second gear or build manager, a second combat meter, a second map-pin pack for the same thing), \
        and never pick two candidates that do the same job. Prefer well-known, maintained addons.
        Answer with one line per pick and nothing else, in exactly this form:
        <id> | <one sentence on what it adds, naming an installed addon it works with when there is one>

        Candidates:
        \(list)
        """
    }

    /// Lines that say nothing about what an addon does: notes, thanks, translation and donation asks.
    static let noise = #"(?i)^(note|notes|important|attention|warning|update|updated|please|thanks|thank you|credits|donat|changelog|version|required|requires|dependenc|librar|translation|known issues|faq|installation|install)\b|locali[sz]ation|translat|donat|patreon|paypal|discord|github|ko-fi|buy me"#

    /// The first sentence or two of an ESOUI description or a manifest line, as plain text, skipping
    /// lines that are notes, thanks, or asks rather than what the addon does.
    public static func blurb(_ description: String, limit: Int = 200) -> String {
        let lines = BBCode.plainText(description).components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 20 && $0.range(of: noise, options: .regularExpression) == nil }
        var text = (lines.isEmpty ? BBCode.plainText(description) : lines.prefix(3).joined(separator: " "))
            .replacingOccurrences(of: #"\(https?://[^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        if let end = head.range(of: #"[.!?](?=\s)[^.!?]*$"#, options: .regularExpression), end.lowerBound > head.index(head.startIndex, offsetBy: limit / 3) {
            text = String(head[...end.lowerBound])
        } else {
            text = head.trimmingCharacters(in: .whitespaces) + "…"
        }
        return text
    }

    /// Lines like "1360 | Adds price history to the guild store." Unknown ids and repeats are dropped.
    public static func parse(_ answer: String, candidates: Set<Int>, limit: Int = maxSuggestions) -> [AddonSuggestion] {
        var out: [AddonSuggestion] = []
        var seen = Set<Int>()
        for raw in answer.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "•*-` "))
            guard let match = line.firstMatch(of: /^\[?(\d+)\]?\s*[|:–—-]\s*(.+)$/),
                  let id = Int(match.1), candidates.contains(id), seen.insert(id).inserted else { continue }
            out.append(AddonSuggestion(id: id, reason: String(match.2).trimmingCharacters(in: .whitespaces)))
            if out.count == limit { break }
        }
        return out
    }
}
