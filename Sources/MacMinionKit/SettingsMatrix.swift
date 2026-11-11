import Foundation

/// Addons' saved settings, per character (S-053 to S-057): which addons keep settings for which
/// characters, which settings are the same everywhere, and where a character is set up differently.
/// Read from SavedVariables configuration only.
public struct SettingsMatrix: Sendable {
    /// One addon's settings: what every character shares, and each character's own.
    public struct Addon: Sendable, Identifiable {
        public let file: String
        /// Settings in `$AccountWide` tables, shared by every character.
        public let shared: Int
        /// Character ID -> setting key ("Auto craft", "Colors › Guild 1") -> value.
        public let characters: [String: [String: Setting]]
        /// Every setting key any character has, by name.
        public let keys: [String]
        /// Key -> its values and who has each, worked out once: the grid asks for them on every redraw.
        let groups: [String: [ValueGroup]]
        public var id: String { file }

        init(file: String, shared: Int, characters: [String: [String: Setting]]) {
            self.file = file
            self.shared = shared
            self.characters = characters
            var byKey: [String: [String: (setting: Setting, ids: [String])]] = [:]
            for (id, settings) in characters {
                for (key, s) in settings { byKey[key, default: [:]][s.text, default: (s, [])].ids.append(id) }
            }
            keys = byKey.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            groups = byKey.mapValues { values in
                values.values.map { ValueGroup(setting: $0.setting, characters: $0.ids.sorted()) }
                    .sorted { ($0.characters.count, $1.setting.text) > ($1.characters.count, $0.setting.text) }
            }
        }

        /// For each key, its values and who has each, most common first.
        public func values(of key: String) -> [ValueGroup] { groups[key] ?? [] }

        /// Keys whose value isn't the same for every character that has them.
        public var differing: [String] { keys.filter { values(of: $0).count > 1 } }

        /// Keys every character has, with the same value.
        public var same: [String] {
            keys.filter { key in
                let groups = values(of: key)
                return groups.count == 1 && groups[0].characters.count == characters.count
            }
        }

        /// Keys only some characters have, all with one value: set once, or added by a later version of the addon.
        public var partial: [String] {
            keys.filter { key in
                let groups = values(of: key)
                return groups.count == 1 && groups[0].characters.count < characters.count
            }
        }

        /// A character's settings that aren't the most common value, with that usual value.
        public func oddOnesOut(_ id: String) -> [(key: String, setting: Setting, usual: Setting)] {
            guard let mine = characters[id] else { return [] }
            return mine.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap { key in
                let groups = values(of: key)
                guard groups.count > 1, let usual = groups.first, let s = mine[key], s.text != usual.setting.text else { return nil }
                // A tie isn't odd: only a value fewer characters share than the most common one.
                let mineShared = groups.first(where: { $0.setting.text == s.text })?.characters.count ?? 0
                guard usual.characters.count > mineShared else { return nil }
                return (key, s, usual.setting)
            }
        }
    }

    /// One saved value, with where it lives so it can be opened.
    public struct Setting: Sendable {
        public let value: LuaValue
        public let key: LuaKey
        /// The full path in the file, variable first.
        public let path: [LuaKey]
        /// For comparing values: the plain value, or the color's components.
        public let text: String
    }

    public struct ValueGroup: Sendable {
        public let setting: Setting
        public let characters: [String]
    }

    /// Where a character lives: the account and megaserver whose tables hold their settings.
    public struct Home: Sendable, Hashable {
        public let account: String
        public let server: String
    }

    /// One account's characters on one megaserver, by name.
    public struct ServerGroup: Sendable, Identifiable {
        public let server: String
        public let characters: [String]
        public var id: String { server }
    }

    /// One account's characters, megaserver by megaserver.
    public struct AccountGroup: Sendable, Identifiable {
        public let account: String
        public let servers: [ServerGroup]
        public var id: String { account }
        public var characters: [String] { servers.flatMap(\.characters) }
    }

    public let addons: [Addon]
    /// Characters with any per-character settings: by account, then megaserver, then name.
    public let characterIDs: [String]
    /// The same characters, grouped by account, then megaserver.
    public let accounts: [AccountGroup]
    /// Character ID -> account and megaserver.
    public let homes: [String: Home]

    /// Shown when no file says which account or megaserver a character is on.
    public static let unknownAccount = String(localized: "Unknown account", bundle: .module)
    public static let unknownServer = String(localized: "Unknown megaserver", bundle: .module)

    public func addon(_ file: String) -> Addon? { addons.first { $0.file == file } }

    /// Settings a character has in each addon, and how many are odd ones out.
    public func cell(_ file: String, _ id: String) -> (settings: Int, odd: Int)? {
        cells[file]?[id].map { ($0.settings, $0.odd) }
    }

