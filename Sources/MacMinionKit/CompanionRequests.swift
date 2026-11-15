import Foundation

/// What MacMinion asks ESO Mac Minion to look up at the next login: `lookups.requests` inside each
/// `$AccountWide` table of `EsoMacMinion_Data`. Only that entry is rewritten; every other byte of the
/// file stays as the game wrote it. Write only while ESO is closed: the game rewrites the file on save.
public enum CompanionRequests {
    /// Name ID kinds the companion answers (`kind:id` in `lookups.answers`).
    public static let nameKinds = ["item", "quest", "zone", "set", "collectible", "achievement"]

    /// Cap per kind so the companion queue stays bounded.
    public static let nameIDCap = 200

    /// The `svGlobals` request: every SavedVariables global the installed manifests declare, sorted,
    /// without the companion's own variable.
    public static func svGlobals(from declarations: [String: [String]]) -> [String] {
        Array(Set(declarations.values.flatMap { $0 }).subtracting([CompanionData.variable])).sorted()
    }

    /// Candidate LibAddonMenu panel globals: folder name, `FolderPanel`, plus our own panel id.
    public static func lamPanels(from folders: [String]) -> [String] {
        var names = Set<String>(["EsoMacMinionPanel"])
        for folder in folders where !CompanionData.isCompanionFolder(folder) {
            names.insert(folder)
            names.insert(folder + "Panel")
        }
        return names.sorted()
    }

    /// IDs from SavedVariables references that libraries / answers don't already name.
    public static func unmetNameIDs(references: SVReferenceIndex?, names: SVNameIndex?,
                                    answers: [String: CompanionAnswer] = [:]) -> [String: [Int]] {
        var sets: [String: Set<Int>] = Dictionary(uniqueKeysWithValues: nameKinds.map { ($0, []) })
        guard let references else { return Dictionary(uniqueKeysWithValues: nameKinds.map { ($0, []) }) }
        for target in references.hits.keys {
            let kind = target.kind.rawValue
            guard nameKinds.contains(kind), let id = Int(target.id) else { continue }
            if answers["\(kind):\(id)"]?.name != nil { continue }
            if named(kind: kind, id: id, names: names) { continue }
            sets[kind, default: []].insert(id)
        }
        return Dictionary(uniqueKeysWithValues: nameKinds.map { kind in
            (kind, Array(sets[kind, default: []].sorted().prefix(nameIDCap)))
        })
    }

    private static func named(kind: String, id: Int, names: SVNameIndex?) -> Bool {
        guard let names else { return false }
        switch kind {
        case "zone": return names.zones[id] != nil
        case "quest": return names.quests[id] != nil
        case "set": return names.sets[id] != nil
        case "item": return names.itemSets[id] != nil
        default: return false
        }
    }

    /// Paths `apply` / `write` are allowed to change under `EsoMacMinion_Data`.
    public static let allowedWritePaths: Set<LuaCompare.AllowedPath> = [
        .companionRequests,
        .companionLookups,
    ]

    /// Keys rewritten this write: always svGlobals / lamPanels; name kinds only when present in `nameIDs`.
    private static func rewrittenRequestKeys(nameIDs: [String: [Int]]) -> Set<String> {
        Set(["svGlobals", "lamPanels"]).union(nameIDs.keys)
    }

