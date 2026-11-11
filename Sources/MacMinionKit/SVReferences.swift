import Foundation

/// Something an ID stands for, the same in every file: a character, an item, a zone.
public struct SVTarget: Hashable, Sendable, CustomStringConvertible {
    public let kind: SVName.Kind
    /// The character or item ID, the account name, the guild ID (or name, from LibGuildStore's index).
    public let id: String

    public init(_ kind: SVName.Kind, _ id: String) { self.kind = kind; self.id = id }

    public var description: String { "\(kind.rawValue) \(id)" }

    /// What a key stands for, if anything: a character ID, an account, an item link, or an item ID
    /// keying LibGuildStore's sales (`GS00DataSavedVariables › dataeu › 29516`).
    public static func of(key: LuaKey, at path: [LuaKey]) -> SVTarget? {
        switch key {
        case .string(let s): return of(string: s)
        case .integer(let n):
            if path.count == 2, isGuildStore(path), path[1].description.hasPrefix("data") { return SVTarget(.item, String(n)) }
            return nil
        default: return nil
        }
    }

    /// What a value stands for, from its shape or its key; LibGuildStore's numbers go through `names`.
    public static func of(value: LuaValue, key: LuaKey, at path: [LuaKey], names: SVNameIndex) -> SVTarget? {
        switch value {
        case .string(let s): return of(string: s)
        case .integer(let n):
            let keyName = key.description
            if isGuildStore(path) {
                switch keyName {
                case "itemLink": return names.guildStoreLinks[n].flatMap { ItemLink.parse($0) }.map { SVTarget(.item, String($0.itemID)) }
                case "seller", "buyer": return names.guildStoreAccounts[n].map { SVTarget(.account, $0) }
                case "guild": return names.guildStoreGuilds[n].map { guild(named: $0, names) }
                default: break
                }
            }
            switch keyName {
            case "zoneId", "zoneID": return SVTarget(.zone, String(n))
            case "questId", "questID": return SVTarget(.quest, String(n))
            case "setId", "setID": return SVTarget(.set, String(n))
            case "itemId", "itemID": return SVTarget(.item, String(n))
            case "guildId", "guildID": return SVTarget(.guild, String(n))
            case "achievementId", "achievementID": return SVTarget(.achievement, String(n))
            case "mapId", "mapID": return SVTarget(.map, String(n))
            default: return nil
            }
        default: return nil
        }
    }

    static func of(string s: String) -> SVTarget? {
        if CharacterID.isID(s) { return SVTarget(.character, s) }
        if s.hasPrefix("@"), s.count > 1, !s.contains(" ") { return SVTarget(.account, s) }
        if ItemLink.isLink(s), let link = ItemLink.parse(s) { return SVTarget(.item, String(link.itemID)) }
        return nil
    }

    /// A guild by ID when some file pairs its name with one, otherwise by name.
    static func guild(named name: String, _ names: SVNameIndex) -> SVTarget {
        if let id = names.guildIDs[name] { return SVTarget(.guild, String(id)) }
        return SVTarget(.guild, name)
    }

    static func isGuildStore(_ path: [LuaKey]) -> Bool {
        let variable = path.first?.description ?? ""
        return variable.hasPrefix("GS") && variable.hasSuffix("DataSavedVariables")
    }
}

/// One mention: which file, and where its entry starts. The key path is found again on demand
/// (`SVDocument.entry(at:)`), so the index stays small for a million entries.
public struct SVHit: Hashable, Sendable {
    public let file: Int32
    public let offset: Int32
}

/// Every place each ID appears across SavedVariables. Built once per scan of the folder.
public struct SVReferenceIndex: Sendable {
    public let files: [String]
    public private(set) var hits: [SVTarget: [SVHit]] = [:]