    struct Cell: Sendable { let settings: Int, odd: Int }
    /// File -> character ID -> cell, worked out once.
    let cells: [String: [String: Cell]]

    init(addons: [Addon], characterIDs: [String], accounts: [AccountGroup], homes: [String: Home]) {
        self.addons = addons
        self.characterIDs = characterIDs
        self.accounts = accounts
        self.homes = homes
        cells = Dictionary(uniqueKeysWithValues: addons.map { addon in
            (addon.file, Dictionary(uniqueKeysWithValues: addon.characters.map { id, settings in
                (id, Cell(settings: settings.count, odd: addon.oddOnesOut(id).count))
            }))
        })
    }

    /// Addons where this character is the only one with settings.
    public func onlyHere(_ id: String) -> [String] {
        addons.filter { $0.characters.count == 1 && $0.characters[id] != nil }.map(\.file)
    }

    /// Two characters side by side in one addon (S-057): settings where their values differ, and
    /// settings only one of them has.
    public struct Comparison: Sendable, Identifiable {
        public let file: String
        public let differing: [(key: String, a: Setting, b: Setting)]
        public let onlyA: [(key: String, setting: Setting)]
        public let onlyB: [(key: String, setting: Setting)]
        public var id: String { file }
    }

    /// Every addon where two characters' settings differ, by addon name.
    public func compare(_ a: String, _ b: String) -> [Comparison] {
        addons.compactMap { addon in
            let sa = addon.characters[a] ?? [:], sb = addon.characters[b] ?? [:]
            guard !sa.isEmpty || !sb.isEmpty else { return nil }
            let byName: (String, String) -> Bool = { $0.localizedStandardCompare($1) == .orderedAscending }
            let differing = Set(sa.keys).intersection(sb.keys).sorted(by: byName).compactMap { key -> (key: String, a: Setting, b: Setting)? in
                guard let x = sa[key], let y = sb[key], x.text != y.text else { return nil }
                return (key, x, y)
            }
            let onlyA = Set(sa.keys).subtracting(sb.keys).sorted(by: byName).map { ($0, sa[$0]!) }
            let onlyB = Set(sb.keys).subtracting(sa.keys).sorted(by: byName).map { ($0, sb[$0]!) }
            guard !differing.isEmpty || !onlyA.isEmpty || !onlyB.isEmpty else { return nil }
            return Comparison(file: addon.file, differing: differing, onlyA: onlyA, onlyB: onlyB)
        }
    }

    /// How deep into nested tables a character's settings are read.
    public static let depth = 2

    public static func build(documents: [String: SVDocument], names: SVNameIndex) -> SettingsMatrix {
        let sorted = documents.sorted(by: { $0.key < $1.key })
        var homes: [String: Home] = [:]
        for (_, doc) in sorted { mergeHomes(&homes, Self.homes(in: doc)) }
        let byName = charactersByName(names)
        return assemble(addons: sorted.compactMap { addon(file: $0.key, document: $0.value, names: names, homes: homes, byName: byName) },
                        names: names, homes: homes)
    }

    /// Where each character lives, from one file's tables keyed by their ID: an ID belongs to one account on one
    /// megaserver. A table keyed by name doesn't say which character it is when two share a name.
    public static func homes(in doc: SVDocument) -> [String: Home] {
        var homes: [String: Home] = [:]
        for v in doc.variables {
            for server in v.value.table?.entries ?? [] {
                guard case .string(let s) = server.key, SVLevel.servers.contains(s) else { continue }
                for account in server.value.table?.entries ?? [] {
                    guard case .string(let a) = account.key, a.hasPrefix("@") else { continue }
                    for c in account.value.table?.entries ?? [] {
                        guard case .string(let id) = c.key, CharacterID.isID(id), c.value.table != nil else { continue }
                        // "Default" is the profile an addon gets when it names none, not a megaserver: prefer a real one.
                        if homes[id] == nil || (homes[id]?.server == "Default" && s != "Default") {
                            homes[id] = Home(account: a, server: s)
                        }
                    }
                    // A megaserver passed as the namespace instead of the profile (CraftStore, EsoAutoProvision,
                    // EsoCombatLock, EsoVendorJunk): `<profile> › @acct › $AccountWide › NA Megaserver › … › <ID>`.
                    for namespace in account.value.table?["$AccountWide"]?.table?.entries ?? [] {
                        guard case .string(let ns) = namespace.key, let megaserver = SVLevel.megaserver(ofProfile: ns),
                              let inner = namespace.value.table else { continue }
                        for id in characterIDs(in: inner, depth: 3) where homes[id] == nil || homes[id]?.server == "Default" {
                            homes[id] = Home(account: a, server: megaserver)
                        }
                    }
                }
            }
            // IIfA's own layout, with short megaserver codes: `@acct › servers › NA | EU › CharIdToName › <ID>`.
            for account in v.value.table?.entries ?? [] {
                guard case .string(let a) = account.key, a.hasPrefix("@"),
                      let servers = account.value.table?["servers"]?.table else { continue }
                for server in servers.entries {
                    guard case .string(let code) = server.key, let megaserver = shortServers[code],
                          let ids = server.value.table?["CharIdToName"]?.table else { continue }
                    for e in ids.entries {
                        guard case .string(let id) = e.key, CharacterID.isID(id) else { continue }
                        if homes[id] == nil || homes[id]?.server == "Default" { homes[id] = Home(account: a, server: megaserver) }
                    }
                }
            }
        }
        return homes
    }

