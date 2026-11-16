import Foundation

// MARK: - Defaults and who loads what (S-070)

extension SettingsMatrix {
    /// What turns saved settings into the settings each character runs on: each file's defaults. Characters
    /// who load an addon but have no table in it are left out: they crowded the graph and the grid.
    public struct ProfileContext: Sendable {
        /// SavedVariables file ("AutoResearch.lua") -> its variables' defaults.
        public var defaults: [String: [SVDefaults.Found]]

        public init(defaults: [String: [SVDefaults.Found]] = [:]) {
            self.defaults = defaults
        }

        public var isEmpty: Bool { defaults.isEmpty }
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

    /// Each character's settings as the addon runs them: its defaults, then the account-wide settings for a
    /// character who uses them, then the character's own. A character with no table of their own joins an addon
    /// whose settings still reach them: its account-wide settings for their account (an addon that keeps only
    /// those, or LibSavedVars), else its known defaults. One with only bookkeeping and nothing known is left out.
    public func applying(_ context: ProfileContext, names: SVNameIndex?) -> SettingsMatrix {
        let byFile = Dictionary((addons + others).map { ($0.file, $0) }, uniquingKeysWith: { a, _ in a })
        // The companion's file is MacMinion's record of the game, not settings anyone runs on.
        let files = Set(byFile.keys).subtracting(CompanionData.fileNames)
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
            let perCharacter = !raw.isEmpty
            let ids = Set(raw.keys).union(characterIDs)
            var characters: [String: [String: Setting]] = [:]
            var own: [String: [String: Setting]] = [:]
            var profiles: [String: Profile] = [:]
            var sources: [String: [String: ValueSource]] = [:]
            for id in ids {
                let table = raw[id]
                let mine = (table ?? [:]).filter { !Self.isBookkeeping($0.value) }
                let shared = accountTable(base, for: id)
                // LibSavedVars' switch on (or, with no table, its fallback), or an addon that keeps only
                // account-wide settings: the account's settings are this character's.
                let accountActive = table == nil
                    ? !shared.isEmpty && (libSavedVars || !perCharacter)
                    : libSavedVars && Self.accountSwitch(table) == true
                // Nothing of their own and nothing known to run on: nothing to show.
                if !accountActive, mine.isEmpty, defaults.isEmpty { continue }
                let account = accountActive ? shared : [:]
                var settings = defaults
                var from: [String: ValueSource] = defaults.mapValues { _ in .defaults }
                for (key, s) in account { settings[key] = s; from[key] = .account }
                if !accountActive {
                    for (key, s) in mine { settings[key] = s; from.removeValue(forKey: key) }
                }
                own[id] = mine
                characters[id] = settings
                sources[id] = from
                profiles[id] = accountActive ? .accountWide : !mine.isEmpty ? .own : .defaults
            }
            result.append(Addon(file: file, shared: base?.shared ?? 0, characters: characters, own: own, profiles: profiles,
                                defaults: defaults, unresolvedDefaults: unresolved, sources: sources,
                                accountTables: base?.accountTables ?? [:], tablePaths: base?.tablePaths ?? [:]))
        }
        result.removeAll { $0.characters.isEmpty }
        return SettingsMatrix(addons: result.sorted { $0.file.localizedStandardCompare($1.file) == .orderedAscending },
                              characterIDs: characterIDs, accounts: accounts, homes: homes, others: others)
    }

    /// The `$AccountWide` settings a character shares: their account's, for their megaserver, then the `Default`
    /// profile's. Nothing when their account isn't known: another account's settings aren't theirs.
    func accountTable(_ addon: Addon?, for id: String) -> [String: Setting] {
        guard let tables = addon?.accountTables, !tables.isEmpty, let home = homes[id] else { return [:] }
        let server = home.server.hasSuffix(" Megaserver") ? home.server : CharacterID.megaserver(ofID: id) ?? home.server
        var merged = tables["Default|\(home.account)"] ?? [:]
        merged.merge(tables["\(server)|\(home.account)"] ?? [:]) { _, b in b }
        return merged
    }
}
