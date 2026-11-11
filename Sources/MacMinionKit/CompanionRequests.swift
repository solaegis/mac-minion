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

    /// The file's bytes with `requests.svGlobals` set in every `$AccountWide` table, other request keys
    /// kept. Nil when the file doesn't parse or holds no `EsoMacMinion_Data` table: nothing to change.
    public static func apply(svGlobals: [String], to data: Data) -> Data? {
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
                        let kept = (requestsEntry.value.table?.entries ?? []).filter { $0.key != .string("svGlobals") }
                        edits.append((requestsEntry.span, "[\"requests\"] = " + requestsTable(svGlobals, keeping: kept)))
                    } else {
                        let at = lookups.span.lowerBound + 1 // just inside `{`
                        edits.append((at..<at, "\n[\"requests\"] = " + requestsTable(svGlobals, keeping: []) + ","))
                    }
                } else if lookupsEntry == nil {
                    let at = wide.span.lowerBound + 1
                    edits.append((at..<at, "\n[\"lookups\"] = { [\"requests\"] = " + requestsTable(svGlobals, keeping: [])
                                  + ", [\"answers\"] = {}, },"))
                }
            }
        }
        guard !edits.isEmpty else { return nil }
        var bytes = [UInt8](data)
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            bytes.replaceSubrange(edit.range, with: Array(edit.text.utf8))
        }
        return Data(bytes)
    }

    /// Sets the request in the companion's SavedVariables file in `folder`, if there is one and it
    /// changes. Returns true when the file was written. The caller checks that ESO isn't running.
    @discardableResult
    public static func write(svGlobals: [String], savedVariables folder: URL) throws -> Bool {
        let fm = FileManager.default
        guard let url = CompanionData.fileNames.map({ folder.appending(path: $0) }).first(where: { fm.fileExists(atPath: $0.path) })
        else { return false }
        let data = try Data(contentsOf: url)
        guard let root = SVDocument.parse(data).variables.first(where: { $0.key == .string(CompanionData.variable) })?.value.table,
              requested(in: root) != svGlobals,
              let updated = apply(svGlobals: svGlobals, to: data), updated != data else { return false }
        try updated.write(to: url, options: .atomic)
        return true
    }

    /// The `svGlobals` list as it stands in every `$AccountWide` table, or nil when the tables disagree.
    static func requested(in root: LuaTable) -> [String]? {
        var found: [String]?
        for profile in root.entries {
            for account in profile.value.table?.entries ?? [] {
                guard let wide = account.value.table?.entries.first(where: { $0.key == .string("$AccountWide") })?.value.table else { continue }
                let list = (wide["lookups"]?.table?["requests"]?.table?["svGlobals"]?.table?.entries ?? []).compactMap(\.value.string)
                if let found, found != list { return nil }
                found = list
            }
        }
        return found
    }

    // MARK: Lua text

    static func requestsTable(_ svGlobals: [String], keeping kept: [LuaEntry]) -> String {
        var parts = kept.map { "\(key($0.key)) = \(value($0.value))" }
        let list = svGlobals.enumerated().map { "[\($0.offset + 1)] = \(quote($0.element))" }
        parts.append("[\"svGlobals\"] = { " + list.joined(separator: ", ") + (list.isEmpty ? "}" : ", }"))
        return "{ " + parts.joined(separator: ", ") + ", }"
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