    public static func build(documents: [String: SVDocument], names: SVNameIndex) -> SVReferenceIndex {
        let files = documents.keys.sorted()
        var index = SVReferenceIndex(files: files)
        for (i, file) in files.enumerated() {
            for variable in documents[file]!.variables {
                index.collect(variable, parentPath: [], file: Int32(i), names: names)
            }
        }
        return index
    }

    /// The same index with each file on its own core, merged in file order, so every ID's hits come out
    /// in the order `build` gives them.
    public static func buildConcurrently(documents: [String: SVDocument], names: SVNameIndex) async -> SVReferenceIndex {
        let files = documents.keys.sorted()
        let parts = await withTaskGroup(of: (Int, [SVTarget: [SVHit]]).self) { group in
            for (i, file) in files.enumerated() {
                let doc = documents[file]!
                group.addTask {
                    var part = SVReferenceIndex(files: [])
                    for variable in doc.variables { part.collect(variable, parentPath: [], file: Int32(i), names: names) }
                    return (i, part.hits)
                }
            }
            var parts = [[SVTarget: [SVHit]]](repeating: [:], count: files.count)
            for await (i, hits) in group { parts[i] = hits }
            return parts
        }
        var index = SVReferenceIndex(files: files)
        for part in parts {
            for (target, hits) in part { index.hits[target, default: []].append(contentsOf: hits) }
        }
        return index
    }

    /// One file's hits, as file number `file` of the index's files.
    public static func hits(in doc: SVDocument, file: Int32, names: SVNameIndex) -> [SVTarget: [SVHit]] {
        var part = SVReferenceIndex(files: [])
        for variable in doc.variables { part.collect(variable, parentPath: [], file: file, names: names) }
        return part.hits
    }

    /// An index from each file's hits, in the order of `files`: part `i` becomes file number `i`, whatever
    /// number its hits were made with.
    public static func merging(files: [String], parts: [[SVTarget: [SVHit]]]) -> SVReferenceIndex {
        var index = SVReferenceIndex(files: files)
        for (i, part) in parts.enumerated() {
            let file = Int32(i)
            for (target, hits) in part {
                index.hits[target, default: []].append(contentsOf: hits.lazy.map { SVHit(file: file, offset: $0.offset) })
            }
        }
        return index
    }

    mutating func collect(_ entry: LuaEntry, parentPath: [LuaKey], file: Int32, names: SVNameIndex) {
        let hit = SVHit(file: file, offset: Int32(entry.span.lowerBound))
        if let target = SVTarget.of(key: entry.key, at: parentPath) { hits[target, default: []].append(hit) }
        if let target = SVTarget.of(value: entry.value, key: entry.key, at: parentPath, names: names) {
            hits[target, default: []].append(hit)
        }
        if let table = entry.value.table {
            let path = parentPath + [entry.key]
            for child in table.entries { collect(child, parentPath: path, file: file, names: names) }
        }
    }

    public var targetCount: Int { hits.count }
    public var hitCount: Int { hits.values.reduce(0) { $0 + $1.count } }

    /// IDs whose ID or name matches `query`, most mentioned first: "Masisi", "@Paltop", "Glenumbra", "96175".
    public func targets(matching query: String, names: SVNameIndex, limit: Int = 50) -> [SVTarget] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let found = hits.keys.filter { target in
            if target.id.caseInsensitiveCompare(q) == .orderedSame { return true }
            if target.kind == .account, target.id.localizedCaseInsensitiveContains(q) { return true }
            guard q.count >= 2, let name = names.title(for: target) else { return false }
            return name.localizedCaseInsensitiveContains(q)
        }
        return found.sorted { (hits[$0]?.count ?? 0, $1.description) > (hits[$1]?.count ?? 0, $0.description) }.prefix(limit).map { $0 }
    }
}

