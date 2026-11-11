import Foundation

// The SavedVariables Inspector's model: a lazy tree over a parsed file, the ZO_SavedVars levels
// (server, account, character), and names for the IDs inside. See docs/research/SAVEDVARIABLES.md.

/// The fixed levels ZO_SavedVars stores under: `Var[profile][displayName][character or $AccountWide]`.
/// The first level is the *profile* argument, `"Default"` when the addon gives none. Many addons pass
/// `GetWorldName()`, so it's often a megaserver name, but `Default` means no profile, not an old server
/// (LibSavedVars documents the argument; see docs/research/sv-graph-model-findings.md).
public enum SVLevel: String, Sendable {
    /// The title of account-wide settings. Views sort and compare by it, so it is said in one place.
    public static let everyCharacter = String(localized: "Every character", bundle: .module)

    case profile, account, character, characterName, accountWide

    public var title: String {
        switch self {
        case .profile: "profile"
        case .account: "account"
        case .character: "character"
        case .characterName: String(localized: "character, by name", bundle: .module)
        case .accountWide: String(localized: "every character", bundle: .module)
        }
    }

    static let servers: Set<String> = ["NA Megaserver", "EU Megaserver", "PTS", "Default"]

    /// The megaserver a profile key names; nil for `Default` (no profile, so shared across megaservers)
    /// and for any other profile name.
    public static func megaserver(ofProfile profile: String) -> String? {
        profile != "Default" && servers.contains(profile) ? profile : nil
    }

    /// The level a key stands for, from its shape and depth (`path` is the parent's path, variable first).
    public static func of(_ key: LuaKey, at path: [LuaKey]) -> SVLevel? {
        guard case .string(let s) = key else { return nil }
        if path.count == 1, servers.contains(s) { return .profile }
        if s.hasPrefix("@"), path.count == 2 { return .account }
        if s == "$AccountWide" { return .accountWide }
        if path.count == 3, CharacterID.isID(s) || s.contains("^") { return .character }
        // ZO_SavedVars:New and NewCharacterNameSettings key by the character's name. Only under a profile
        // and an @account, so tables of other shapes aren't mistaken for characters.
        if path.count == 3, !s.isEmpty, !s.hasPrefix("$"),
           case .string(let profile) = path[1], servers.contains(profile),
           case .string(let account) = path[2], account.hasPrefix("@") { return .characterName }
        return nil
    }
}

public enum CharacterID {
    /// Character IDs are 16 digits starting 87, like 8796093036412335 (NA) or 8798292071293572 (EU).
    /// Longer numbers, like the 19-digit item instance IDs some addons key by, are not characters.
    public static func isID(_ s: String) -> Bool {
        s.utf8.count == 16 && s.hasPrefix("87") && s.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }
}

/// One row of the tree: an entry and where it sits. Children are made on first use, so a
/// 100 000-entry table costs nothing until it is opened.
public final class SVNode: Identifiable {
    public let key: LuaKey
    public let value: LuaValue
    /// The parent's path, variable first.
    public let parentPath: [LuaKey]
    public let span: Range<Int>
    /// The path joined, made once: tables and selection read it on every render.
    public let id: String
    public let path: [LuaKey]
    public var bytes: Int { span.count }

    public init(entry: LuaEntry, parentPath: [LuaKey]) {
        key = entry.key; value = entry.value; self.parentPath = parentPath; span = entry.span
        path = parentPath + [entry.key]
        id = Self.id(path)
    }

    public static func id(_ path: [LuaKey]) -> String { path.map(\.description).joined(separator: "\u{1F}") }

    public lazy var children: [SVNode]? = value.table.map { table in
        let path = self.path
        return table.entries.sorted { LuaKey.displayOrder($0.key, $1.key) }.map { SVNode(entry: $0, parentPath: path) }
    }

    public var level: SVLevel? { SVLevel.of(key, at: parentPath) }

    public static func roots(_ doc: SVDocument) -> [SVNode] {
        doc.variables.sorted { LuaKey.displayOrder($0.key, $1.key) }.map { SVNode(entry: $0, parentPath: []) }
    }
}

/// `|H1:item:96175:4:22:0:…:9:0:1:0:10000:0|hName|h`.
public struct ItemLink: Sendable, Equatable {
    public let itemID: Int
    public let subtype: Int
    public let level: Int
    public let style: Int
    public let crafted: Bool
    public let bound: Bool
    public let stolen: Bool
    /// The name written in the link, often empty.
    public let name: String

