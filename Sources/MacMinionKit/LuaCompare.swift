import Foundation

/// Structural equality and path diffs for SavedVariables trees (ignores byte spans).
public enum LuaCompare {
    /// True when both values match, including nested tables in entry order by key multiset.
    public static func equal(_ a: LuaValue, _ b: LuaValue) -> Bool {
        switch (a, b) {
        case (.string(let x), .string(let y)): return x == y
        case (.integer(let x), .integer(let y)): return x == y
        case (.number(let x), .number(let y)): return x == y || (x.isNaN && y.isNaN)
        case (.bool(let x), .bool(let y)): return x == y
        case (.nil, .nil): return true
        case (.table(let x), .table(let y)): return equal(x, y)
        // Integer/number cross-match when the game/serializer flips representation.
        case (.integer(let x), .number(let y)): return Double(x) == y
        case (.number(let x), .integer(let y)): return x == Double(y)
        default: return false
        }
    }

    public static func equal(_ a: LuaTable, _ b: LuaTable) -> Bool {
        guard a.entries.count == b.entries.count else { return false }
        // Compare as maps: file order may change when we re-serialize a subtree.
        var remaining = b.entries
        for entry in a.entries {
            guard let i = remaining.firstIndex(where: { $0.key == entry.key && equal($0.value, entry.value) }) else {
                return false
            }
            remaining.remove(at: i)
        }
        return remaining.isEmpty
    }

    /// Paths (from the root variable key) whose values differ between `old` and `new` documents.
    public static func differingPaths(old: SVDocument, new: SVDocument) -> [[LuaKey]] {
        var paths: [[LuaKey]] = []
        var oldByName: [String: LuaValue] = [:]
        for entry in old.variables {
            if case .string(let name) = entry.key { oldByName[name] = entry.value }
        }
        var newByName: [String: LuaValue] = [:]
        for entry in new.variables {
            if case .string(let name) = entry.key { newByName[name] = entry.value }
        }
        let names = Set(oldByName.keys).union(newByName.keys)
        for name in names.sorted() {
            diff(oldByName[name], newByName[name], path: [.string(name)], into: &paths)
        }
        return paths
    }

    private static func diff(_ a: LuaValue?, _ b: LuaValue?, path: [LuaKey], into paths: inout [[LuaKey]]) {
        switch (a, b) {
        case (nil, nil):
            return
        case (nil, _), (_, nil):
            paths.append(path)
        case (.table(let at)?, .table(let bt)?):
            var keys = Set(at.entries.map(\.key))
            keys.formUnion(bt.entries.map(\.key))
            // Stable order for tests: strings first by description, then others.
            let ordered = keys.sorted { $0.description < $1.description }
            for key in ordered {
                diff(at[key], bt[key], path: path + [key], into: &paths)
            }
        case (let av?, let bv?):
            if !equal(av, bv) { paths.append(path) }
        }
    }

    /// True when every differing path is allowed: either equals an allowed path, or is under one
    /// (so inserting nested tables for a deep change still passes).
    public static func onlyAllowedPathsDiffer(old: SVDocument, new: SVDocument, allowed: Set<AllowedPath>) -> Bool {
        let diffs = differingPaths(old: old, new: new)
        guard !diffs.isEmpty else { return true }
        return diffs.allSatisfy { diff in
            allowed.contains { allowedPath in
                allowedPath.matches(diff)
            }
        }
    }

    /// A path that may change, with optional "any account-wide lookups.requests" pattern for the companion.
    public struct AllowedPath: Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            case exact([LuaKey])
            /// `EsoMacMinion_Data` › * › * › `$AccountWide` › `lookups` › `requests` (and under it).
            case companionRequests
            /// `EsoMacMinion_Data` › * › * › `$AccountWide` › `lookups` when the whole lookups table is new/changed.
            case companionLookups
        }
        public let kind: Kind

        public static func exact(_ path: [LuaKey]) -> AllowedPath { AllowedPath(kind: .exact(path)) }
        public static var companionRequests: AllowedPath { AllowedPath(kind: .companionRequests) }
        public static var companionLookups: AllowedPath { AllowedPath(kind: .companionLookups) }

        public func matches(_ path: [LuaKey]) -> Bool {
            switch kind {
            case .exact(let allowed):
                // Diff at the leaf or any ancestor of an insert: path is prefix of allowed, or allowed is prefix of path.
                if path.count <= allowed.count {
                    return Array(allowed.prefix(path.count)) == path
                }
                return Array(path.prefix(allowed.count)) == allowed
            case .companionRequests:
                // lookups.requests and anything under it (new request keys, list items).
                return isCompanion(path, endingWith: ["lookups", "requests"], descendants: true)
            case .companionLookups:
                // Only the lookups node itself (inserting the whole table). Descendants under
                // answers are not allowed; request edits use companionRequests.
                return isCompanion(path, endingWith: ["lookups"], descendants: false)
            }
        }

        private func isCompanion(_ path: [LuaKey], endingWith suffix: [String], descendants: Bool) -> Bool {
            // EsoMacMinion_Data, profile, account, $AccountWide, then suffix… (and optionally under).
            let depth = 4 + suffix.count
            guard path.count >= depth,
                  path[0] == .string(CompanionData.variable),
                  path[3] == .string("$AccountWide") else { return false }
            for (i, name) in suffix.enumerated() {
                guard path[4 + i] == .string(name) else { return false }
            }
            return descendants || path.count == depth
        }
    }
}