extension SVNameIndex {
    /// The name for a target, when one is known.
    public func title(for target: SVTarget) -> String? {
        let n = Int(target.id) ?? -1
        switch target.kind {
        case .character: return characters[target.id]?.name
        case .account: return target.id
        case .guild: return Int64(target.id).flatMap { guilds[$0] } ?? (Int64(target.id) == nil ? target.id : nil)
        case .item: return itemSets[n].flatMap { sets[$0] }.map { String(localized: "Item \(n) · \($0) set", bundle: .module) }
        case .set: return sets[n]
        case .zone: return zones[n]
        case .quest: return quests[n]
        case .achievement, .map: return nil
        }
    }
}

extension SVDocument {
    /// The entry starting at `offset`, and the keys down to it, variable first. Walks down by byte
    /// span, so finding a mention again costs a few comparisons per level.
    public func entry(at offset: Int) -> (path: [LuaKey], entry: LuaEntry)? {
        var entries = variables, path: [LuaKey] = []
        while true {
            // Entries are in file order: the last one starting at or before the offset holds it.
            var lo = 0, hi = entries.count
            while lo < hi { let mid = (lo + hi) / 2; if entries[mid].span.lowerBound <= offset { lo = mid + 1 } else { hi = mid } }
            guard lo > 0 else { return nil }
            let entry = entries[lo - 1]
            guard entry.span.contains(offset) || entry.span.lowerBound == offset else { return nil }
            path.append(entry.key)
            if entry.span.lowerBound == offset { return (path, entry) }
            guard let table = entry.value.table else { return nil }
            entries = table.entries
        }
    }
}

/// Key paths as people and Copy Path write them.
public enum LuaPath {
    /// `Var["NA Megaserver"]["@me"][1]`, or `Var › NA Megaserver › @me › 1`. Nil when it can't be read.
    public static func parse(_ text: String) -> [LuaKey]? {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return [] }
        if s.contains("›") {
            return s.components(separatedBy: "›").map { part in
                let p = part.trimmingCharacters(in: .whitespaces)
                return Int64(p).map(LuaKey.integer) ?? .string(p)
            }
        }
        var keys: [LuaKey] = []
        var rest = Substring(s)
        let head = rest.prefix { $0 != "[" }
        if !head.isEmpty { keys.append(.string(String(head))); rest = rest.dropFirst(head.count) }
        while !rest.isEmpty {
            guard rest.first == "[" else { return nil }
            rest = rest.dropFirst()
            if rest.first == "\"" {
                rest = rest.dropFirst()
                var key = "", escaped = false
                while let c = rest.first {
                    rest = rest.dropFirst()
                    if escaped { key.append(c); escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { break } else { key.append(c) }
                }
                guard rest.first == "]" else { return nil }
                keys.append(.string(key))
            } else {
                let inner = rest.prefix { $0 != "]" }
                rest = rest.dropFirst(inner.count)
                guard rest.first == "]" else { return nil }
                if let n = Int64(inner) { keys.append(.integer(n)) }
                else if inner == "true" || inner == "false" { keys.append(.bool(inner == "true")) }
                else if let d = Double(inner) { keys.append(.number(d)) }
                else { return nil }
            }
            rest = rest.dropFirst()
        }
        return keys
    }
}

extension SVDocument {
    /// Follows a path typed by a person, where `8796093036412335` may mean the number or the string:
    /// each key matches as written, or else the same digits in the other form. Returns the path as stored.
    public func resolve(_ path: [LuaKey]) -> (path: [LuaKey], value: LuaValue)? {
        var entries = variables, resolved: [LuaKey] = [], value: LuaValue?
        for key in path {
            let alternate: LuaKey? = switch key {
            case .integer(let n): .string(String(n))
            case .string(let s): Int64(s).map(LuaKey.integer)
            default: nil
            }
            guard let entry = entries.first(where: { $0.key == key }) ?? alternate.flatMap({ alt in entries.first { $0.key == alt } }) else { return nil }
            resolved.append(entry.key)
            value = entry.value
            entries = entry.value.table?.entries ?? []
        }
        return value.map { (resolved, $0) }
    }
}