    public static func parse(_ text: String) -> ItemLink? {
        guard let start = text.range(of: ":item:") else { return nil }
        let rest = text[start.upperBound...]
        let fieldsEnd = rest.range(of: "|h")?.lowerBound ?? rest.endIndex
        let fields = rest[..<fieldsEnd].split(separator: ":", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        guard let id = fields.first, id > 0 else { return nil }
        func f(_ i: Int) -> Int { i < fields.count ? fields[i] : 0 }
        var name = ""
        if fieldsEnd < rest.endIndex {
            let after = rest[rest.index(fieldsEnd, offsetBy: 2)...]
            name = String(after[..<(after.range(of: "|h")?.lowerBound ?? after.endIndex)])
        }
        // Fields after the ID: subtype, level, three enchant fields, nine unused, then
        // style (16), crafted, bound, stolen, condition, instance data.
        return ItemLink(itemID: id, subtype: f(1), level: f(2), style: f(15), crafted: f(16) == 1,
                        bound: f(17) == 1, stolen: f(18) == 1, name: name)
    }

    public static func isLink(_ s: String) -> Bool { s.hasPrefix("|H") && s.contains(":item:") }
}

/// A name for an ID, and where it came from.
public struct SVName: Sendable, Equatable {
    public enum Kind: String, Sendable { case character, account, guild, item, set, zone, map, quest, achievement }

    /// The title of a character ID no file names. Views compare against this, so it is said in one place.
    public static let unknownCharacter = String(localized: "Unknown character", bundle: .module)

    public let title: String
    public let kind: Kind
    /// More about it: "level 22 · style 9", "yours".
    public let detail: String?
    /// "ZO_Ingame › NameChange", "LibSets", "the item link".
    public let source: String
    /// A page about it on UESP, opened in the browser. UESP's data API blocks apps, so nothing is fetched.
    public let uesp: URL?
    /// The ID this names, as saved: "8796093036412335", "3".
    public let id: String?

    public init(title: String, kind: Kind, detail: String? = nil, source: String, uesp: URL? = nil, id: String? = nil) {
        self.title = title; self.kind = kind; self.detail = detail; self.source = source; self.uesp = uesp; self.id = id
    }

    /// "Masisi (8796093036412335)", "Glenumbra (3)": the name people know, with the ID it stands for.
    /// Just the title when it already holds the ID ("Item 29516").
    public var titleWithID: String {
        guard let id, !title.contains(id) else { return title }
        return "\(title) (\(id))"
    }

    /// "Masisi · character"; "Item 29516 · Vestments of the Warlock set" when the title already says the kind.
    public var label: String {
        let kindWord = title.lowercased().contains(kind.rawValue) ? nil : kind.rawValue
        return ([title, kindWord, detail].compactMap { $0 }).joined(separator: " · ")
    }
}

/// Every name the inspector knows: from SavedVariables themselves (characters, your accounts, guilds,
/// LibGuildStore's indexes) and from libraries' data files (sets, zones, quests), read as text.
public struct SVNameIndex: Sendable {
    public var characters: [String: (name: String, source: String)] = [:]
    public var ownAccounts: Set<String> = []
    public var guilds: [Int64: String] = [:]
    /// Guild name -> ID, for LibGuildStore's guild index, which keeps names only.
    public var guildIDs: [String: Int64] = [:]
    public var sets: [Int: String] = [:]
    public var itemSets: [Int: Int] = [:]
    public var zones: [Int: String] = [:]
    public var quests: [Int: String] = [:]
    /// LibGuildStore stores sales with numbers in place of links, accounts, and guilds.
    public var guildStoreLinks: [Int64: String] = [:]
    public var guildStoreAccounts: [Int64: String] = [:]
    public var guildStoreGuilds: [Int64: String] = [:]

    /// Character IDs a file names with the game's own say (ZO_Ingame's NameChange): they replace a
    /// name an earlier file gave. Only used while merging files.
    var overriding: Set<String> = []

    public init() {}

