import Foundation

// MARK: - Defaults and who loads what (S-070)

extension SettingsMatrix {
    /// What turns saved settings into the settings each character runs on: each file's defaults, and which
    /// files each character loads.
    public struct ProfileContext: Sendable {
        /// SavedVariables file ("AutoResearch.lua") -> its variables' defaults.
        public var defaults: [String: [SVDefaults.Found]]
        /// Character ID -> the SavedVariables files of the addons they load.
        public var loads: [String: Set<String>]

        public init(defaults: [String: [SVDefaults.Found]] = [:], loads: [String: Set<String>] = [:]) {
            self.defaults = defaults
            self.loads = loads
        }

        public var isEmpty: Bool { defaults.isEmpty && loads.isEmpty }
    }

    /// Keys every addon's table carries that aren't settings: ZO_SavedVars' version and name, and
    /// LibSavedVars' own switch.
    public static func isBookkeeping(_ setting: Setting) -> Bool {
        setting.key == .string("version") || setting.key == .string("$LastCharacterName")
            || setting.path.dropFirst(4).contains(.string("LibSavedVars"))
    }

    /// LibSavedVars' switch in a character's table: true for account-wide, false for their own, nil when absent.
    static func accountSwitch(_ table: [String: Setting]?) -> Bool? {
        guard let s = table?.values.first(where: { $0.key == .string("accountSavedVarsActive")
            && $0.path.dropFirst(4).contains(.string("LibSavedVars")) }) else { return nil }
        if case .bool(let on) = s.value { return on }
        return nil
    }

    /// Each character's settings as the addon runs them: its defaults, then LibSavedVars' account-wide
    /// settings for a character who uses them, then the character's own. Characters who load an addon join
    /// it even with no table of their own; only characters this matrix already knows are added.
    public func applying(_ context: ProfileContext, names: SVNameIndex?) -> SettingsMatrix {
        guard !context.isEmpty else { return self }
        let known = Set(characterIDs)
        var loaders: [String: Set<String>] = [:]
        for (id, files) in context.loads where known.contains(id) {
            for file in files { loaders[file, default: []].insert(id) }
        }
        let byFile = Dictionary((addons + others).map { ($0.file, $0) }, uniquingKeysWith: { a, _ in a })
        let files = Set(addons.map(\.file)).union(loaders.keys)
        var result: [Addon] = []
        for file in files {
            let base = byFile[file]
            let found = context.defaults[file] ?? []
            var defaults: [String: Setting] = [:]
            var unresolved: [String: String] = [:]
            for f in found {
                // The same four steps a character's table has, so a default can be written under theirs.
                let root: [LuaKey] = [.string(f.variable), .string("$Defaults"), .string(""), .string("")]
                var flat: [String: Setting] = [:]
                Self.flatten(f.table, root, [], depth: Self.depth, names: names, into: &flat)
                defaults.merge(flat) { a, _ in a }
                for (path, text) in f.unresolved where path.count <= Self.depth {
                    unresolved[path.map { SVReadable.label($0, names: names) }.joined(separator: " › ")] = text
                }
            }
            let raw = base?.characters ?? [:]
            let libSavedVars = found.contains(where: \.libSavedVars)
                || raw.values.contains { Self.accountSwitch($0) != nil }
            let ids = Set(raw.keys).union(loaders[file] ?? [])
            guard !ids.isEmpty else { continue }
            var characters: [String: [String: Setting]] = [:]
            var own: [String: [String: Setting]] = [:]
            var profiles: [String: Profile] = [:]
            var sources: [String: [String: ValueSource]] = [:]
            for id in ids {
                let table = raw[id]
                let mine = (table ?? [:]).filter { !Self.isBookkeeping($0.value) }
                // LibSavedVars: no table, or the switch on, means the account-wide settings (LSV_Data.lua).
                let accountActive = libSavedVars
                    && (table == nil || Self.accountSwitch(table) == true)
                let account = accountActive ? accountTable(base, for: id) : [:]
                var settings = defaults
                var from: [String: ValueSource] = defaults.mapValues { _ in .defaults }
                for (key, s) in account { settings[key] = s; from[key] = .account }
                if !accountActive {
                    for (key, s) in mine { settings[key] = s; from.removeValue(forKey: key) }
                }
                own[id] = mine
                characters[id] = settings
                sources[id] = from
                profiles[id] = accountActive ? .accountWide : !mine.isEmpty ? .own : !defaults.isEmpty ? .defaults : .loadedOnly
            }
            result.append(Addon(file: file, shared: base?.shared ?? 0, characters: characters, own: own, profiles: profiles,
                                defaults: defaults, unresolvedDefaults: unresolved, sources: sources,
                                accountTables: base?.accountTables ?? [:], tablePaths: base?.tablePaths ?? [:]))
        }
        return SettingsMatrix(addons: result.sorted { $0.file.localizedStandardCompare($1.file) == .orderedAscending },
                              characterIDs: characterIDs, accounts: accounts, homes: homes, others: others)
    }

    /// The `$AccountWide` settings a character shares: their megaserver's and account's, or the only ones.
    func accountTable(_ addon: Addon?, for id: String) -> [String: Setting] {
        guard let tables = addon?.accountTables, !tables.isEmpty else { return [:] }
        if let home = homes[id] {
            if let t = tables["\(home.server)|\(home.account)"] { return t }
            if let t = tables["Default|\(home.account)"] { return t }
        }
        return tables.count == 1 ? tables.values.first! : [:]
    }
}