    /// Short megaserver codes some addons key by (IIfA, LibCharacterKnowledge).
    static let shortServers = ["NA": "NA Megaserver", "EU": "EU Megaserver", "PTS": "PTS"]

    /// Character IDs keying tables in `table`, looking `depth` levels down.
    static func characterIDs(in table: LuaTable, depth: Int) -> [String] {
        var out: [String] = []
        for e in table.entries {
            if case .string(let k) = e.key, CharacterID.isID(k), e.value.table != nil {
                out.append(k)
            } else if depth > 1, let inner = e.value.table {
                out += characterIDs(in: inner, depth: depth - 1)
            }
        }
        return out
    }

    /// Adds a later file's homes: the first real megaserver wins over "Default" (no profile).
    public static func mergeHomes(_ homes: inout [String: Home], _ later: [String: Home]) {
        for (id, home) in later where homes[id] == nil || (homes[id]?.server == "Default" && home.server != "Default") { homes[id] = home }
    }

    /// Character IDs by name, for addons that key characters by name.
    public static func charactersByName(_ names: SVNameIndex) -> [String: [String]] {
        var byName: [String: [String]] = [:]
        for (id, c) in names.characters { byName[c.name, default: []].append(id) }
        return byName
    }

    /// One file's settings per character, or nil when it keeps none per character.
    public static func addon(file: String, document doc: SVDocument, names: SVNameIndex, homes: [String: Home],
                             byName: [String: [String]]) -> Addon? {
        // Some addons key characters by name ("Ringil of Eskiath") rather than ID: the one character with that
        // name, or the one on this account and megaserver. Two characters can share a name on EU and NA.
        func named(_ name: String, server: String, account: String) -> String? {
            let ids = byName[name] ?? []
            if ids.count == 1 { return ids[0] }
            let here = ids.filter { homes[$0]?.account == account && (server == "Default" || homes[$0]?.server == server) }
            return here.count == 1 ? here[0] : nil
        }
        var shared = 0
        var perCharacter: [String: [String: Setting]] = [:]

        func flatten(_ table: LuaTable, _ path: [LuaKey], _ prefix: [String], depth: Int, into out: inout [String: Setting]) {
            for e in table.entries {
                let label = prefix + [SVReadable.label(e.key, names: names)]
                let here = path + [e.key]
                if let inner = e.value.table {
                    // A color or other small value table counts as one setting.
                    if case .color(let r, let g, let b, let a) = SVReadable.display(e.value, key: e.key, at: path, names: nil) {
                        out[label.joined(separator: " › ")] = Setting(value: e.value, key: e.key, path: here,
                                                                   text: String(format: "%.3f,%.3f,%.3f,%.3f", r, g, b, a))
                    } else if depth > 1 {
                        flatten(inner, here, label, depth: depth - 1, into: &out)
                    }
                    continue
                }
                // Encoded strings are data an addon packs away (what a character knows), not a setting; so are
                // the times an addon stamps its data with.
                if case .string(let text) = e.value, isPacked(text) { continue }
                if case .date = SVReadable.display(e.value, key: e.key, at: path, names: nil) { continue }
                out[label.joined(separator: " › ")] = Setting(value: e.value, key: e.key, path: here, text: plain(e.value))
            }
        }

        func walk(_ table: LuaTable, _ path: [LuaKey]) {
            for e in table.entries {
                guard let inner = e.value.table else { continue }
                let level = SVLevel.of(e.key, at: path)
                if level == .accountWide { shared += inner.count; continue }
                var id: String?
                if path.count == 3, case .string(let k) = e.key {
                    if CharacterID.isID(k) {
                        id = level == .character ? k : nil
                    } else if case .string(let server) = path[1], case .string(let account) = path[2] {
                        id = named(String(k.split(separator: "^").first ?? ""), server: server, account: account)
                    }
                }
                if let id {
                    var settings: [String: Setting] = perCharacter[id] ?? [:]
                    flatten(inner, path + [e.key], [], depth: depth, into: &settings)
                    if !settings.isEmpty { perCharacter[id] = settings }
                    continue
                }
                if path.count < 3 { walk(inner, path + [e.key]) }
            }
        }
        for v in doc.variables { if let t = v.value.table { walk(t, [v.key]) } }
        return perCharacter.isEmpty ? nil : Addon(file: file, shared: shared, characters: perCharacter)
    }

