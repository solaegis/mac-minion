import Foundation

/// What MacMinion asks ESO Mac Minion to look up at the next login: `lookups.requests` inside each
/// `$AccountWide` table of `EsoMacMinion_Data`. Only that entry is rewritten; every other byte of the
/// file stays as the game wrote it. Write only while ESO is closed: the game rewrites the file on save.
public enum CompanionRequests {
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

    /// Paths `apply` / `write` are allowed to change under `EsoMacMinion_Data`.
    public static let allowedWritePaths: Set<LuaCompare.AllowedPath> = [
        .companionRequests,
        .companionLookups,
    ]

    private static let rewrittenRequestKeys: Set<String> = ["svGlobals", "lamPanels"]

    /// The file's bytes with `requests.svGlobals` / `lamPanels` set in every `$AccountWide` table, other
    /// request keys kept. Nil when the file doesn't parse, holds no `EsoMacMinion_Data` table, or the
    /// splice would leave unparsable bytes / unintended keys: nothing to change.
    public static func apply(svGlobals: [String], lamPanels: [String] = [], to data: Data) -> Data? {
        let doc = SVDocument.parse(data)
        guard doc.error == nil,
              let root = doc.variables.first(where: { $0.key == .string(CompanionData.variable) })?.value.table else { return nil }
        var edits: [(range: Range<Int>, text: String)] = []
        for profile in root.entries {
            for account in profile.value.table?.entries ?? [] {
                guard let wide = account.value.table?.entries.first(where: { $0.key == .string("$AccountWide") })?.value.table else { continue }
                let lookupsEntry = wide.entries.first { $0.key == .string("lookups") }
                if let lookups = lookupsEntry?.value.table {
                    if let requestsEntry = lookups.entries.first(where: { $0.key == .string("requests") }) {
                        let kept = (requestsEntry.value.table?.entries ?? []).filter {
                            guard case .string(let name) = $0.key else { return true }
                            return !rewrittenRequestKeys.contains(name)
                        }
                        edits.append((requestsEntry.span, "[\"requests\"] = " + requestsTable(svGlobals: svGlobals, lamPanels: lamPanels, keeping: kept)))
                    } else {
                        let at = lookups.span.lowerBound + 1 // just inside `{`
                        edits.append((at..<at, "\n[\"requests\"] = " + requestsTable(svGlobals: svGlobals, lamPanels: lamPanels, keeping: []) + ","))
                    }
                } else if lookupsEntry == nil {
                    let at = wide.span.lowerBound + 1
                    edits.append((at..<at, "\n[\"lookups\"] = { [\"requests\"] = " + requestsTable(svGlobals: svGlobals, lamPanels: lamPanels, keeping: [])
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
        // Never hand back bytes that won't load in ESO or that touched keys outside lookups.requests.
        let after = SVDocument.parse(updated)
        guard after.error == nil,
              LuaCompare.onlyAllowedPathsDiffer(old: doc, new: after, allowed: allowedWritePaths) else { return nil }
        return updated
    }

    /// Sets the request in the companion's SavedVariables file in `folder`, if there is one and it
    /// changes. Returns true when the file was written. The caller checks that ESO isn't running.
    /// Throws `SavedVariablesWrite.Refusal` when a write was needed but refused.
    @discardableResult
    public static func write(svGlobals: [String], lamPanels: [String] = [], savedVariables folder: URL) throws -> Bool {
        let fm = FileManager.default
        guard let url = CompanionData.fileNames.map({ folder.appending(path: $0) }).first(where: { fm.fileExists(atPath: $0.path) })
        else { return false }
        let stamp = try SavedVariablesWrite.Stamp.read(url: url)
        guard let root = SVDocument.parse(stamp.data).variables.first(where: { $0.key == .string(CompanionData.variable) })?.value.table else { return false }
        let sameGlobals = requested(in: root) == svGlobals
        let samePanels = requestedLamPanels(in: root) == lamPanels
        guard !(sameGlobals && samePanels),
              let updated = apply(svGlobals: svGlobals, lamPanels: lamPanels, to: stamp.data), updated != stamp.data else { return false }
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

    // MARK: Lua text

    static func requestsTable(svGlobals: [String], lamPanels: [String], keeping kept: [LuaEntry]) -> String {
        var parts = kept.map { "\(key($0.key)) = \(value($0.value))" }
        parts.append(stringList("svGlobals", svGlobals))
        parts.append(stringList("lamPanels", lamPanels))
        return "{ " + parts.joined(separator: ", ") + ", }"
    }

    private static func stringList(_ name: String, _ values: [String]) -> String {
        let list = values.enumerated().map { "[\($0.offset + 1)] = \(quote($0.element))" }
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