/// What sits next to one ID (S-051): the files that mention it, and the other IDs stored with it,
/// ranked by how often. For a mention that holds a table (a character's own settings), what's inside
/// counts; for a plain value (an item link in a sale), the table it sits in counts.
public struct SVNeighborhood: Sendable, Equatable {
    public struct Count: Sendable, Equatable {
        public let target: SVTarget
        public let count: Int
    }

    public let target: SVTarget
    public let files: [(file: String, count: Int)]
    public let neighbors: [Count]

    public static func == (a: Self, b: Self) -> Bool {
        a.target == b.target && a.neighbors == b.neighbors && a.files.map(\.file) == b.files.map(\.file) && a.files.map(\.count) == b.files.map(\.count)
    }

    /// At most this many neighbors, and this many mentions read to find them.
    public static let limit = 12
    public static let perKindLimit = 4
    public static let mentionsRead = 2_000

    public static func build(_ target: SVTarget, refs: SVReferenceIndex, names: SVNameIndex,
                             read: (String) -> SVDocument?) -> SVNeighborhood {
        let hits = refs.hits[target] ?? []
        var fileCounts: [String: Int] = [:]
        for hit in hits { fileCounts[refs.files[Int(hit.file)], default: 0] += 1 }
        var counts: [SVTarget: Int] = [:]
        var docs: [String: SVDocument] = [:]

        /// `siblings`: the table is one the target is a key of, like a map of character ID -> name; its
        /// other keys of the same kind are just the rest of that list, not connections.
        func note(_ entry: LuaEntry, at parent: [LuaKey], siblings: Bool) {
            let keyTarget = SVTarget.of(key: entry.key, at: parent)
            if let keyTarget, keyTarget != target, !(siblings && keyTarget.kind == target.kind) { counts[keyTarget, default: 0] += 1 }
            if let found = SVTarget.of(value: entry.value, key: entry.key, at: parent, names: names), found != target {
                counts[found, default: 0] += 1
            }
        }
        /// A table and the tables inside it, a few levels down and a few hundred entries at most.
        func walk(_ table: LuaTable, _ path: [LuaKey], depth: Int, siblings: Bool = false, budget: inout Int) {
            for entry in table.entries {
                guard budget > 0 else { return }
                budget -= 1
                note(entry, at: path, siblings: siblings)
                if depth > 1, let inner = entry.value.table { walk(inner, path + [entry.key], depth: depth - 1, budget: &budget) }
            }
        }

        for hit in hits.prefix(mentionsRead) {
            let file = refs.files[Int(hit.file)]
            if docs[file] == nil { docs[file] = read(file) }
            guard let doc = docs[file], let found = doc.entry(at: Int(hit.offset)) else { continue }
            var budget = 400
            if let table = found.entry.value.table, SVTarget.of(key: found.entry.key, at: Array(found.path.dropLast())) == target {
                walk(table, found.path, depth: 3, budget: &budget)
            } else if let parent = doc.resolve(Array(found.path.dropLast()))?.value.table {
                let isKey = SVTarget.of(key: found.entry.key, at: Array(found.path.dropLast())) == target
                walk(parent, Array(found.path.dropLast()), depth: 1, siblings: isKey, budget: &budget)
            }
        }
        // Most mentioned first, at most four of a kind, so items, zones, and guilds all get room.
        var perKind: [SVName.Kind: Int] = [:]
        let neighbors = counts.map { Count(target: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.target.description) > ($1.count, $0.target.description) }
            .filter { n in
                perKind[n.target.kind, default: 0] += 1
                return perKind[n.target.kind]! <= perKindLimit
            }
        return SVNeighborhood(target: target,
                              files: fileCounts.map { ($0.key, $0.value) }.sorted { ($0.count, $1.file) > ($1.count, $0.file) },
                              neighbors: Array(neighbors.prefix(limit)))
    }
}