    /// A string an addon packs data into, like LibCharacterKnowledge's `zsU%t#tt#ltw…`, `8mc8r6IIqepWV3…`, or
    /// `00:G00000000000`: no spaces, and it jumps between letters and digits often, or is mostly digits or
    /// symbols. Names like `LibAddonMenu2`, `ZO_ControlName`, or `autoCraft` stay settings.
    public static func isPacked(_ text: String) -> Bool {
        if text.count > 64, !text.contains(" ") { return true }
        guard text.count >= 12, !text.contains(where: \.isWhitespace) else { return false }
        let n = Double(text.count)
        let alnum = text.filter { $0.isLetter || $0.isNumber }.map(\.isNumber)
        let jumps = zip(alnum, alnum.dropFirst()).filter { $0 != $1 }.count
        let digits = text.filter(\.isNumber).count
        let symbols = text.filter { !$0.isLetter && !$0.isNumber && !"_-.".contains($0) }.count
        return Double(jumps) / n >= 0.2 || Double(digits) / n >= 0.5 || Double(symbols) / n >= 0.25
    }

    /// The matrix from every file's addon, with characters grouped by account and megaserver.
    public static func assemble(addons: [Addon], names: SVNameIndex, homes: [String: Home]) -> SettingsMatrix {
        let ids = Set(addons.flatMap { $0.characters.keys })
        let accounts = group(ids, homes: homes, names: names)
        return SettingsMatrix(addons: addons.sorted { $0.file.localizedStandardCompare($1.file) == .orderedAscending },
                              characterIDs: accounts.flatMap(\.characters), accounts: accounts, homes: homes)
    }

    /// Account, then megaserver, then character, each by name; unknown ones last.
    static func group(_ ids: Set<String>, homes: [String: Home], names: SVNameIndex) -> [AccountGroup] {
        let byName: (String, String) -> Bool = { $0.localizedStandardCompare($1) == .orderedAscending }
        func last(_ unknown: String) -> (String, String) -> Bool {
            { a, b in a == unknown ? false : b == unknown ? true : byName(a, b) }
        }
        var tree: [String: [String: [String]]] = [:]
        for id in ids {
            let home = homes[id]
            tree[home?.account ?? unknownAccount, default: [:]][home?.server ?? unknownServer, default: []].append(id)
        }
        return tree.keys.sorted(by: last(unknownAccount)).map { account in
            let servers = tree[account]!
            return AccountGroup(account: account, servers: servers.keys.sorted(by: last(unknownServer)).map { server in
                // Characters no file names come after the named ones.
                ServerGroup(server: server, characters: servers[server]!.sorted {
                    switch (names.characters[$0]?.name, names.characters[$1]?.name) {
                    case (let a?, let b?): byName(a, b)
                    case (nil, nil): $0 < $1
                    case (_, nil): true
                    case (nil, _): false
                    }
                })
            })
        }
    }

    /// "NA Megaserver" -> "NA", for tight places.
    public static func shortServer(_ server: String) -> String {
        server.hasSuffix(" Megaserver") ? String(server.dropLast(" Megaserver".count)) : server
    }

    static func plain(_ v: LuaValue) -> String {
        switch v {
        case .string(let s): s
        case .integer(let n): String(n)
        case .number(let d): String(d)
        case .bool(let b): b ? "true" : "false"
        case .nil: "nil"
        case .table(let t): "table(\(t.count))"
        }
    }
}

// MARK: - Copying settings between characters (S-060)

extension SettingsMatrix {
    /// Where one of `from`'s settings goes for `to`: `to`'s own entry when they have the setting, else the same
    /// place under `to`'s table in the same variable. Nil when `to` keeps nothing in that variable to put it under.
    public func target(file: String, key: String, from: String, to: String) -> [LuaKey]? {
        guard let addon = addons.first(where: { $0.file == file }),
              let source = addon.characters[from]?[key], source.path.count > 4 else { return nil }
        let theirs = addon.characters[to] ?? [:]
        if let own = theirs[key] { return own.path }
        // A character's table is the fourth step: variable › profile or server › account › character.
        let homes = theirs.values.map(\.path).filter { $0.count > 4 && $0[0] == source.path[0] }
        guard let home = homes.first(where: { $0[1] == source.path[1] }) ?? homes.first else { return nil }
        return Array(home.prefix(4)) + source.path.dropFirst(4)
    }
}