    /// Builds the index from parsed files (keyed by file name) and the libraries in `addons`.
    public static func build(documents: [String: SVDocument], addons: URL?) -> SVNameIndex {
        var index = SVNameIndex()
        for (file, doc) in documents.sorted(by: { $0.key < $1.key }) { index.merge(collect(file: file, document: doc)) }
        let companion = documents.first { CompanionData.isCompanionFile($0.key) }
        let snapshot = companion.flatMap { CompanionData.snapshot($0.value, file: $0.key) }
        index.finish(roster: snapshot?.characters ?? companion.map { CompanionData.roster($0.value) },
                     addons: addons,
                     guilds: snapshot.map { Dictionary($0.guilds.map { ($0.key, $0.value.name) }, uniquingKeysWith: { _, n in n }) } ?? [:])
        return index
    }

    /// One file's names, to merge in file-name order: the same index as reading the files one after another,
    /// without keeping every file in memory.
    public static func collect(file: String, document: SVDocument) -> SVNameIndex {
        var index = SVNameIndex()
        for variable in document.variables { index.collect(variable.value, path: [variable.key], file: file) }
        return index
    }

    /// Adds the names of a file that comes after the ones merged so far.
    public mutating func merge(_ later: SVNameIndex) {
        for (id, name) in later.characters where characters[id] == nil || later.overriding.contains(id) { characters[id] = name }
        ownAccounts.formUnion(later.ownAccounts)
        guilds.merge(later.guilds) { _, new in new }
        guildStoreLinks.merge(later.guildStoreLinks) { _, new in new }
        guildStoreAccounts.merge(later.guildStoreAccounts) { _, new in new }
        guildStoreGuilds.merge(later.guildStoreGuilds) { _, new in new }
    }

    /// Changes when any name changes, to tell whether results that depend on names can be kept. Only
    /// meaningful within one run of the app.
    public var fingerprint: Int {
        func sum<K: Hashable, V: Hashable>(_ d: [K: V]) -> Int {
            d.reduce(d.count) { total, entry in var h = Hasher(); h.combine(entry.key); h.combine(entry.value); return total &+ h.finalize() }
        }
        var h = Hasher()
        h.combine(sum(characters.mapValues { $0.name }))
        h.combine(ownAccounts)
        for part in [sum(guilds), sum(guildIDs), sum(sets), sum(itemSets), sum(zones), sum(quests),
                     sum(guildStoreLinks), sum(guildStoreAccounts), sum(guildStoreGuilds)] { h.combine(part) }
        return h.finalize()
    }

    /// After every file: the companion's roster, the libraries' names, and guild IDs by name.
    public mutating func finish(roster: [String: CompanionCharacter]?, addons: URL?,
                                guilds companionGuilds: [Int64: String] = [:]) {
        overriding = []
        // The companion's roster is the game's own list: its names win.
        for (id, c) in roster ?? [:] { characters[id] = (c.name, String(localized: "MacMinion Companion", bundle: .module)) }
        for (id, name) in companionGuilds { guilds[id] = name }
        if let addons { loadLibraries(addons) }
        guildIDs = Dictionary(guilds.map { ($1, $0) }, uniquingKeysWith: min)
    }

    // MARK: From SavedVariables

    mutating func collect(_ value: LuaValue, path: [LuaKey], file: String) {
        guard let table = value.table else { return }
        let parentKey = path.last?.description ?? ""
        let variable = path.first?.description ?? ""
        // LibGuildStore's reverse indexes: link, account, or guild name -> number.
        if variable.hasPrefix("GS"), variable.hasSuffix("DataSavedVariables"), path.count == 2 {
            for e in table.entries {
                guard case .string(let name) = e.key, case .integer(let n) = e.value else { continue }
                switch parentKey {
                case "itemLink": guildStoreLinks[n] = name
                case "accountNames": guildStoreAccounts[n] = name
                case "guildNames": guildStoreGuilds[n] = name
                default: break
                }
            }
        }
        var guildID: Int64?, guildName: String?
        for e in table.entries {
            switch (e.key, e.value) {
            case (.string(let k), .string(let name)) where CharacterID.isID(k) && !name.isEmpty:
                // A table of character ID -> name, like ZO_Ingame's NameChange.
                if characters[k] == nil || file == "ZO_Ingame.lua" {
                    characters[k] = (name, "\(file.replacingOccurrences(of: ".lua", with: "")) › \(parentKey)")
                    if file == "ZO_Ingame.lua" { overriding.insert(k) }
                }
            case (.string("$LastCharacterName"), .string(let name)) where CharacterID.isID(parentKey) && characters[parentKey] == nil:
                characters[parentKey] = (name, "\(file.replacingOccurrences(of: ".lua", with: "")) › $LastCharacterName")
            case (.string("guildId"), .integer(let id)): guildID = id
            case (.string("guildName"), .string(let name)): guildName = name
            default: break
            }
            if case .string(let k) = e.key, k.hasPrefix("@"), path.count == 2,
               SVLevel.servers.contains(parentKey) { ownAccounts.insert(k) }
            collect(e.value, path: path + [e.key], file: file)
        }
        if let guildName {
            if let guildID { guilds[guildID] = guildName }
            else if case .integer(let id)? = path.last { guilds[id] = guildName } // visitedEUTraders > 487424 > guildName
        }
    }