    /// The file's bytes with request lists set in every `$AccountWide` table; other request keys kept.
    public static func apply(svGlobals: [String], lamPanels: [String] = [],
                             nameIDs: [String: [Int]] = [:], to data: Data) -> Data? {
        let doc = SVDocument.parse(data)
        guard doc.error == nil,
              let root = doc.variables.first(where: { $0.key == .string(CompanionData.variable) })?.value.table else { return nil }
        let rewriting = rewrittenRequestKeys(nameIDs: nameIDs)
        var edits: [(range: Range<Int>, text: String)] = []
        for profile in root.entries {
            for account in profile.value.table?.entries ?? [] {
                guard let wide = account.value.table?.entries.first(where: { $0.key == .string("$AccountWide") })?.value.table else { continue }
                let lookupsEntry = wide.entries.first { $0.key == .string("lookups") }
                if let lookups = lookupsEntry?.value.table {
                    if let requestsEntry = lookups.entries.first(where: { $0.key == .string("requests") }) {
                        let kept = (requestsEntry.value.table?.entries ?? []).filter {
                            guard case .string(let name) = $0.key else { return true }
                            return !rewriting.contains(name)
                        }
                        edits.append((requestsEntry.span, "[\"requests\"] = " + requestsTable(svGlobals: svGlobals, lamPanels: lamPanels,
                                                                                              nameIDs: nameIDs, keeping: kept)))
                    } else {
                        let at = lookups.span.lowerBound + 1 // just inside `{`
                        edits.append((at..<at, "\n[\"requests\"] = " + requestsTable(svGlobals: svGlobals, lamPanels: lamPanels,
                                                                                    nameIDs: nameIDs, keeping: []) + ","))
                    }
                } else if lookupsEntry == nil {
                    let at = wide.span.lowerBound + 1
                    edits.append((at..<at, "\n[\"lookups\"] = { [\"requests\"] = " + requestsTable(svGlobals: svGlobals, lamPanels: lamPanels,
                                                                                                  nameIDs: nameIDs, keeping: [])
                                  + ", [\"answers\"] = {}, },"))
                }
            }
        }
        guard !edits.isEmpty else { return nil }
        var bytes = [UInt8](data)
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            bytes.replaceSubrange(edit.range, with: Array(edit.text.utf8))
        }
        let updated = Data(bytes)
        let after = SVDocument.parse(updated)
        guard after.error == nil,
              LuaCompare.onlyAllowedPathsDiffer(old: doc, new: after, allowed: allowedWritePaths) else { return nil }
        return updated
    }

    /// Sets the request lists in the companion's SavedVariables file. Returns true when written.
    @discardableResult
    public static func write(svGlobals: [String], lamPanels: [String] = [], nameIDs: [String: [Int]] = [:],
                             savedVariables folder: URL) throws -> Bool {
        let fm = FileManager.default
        guard let url = CompanionData.fileNames.map({ folder.appending(path: $0) }).first(where: { fm.fileExists(atPath: $0.path) })
        else { return false }
        let stamp = try SavedVariablesWrite.Stamp.read(url: url)
        guard let root = SVDocument.parse(stamp.data).variables.first(where: { $0.key == .string(CompanionData.variable) })?.value.table else { return false }
        let sameGlobals = requested(in: root) == svGlobals
        let samePanels = requestedLamPanels(in: root) == lamPanels
        let sameNames = nameKinds.allSatisfy { requestedInts(in: root, key: $0) == (nameIDs[$0] ?? []) }
        guard !(sameGlobals && samePanels && sameNames),
              let updated = apply(svGlobals: svGlobals, lamPanels: lamPanels, nameIDs: nameIDs, to: stamp.data),
              updated != stamp.data else { return false }
        try SavedVariablesWrite.write(updated, to: url, previouslyRead: stamp, allowed: allowedWritePaths)
        return true
    }

    /// The `svGlobals` list as it stands in every `$AccountWide` table, or nil when the tables disagree.
    static func requested(in root: LuaTable) -> [String]? {
        requestedList(in: root, key: "svGlobals")
    }

    static func requestedLamPanels(in root: LuaTable) -> [String]? {
        requestedList(in: root, key: "lamPanels")
    }

    private static func requestedList(in root: LuaTable, key: String) -> [String]? {
        var found: [String]?
        for profile in root.entries {
            for account in profile.value.table?.entries ?? [] {
                guard let wide = account.value.table?.entries.first(where: { $0.key == .string("$AccountWide") })?.value.table else { continue }
                let list = (wide["lookups"]?.table?["requests"]?.table?[key]?.table?.entries ?? []).compactMap(\.value.string)
                if let found, found != list { return nil }
                found = list
            }
        }
        return found
    }

    private static func requestedInts(in root: LuaTable, key: String) -> [Int]? {
        var found: [Int]?
        for profile in root.entries {
            for account in profile.value.table?.entries ?? [] {
                guard let wide = account.value.table?.entries.first(where: { $0.key == .string("$AccountWide") })?.value.table else { continue }
                let list = (wide["lookups"]?.table?["requests"]?.table?[key]?.table?.entries ?? []).compactMap { entry -> Int? in
                    switch entry.value {
                    case .integer(let n): return Int(n)
                    case .number(let d): return Int(d)
                    case .string(let s): return Int(s)
                    default: return nil
                    }
                }
                if let found, found != list { return nil }
                found = list
            }
        }
        return found
    }

    // MARK: Lua text

    static func requestsTable(svGlobals: [String], lamPanels: [String], nameIDs: [String: [Int]],
                              keeping kept: [LuaEntry]) -> String {
        var parts = kept.map { "\(key($0.key)) = \(value($0.value))" }
        parts.append(stringList("svGlobals", svGlobals))
        parts.append(stringList("lamPanels", lamPanels))
        for kind in nameKinds where nameIDs[kind] != nil {
            parts.append(intList(kind, nameIDs[kind] ?? []))
        }
        return "{ " + parts.joined(separator: ", ") + ", }"
    }

    private static func stringList(_ name: String, _ values: [String]) -> String {
        let list = values.enumerated().map { "[\($0.offset + 1)] = \(quote($0.element))" }
        return "[\"\(name)\"] = { " + list.joined(separator: ", ") + (list.isEmpty ? "}" : ", }")
    }

    private static func intList(_ name: String, _ values: [Int]) -> String {
        let list = values.enumerated().map { "[\($0.offset + 1)] = \($0.element)" }
        return "[\"\(name)\"] = { " + list.joined(separator: ", ") + (list.isEmpty ? "}" : ", }")
    }

    static func key(_ key: LuaKey) -> String {
        switch key {
        case .string(let s): "[\(quote(s))]"
        case .integer(let n): "[\(n)]"
        case .number(let d): "[\(number(d))]"
        case .bool(let b): b ? "[true]" : "[false]"
        }
    }

    static func value(_ value: LuaValue) -> String {
        switch value {
        case .string(let s): return quote(s)
        case .integer(let n): return String(n)
        case .number(let d): return number(d)
        case .bool(let b): return b ? "true" : "false"
        case .nil: return "nil"
        case .table(let t):
            let inner = t.entries.map { "\(key($0.key)) = \(self.value($0.value))" }
            return inner.isEmpty ? "{}" : "{ " + inner.joined(separator: ", ") + ", }"
        }
    }

    static func number(_ d: Double) -> String {
        if d.isInfinite { return d > 0 ? "math.huge" : "-math.huge" }
        return String(d)
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(c)
            }
        }
        return out + "\""
    }
}