    // MARK: From libraries

    mutating func loadLibraries(_ addons: URL) {
        let folders = Self.folders(named: ["LibSets", "LibZone", "LibQuestData"], in: addons)
        if let libSets = folders["LibSets"] {
            let data = libSets.appending(path: "Data")
            if let names = try? Data(contentsOf: data.appending(path: "LibSets_Data_SetNames.lua")),
               let table = SVDocument.table(in: names, after: "[LIBSETS_TABLEKEY_SETNAMES]") {
                for e in table.entries {
                    guard case .integer(let id) = e.key, let name = e.value.table?["en"]?.string else { continue }
                    sets[Int(id)] = name
                }
            }
            if let items = try? Data(contentsOf: data.appending(path: "LibSets_Data_SetItemIds.lua")),
               let table = SVDocument.table(in: items, after: "[LIBSETS_TABLEKEY_SETITEMIDS]") {
                for e in table.entries {
                    guard case .integer(let set) = e.key, let list = e.value.table else { continue }
                    for item in list.entries {
                        switch item.value {
                        case .integer(let id): itemSets[Int(id)] = Int(set)
                        case .string(let range): // "29513,3": 29513 and the 3 IDs after it
                            let parts = range.split(separator: ",").compactMap { Int($0) }
                            if parts.count == 2, parts[1] < 10_000 { for id in parts[0]...(parts[0] + parts[1]) { itemSets[id] = Int(set) } }
                        default: break
                        }
                    }
                }
            }
        }
        if let libZone = folders["LibZone"], let data = try? Data(contentsOf: libZone.appending(path: "LibZone_Data.lua")),
           let table = SVDocument.table(in: data, after: "[\"en\"] =") {
            for e in table.entries { if case .integer(let id) = e.key, let name = e.value.string { zones[Int(id)] = name } }
        }
        if let libQuest = folders["LibQuestData"],
           let data = try? Data(contentsOf: libQuest.appending(path: "quest_names/LibQuestData_QuestNames_en.lua")),
           let table = SVDocument.table(in: data, after: "quest_names[\"en\"] =") {
            for e in table.entries { if case .integer(let id) = e.key, let name = e.value.string { quests[Int(id)] = name } }
        }
    }

    /// Addon folders with these names, up to three folders deep, as the game loads them.
    static func folders(named names: Set<String>, in addons: URL) -> [String: URL] {
        let fm = FileManager.default
        var found: [String: URL] = [:]
        func walk(_ dir: URL, _ level: Int) {
            guard level <= 3, found.count < names.count, let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
            for name in items where !name.hasPrefix(".") {
                let url = dir.appending(path: name, directoryHint: .isDirectory)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
                if names.contains(name), found[name] == nil { found[name] = url }
                walk(url, level + 1)
            }
        }
        walk(addons, 1)
        return found
    }

    // MARK: Naming

    /// A name for a key: a character ID, an account, or an item link used as a key.
    public func name(forKey key: LuaKey, at path: [LuaKey]) -> SVName? {
        guard case .string(let s) = key else { return nil }
        return name(forString: s)
    }

    /// A name for a value, from its shape or the key it sits under.
    public func name(forValue value: LuaValue, key: LuaKey, at path: [LuaKey]) -> SVName? {
        let keyName = key.description
        let variable = path.first?.description ?? ""
        switch value {
        case .string(let s):
            return name(forString: s)
        case .integer(let n):
            if variable.hasPrefix("GS"), variable.hasSuffix("DataSavedVariables") {
                switch keyName {
                case "itemLink": if let link = guildStoreLinks[n] { return item(link, source: String(localized: "LibGuildStore's link index", bundle: .module)) }
                case "seller", "buyer": if let account = guildStoreAccounts[n] { return accountName(account, source: String(localized: "LibGuildStore's account index", bundle: .module)) }
                case "guild": if let guild = guildStoreGuilds[n] { return SVName(title: guild, kind: .guild, source: String(localized: "LibGuildStore's guild index", bundle: .module), id: String(n)) }
                default: break
                }
            }
            let id = Int(n)
            switch keyName {
            case "zoneId", "zoneID", "zone":
                return zones[id].map { SVName(title: $0, kind: .zone, source: "LibZone", uesp: Self.search($0), id: String(n)) }
            case "questId", "questID":
                return quests[id].map { SVName(title: $0, kind: .quest, source: "LibQuestData", uesp: Self.search("Online:\($0)"), id: String(n)) }
            case "setId", "setID":
                return sets[id].map { SVName(title: $0, kind: .set, source: "LibSets", uesp: Self.search("Online:\($0)"), id: String(n)) }
            case "itemId", "itemID":
                return itemName(id: id, link: nil)
            case "guildId", "guildID":
                return guilds[n].map { SVName(title: $0, kind: .guild, source: String(localized: "guild tables in SavedVariables", bundle: .module), id: String(n)) }
            case "achievementId", "achievementID":
                return SVName(title: "Achievement \(id)", kind: .achievement, source: String(localized: "the key name", bundle: .module),
                              uesp: Self.search(String(localized: "Online achievement \(id)", bundle: .module)))
            case "mapId", "mapID":
                return SVName(title: "Map \(id)", kind: .map, source: String(localized: "the key name", bundle: .module))
            default:
                return nil
            }
        default:
            return nil
        }
    }

    func name(forString s: String) -> SVName? {
        if CharacterID.isID(s) {
            if let c = characters[s] { return SVName(title: c.name, kind: .character, source: c.source, id: s) }
            return SVName(title: SVName.unknownCharacter, kind: .character, source: String(localized: "no file names this ID", bundle: .module), id: s)
        }
        if s.hasPrefix("@"), s.count > 1, !s.contains(" ") { return accountName(s, source: String(localized: "the name itself", bundle: .module)) }
        if ItemLink.isLink(s) { return item(s, source: String(localized: "the item link", bundle: .module)) }
        return nil
    }

    func accountName(_ account: String, source: String) -> SVName {
        SVName(title: account, kind: .account, detail: ownAccounts.contains(account) ? "yours" : nil, source: source)
    }

    func item(_ text: String, source: String) -> SVName? {
        guard let link = ItemLink.parse(text) else { return nil }
        guard var named = itemName(id: link.itemID, link: link) else { return nil }
        var details = [named.detail, "level \(link.level)"].compactMap { $0 }
        if link.style > 0 { details.append("style \(link.style)") }
        if link.bound { details.append("bound") }
        if link.crafted { details.append("crafted") }
        named = SVName(title: named.title, kind: .item, detail: details.joined(separator: " · "),
                       source: named.detail == nil ? source : String(localized: "\(source); set from LibSets", bundle: .module), uesp: named.uesp)
        return named
    }

    func itemName(id: Int, link: ItemLink?) -> SVName? {
        let set = itemSets[id].flatMap { sets[$0] }
        let title = link.flatMap { $0.name.isEmpty ? nil : Self.cleanItemName($0.name) } ?? "Item \(id)"
        return SVName(title: title, kind: .item, detail: set.map { "\($0) set" },
                      source: set == nil ? String(localized: "the item ID", bundle: .module) : "LibSets",
                      uesp: URL(string: "https://esoitem.uesp.net/itemLink.php?itemid=\(id)"), id: String(id))
    }

    /// ESO writes some names with a gender suffix: "Masisi^Fx" -> "Masisi".
    static func cleanItemName(_ s: String) -> String { s.split(separator: "^").first.map(String.init) ?? s }

    static func search(_ text: String) -> URL? {
        var c = URLComponents(string: "https://en.uesp.net/w/index.php")
        c?.queryItems = [URLQueryItem(name: "search", value: text)]
        return c?.url
    }
}
