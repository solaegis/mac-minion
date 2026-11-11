import Foundation

/// What ESO Mac Minion, the in-game addon, wrote under `EsoMacMinion_Data`.
/// The game saves that table to `SavedVariables/EsoMacMinion.lua` (the addon folder name).
/// Seeds and older docs also use `EsoMacMinion_Data.lua`. See docs/COMPANION-ADDON.md.
public struct CompanionCharacter: Sendable, Equatable {
    public let id: String
    public let name: String
    public let server: String
    public let account: String
    public let classID: Int?
    public let raceID: Int?
    public let alliance: Int?
    public let level: Int?
    public let champion: Int?
    public let lastPlayed: Date?
    /// Every name this ID has had, with when the companion first saw it. Two or more means a rename.
    public var names: [String: Date] = [:]

    /// Names this character had before its current one, oldest first.
    public var previousNames: [String] {
        names.filter { $0.key != name }.sorted { $0.value < $1.value }.map { $0.key }
    }

    /// "Nightblade", from the game's class IDs.
    public var className: String? { classID.flatMap { Self.classes[$0] } }
    public var raceName: String? { raceID.flatMap { Self.races[$0] } }

    static let classes = [1: "Dragonknight", 2: "Sorcerer", 3: "Nightblade", 4: "Warden", 5: "Necromancer", 6: "Templar", 117: "Arcanist"]
    static let races = [1: "Breton", 2: "Redguard", 3: "Orc", 4: "Dark Elf", 5: "Nord", 6: "Argonian", 7: "High Elf", 8: "Wood Elf",
                        9: "Khajiit", 10: "Imperial"]
}

public struct CompanionEnv: Sendable, Equatable {
    public let apiVersion: Int?
    public let gameVersion: String?
    public let server: String?
    public let language: String?
    public let companionVersion: String?
}

public struct CompanionAddonState: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let title: String?
    public let version: String?
    public let enabled: Bool
    public let state: String
    public let outOfDate: Bool
    public let isLibrary: Bool
    public let missing: [String]
    public let loadMs: Int?
    /// The folder the game loaded it from when it isn't the usual `user:/AddOns/<name>/`, like
    /// `user:/AddOns/CharacterKnowledge/LibCharacterKnowledge/`. Nil means the usual folder.
    public var rootPath: String? = nil
    /// Every installed folder with this name when there is more than one; the game loads one of them.
    public var copies: [String] = []

    public var loaded: Bool { state == "loaded" }
    public var failedToLoad: Bool { state == "missing" || !missing.isEmpty }
}

public struct CompanionError: Sendable, Equatable {
    public let addon: String?
    public let at: Date?
    public let count: Int
    public let character: String?
    public let message: String
}

public struct CompanionGuild: Sendable, Equatable {
    public let id: Int64
    public let name: String
    public let members: Int?
    public let rank: String?
    public let server: String?
}

/// What one character had switched off when it last logged in.
public struct CompanionEnabled: Sendable, Equatable {
    public let at: Date?
    /// Addons this character turned off.
    public let disabled: [String]
    /// Addons turned on that didn't load (missing or outdated dependencies, version mismatch).
    public let notLoaded: [String]
}

/// One SavedVariables global as the companion saw it in the running game: names and shape, no values.
public struct CompanionSVLayout: Sendable, Equatable {
    public let name: String
    /// The ZO_SavedVars constructor seen (`NewAccountWide`, `New`, …), when the call was captured.
    public let ctor: String?
    public let profile: String?
    public let namespace: String?
    /// `account`, `characterId`, or `characterName`, from the constructor.
    public let keyType: String?
    /// The version the addon passed, as written: addons use integers, decimals (`1.511`), and strings (`"1.0"`).
    public let version: String?
    public let addon: String?
    /// `wrap`, `scan`, or `wrap+scan`.
    public let source: String?
    public let zoShaped: Bool
    /// profile -> account -> character keys (capped), from the requested scan.
    public let tree: [String: [String: [String]]]
    /// Server names used as keys under `$AccountWide`, by profile and account.
    public let serverNamespaces: [String: [String: [String]]]
    public let pathCount: Int?
}

/// When the companion last read the globals MacMinion asked for.
public struct CompanionLayoutScan: Sendable, Equatable {
    public let at: Date?
    public let requested: Int
    public let found: Int
    public let missing: [String]
}

/// One login's worth of what only the running game knows.
public struct CompanionSnapshot: Sendable, Equatable {
    public let file: String
    public let schema: Int?
    /// False when `schema` is set and is not the shape this build reads.
    public let schemaKnown: Bool
    public let written: Date?
    public let env: CompanionEnv?
    public let characters: [String: CompanionCharacter]
    public let addons: [String: CompanionAddonState]
    public let errors: [CompanionError]
    public let guilds: [Int64: CompanionGuild]
    /// Section names left unread because the schema is newer than this build.
    public let skipped: [String]
    /// Character ID -> what it had switched off at its last login.
    public var enabledBy: [String: CompanionEnabled] = [:]
    /// SavedVariables global -> its layout in the running game.
    public var layouts: [String: CompanionSVLayout] = [:]
    public var layoutScan: CompanionLayoutScan? = nil
    /// The globals MacMinion last asked the companion to read.
    public var requestedSvGlobals: [String] = []
}

public enum CompanionData {
    /// Seed and docs name. The live game writes `EsoMacMinion.lua`.
    public static let fileName = "EsoMacMinion_Data.lua"
    public static let fileNames = ["EsoMacMinion.lua", "EsoMacMinion_Data.lua"]
    public static let folderName = "EsoMacMinion"
    public static let displayName = "ESO Mac Minion"
    public static let variable = "EsoMacMinion_Data"
    public static let knownSchema = 1
    public static let recommendReason =
        String(localized: "Writes the roster, which addons actually loaded, and Lua errors, so MacMinion can use what only the running game knows.", bundle: .module)

    public static func isCompanionFile(_ name: String) -> Bool {
        fileNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    public static func isCompanionFolder(_ name: String) -> Bool {
        name.caseInsensitiveCompare(folderName) == .orderedSame
    }

    /// The newest readable snapshot in a SavedVariables folder.
    public static func read(in folder: URL) -> CompanionSnapshot? {
        let snaps = fileNames.compactMap { name -> CompanionSnapshot? in
            let url = folder.appending(path: name)
            guard FileManager.default.fileExists(atPath: url.path), let doc = try? SVDocument.read(url) else { return nil }
            return snapshot(doc, file: name)
        }
        return snaps.max { ($0.written ?? .distantPast) < ($1.written ?? .distantPast) }
    }

    /// The roster on every server and account in the file, keyed by character ID.
    public static func roster(_ doc: SVDocument) -> [String: CompanionCharacter] {
        snapshot(doc)?.characters ?? [:]
    }

    public static func snapshot(_ doc: SVDocument, file: String = fileName) -> CompanionSnapshot? {
        guard let root = doc[variable]?.table else { return nil }
        var schema: Int?
        var written: Date?
        var env: CompanionEnv?
        var characters: [String: CompanionCharacter] = [:]
        var addons: [String: CompanionAddonState] = [:]
        var errors: [CompanionError] = []
        var guilds: [Int64: CompanionGuild] = [:]
        var enabledBy: [String: CompanionEnabled] = [:]
        var addonsStamp = Int.min
        var layouts: [String: CompanionSVLayout] = [:]
        var layoutScan: CompanionLayoutScan?
        var requested: [String] = []

        for server in root.entries {
            for account in server.value.table?.entries ?? [] {
                guard let wide = account.value.table?["$AccountWide"]?.table else { continue }
                if schema == nil { schema = int(wide["schema"]) }
                if written == nil, let stamp = int(wide["written"]) {
                    written = Date(timeIntervalSince1970: TimeInterval(stamp))
                }
                if env == nil { env = parseEnv(wide["env"]?.table) }
                for (id, character) in parseCharacters(wide["characters"]?.table, server: server.key.description,
                                                       account: account.key.description) {
                    characters[id] = character
                }
                // The addon list is the same on every megaserver; newer companions keep it only in the block
                // written last. For older files with a list in every block, take the newest block's.
                if let list = wide["addons"]?.table {
                    let stamp = int(wide["written"]) ?? 0
                    if stamp >= addonsStamp { addons = parseAddons(list); addonsStamp = stamp }
                }
                if errors.isEmpty { errors = parseErrors(wide["errors"]?.table) }
                for (id, guild) in parseGuilds(wide["guilds"]?.table) { guilds[id] = guild }
                for (id, row) in parseEnabledBy(wide["enabledBy"]?.table) {
                    if let old = enabledBy[id], (old.at ?? .distantPast) > (row.at ?? .distantPast) { continue }
                    enabledBy[id] = row
                }
                let layoutTable = wide["layouts"]?.table
                for (name, layout) in parseLayouts(layoutTable?["sv"]?.table) where layouts[name] == nil { layouts[name] = layout }
                if layoutScan == nil { layoutScan = parseLayoutScan(layoutTable?["scanned"]?.table) }
                if requested.isEmpty {
                    requested = (wide["lookups"]?.table?["requests"]?.table?["svGlobals"]?.table?.entries ?? []).compactMap(\.value.string)
                }
            }
        }

        let known = schema == nil || schema == knownSchema
        var snapshot = CompanionSnapshot(file: file, schema: schema, schemaKnown: known, written: written, env: env,
                                         characters: characters, addons: addons, errors: errors, guilds: guilds,
                                         skipped: known ? [] : [String(localized: "future schema \(schema ?? 0)", bundle: .module)])
        snapshot.enabledBy = enabledBy
        snapshot.layouts = layouts
        snapshot.layoutScan = layoutScan
        snapshot.requestedSvGlobals = requested
        return snapshot
    }

    /// Load failures, out-of-date addons, and Lua errors from the last session.
    public static func problems(from snapshot: CompanionSnapshot) -> [SVProblem] {
        var out: [SVProblem] = []
        let file = snapshot.file
        if !snapshot.schemaKnown {
            out.append(SVProblem(file: file, path: [.string(variable), .string("schema")], kind: .unknownSchema,
                                 severity: .note,
                                 message: String(localized: "Schema \(snapshot.schema.map(String.init) ?? "?") is newer than this MacMinion. Roster and other known sections are still read; \(snapshot.skipped.joined(separator: ", ")) skipped.", bundle: .module)))
        }
        for addon in snapshot.addons.values.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            if addon.failedToLoad {
                let missing = addon.missing.isEmpty ? addon.state : String(localized: "missing \(addon.missing.joined(separator: ", "))", bundle: .module)
                out.append(SVProblem(file: file, path: [.string(variable), .string("addons"), .string(addon.name)],
                                     kind: .didntLoad, severity: .warning,
                                     message: String(localized: "\(addon.title ?? addon.name) didn't load: \(missing).", bundle: .module)).with(addon: addon.name))
            } else if addon.outOfDate || addon.state == "outdated" {
                out.append(SVProblem(file: file, path: [.string(variable), .string("addons"), .string(addon.name)],
                                     kind: .outOfDateAddon, severity: .warning,
                                     message: String(localized: "\(addon.title ?? addon.name) is out of date for this game version.", bundle: .module)).with(addon: addon.name))
            }
            if let ms = addon.loadMs, ms >= 1_000 {
                let seconds = Double(ms) / 1_000
                out.append(SVProblem(file: file, path: [.string(variable), .string("addons"), .string(addon.name)],
                                     kind: .slowLoad, severity: .note,
                                     message: String(localized: "\(addon.title ?? addon.name) took \(seconds.formatted(.number.precision(.fractionLength(1)))) s to load last login.", bundle: .module)).with(addon: addon.name))
            }
        }
        for (index, error) in snapshot.errors.enumerated() {
            let name = error.addon ?? String(localized: "An addon", bundle: .module)
            let times = error.count == 1 ? String(localized: "once", bundle: .module) : String(localized: "\(error.count) times", bundle: .module)
            // The error's place in the list, so every error has its own id and opens at its own entry.
            out.append(SVProblem(file: file, path: [.string(variable), .string("errors"), .integer(Int64(index + 1))],
                                 kind: .luaError, severity: error.count >= 5 ? .error : .warning,
                                 message: String(localized: "\(name) threw Lua errors \(times) last session.", bundle: .module) + " " + error.message).with(addon: error.addon))
        }
        return out
    }

    // MARK: Parse

    private static func parseEnv(_ table: LuaTable?) -> CompanionEnv? {
        guard let table else { return nil }
        return CompanionEnv(apiVersion: int(table["apiVersion"]), gameVersion: table["gameVersion"]?.string,
                            server: table["server"]?.string, language: table["language"]?.string,
                            companionVersion: table["companionVersion"]?.string)
    }

    private static func parseCharacters(_ table: LuaTable?, server: String, account: String) -> [String: CompanionCharacter] {
        var out: [String: CompanionCharacter] = [:]
        for entry in table?.entries ?? [] {
            guard case .string(let id) = entry.key, let c = entry.value.table, let name = c["name"]?.string else { continue }
            var character = CompanionCharacter(id: id, name: name, server: server, account: account,
                                               classID: int(c["class"]), raceID: int(c["race"]), alliance: int(c["alliance"]),
                                               level: int(c["level"]), champion: int(c["champion"]),
                                               lastPlayed: int(c["lastPlayed"]).map { Date(timeIntervalSince1970: TimeInterval($0)) })
            for seen in c["names"]?.table?.entries ?? [] {
                guard case .string(let old) = seen.key else { continue }
                character.names[old] = Date(timeIntervalSince1970: TimeInterval(int(seen.value) ?? 0))
            }
            out[id] = character
        }
        return out
    }

    private static func parseAddons(_ table: LuaTable?) -> [String: CompanionAddonState] {
        var out: [String: CompanionAddonState] = [:]
        for entry in table?.entries ?? [] {
            guard case .string(let name) = entry.key, let c = entry.value.table else { continue }
            var missing: [String] = []
            for dep in c["missing"]?.table?.entries ?? [] {
                if let s = dep.value.string { missing.append(s) }
            }
            let copies = (c["copies"]?.table?.entries ?? []).compactMap(\.value.string)
            out[name] = CompanionAddonState(name: name, title: c["title"]?.string, version: c["version"]?.string,
                                            // Left out when they're the default: on, and loaded.
                                            enabled: bool(c["enabled"]) ?? true, state: c["state"]?.string ?? "loaded",
                                            outOfDate: bool(c["outOfDate"]) ?? false, isLibrary: bool(c["isLibrary"]) ?? false,
                                            missing: missing, loadMs: int(c["loadMs"]),
                                            rootPath: c["rootPath"]?.string, copies: copies)
        }
        return out
    }

    private static func parseErrors(_ table: LuaTable?) -> [CompanionError] {
        (table?.entries ?? []).compactMap { entry in
            guard let c = entry.value.table, let message = c["message"]?.string, !message.isEmpty else { return nil }
            return CompanionError(addon: c["addon"]?.string, at: int(c["at"]).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                                  count: int(c["count"]) ?? 1, character: c["character"]?.string, message: message)
        }
    }

    private static func parseGuilds(_ table: LuaTable?) -> [Int64: CompanionGuild] {
        var out: [Int64: CompanionGuild] = [:]
        for entry in table?.entries ?? [] {
            guard let c = entry.value.table, let name = c["name"]?.string else { continue }
            let id: Int64? = {
                if case .integer(let n) = entry.key { return n }
                if case .string(let s) = entry.key { return Int64(s) }
                return int(c["id"]).map(Int64.init)
            }()
            guard let id else { continue }
            out[id] = CompanionGuild(id: id, name: name, members: int(c["members"]), rank: c["rank"]?.string,
                                     server: c["server"]?.string)
        }
        return out
    }

    private static func text(_ value: LuaValue?) -> String? {
        switch value {
        case .string(let s)?: s
        case .integer(let n)?: String(n)
        case .number(let d)?: String(d)
        default: nil
        }
    }

    private static func strings(_ value: LuaValue?) -> [String] {
        (value?.table?.entries ?? []).compactMap(\.value.string)
    }

    private static func date(_ value: LuaValue?) -> Date? {
        int(value).map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    private static func parseEnabledBy(_ table: LuaTable?) -> [String: CompanionEnabled] {
        var out: [String: CompanionEnabled] = [:]
        for entry in table?.entries ?? [] {
            guard case .string(let id) = entry.key, let c = entry.value.table else { continue }
            out[id] = CompanionEnabled(at: date(c["at"]), disabled: strings(c["disabled"]), notLoaded: strings(c["notLoaded"]))
        }
        return out
    }

    private static func parseLayouts(_ table: LuaTable?) -> [String: CompanionSVLayout] {
        var out: [String: CompanionSVLayout] = [:]
        for entry in table?.entries ?? [] {
            guard case .string(let name) = entry.key, let c = entry.value.table else { continue }
            var tree: [String: [String: [String]]] = [:]
            var namespaces: [String: [String: [String]]] = [:]
            for profile in c["tree"]?.table?.entries ?? [] {
                for account in profile.value.table?.entries ?? [] {
                    let p = profile.key.description, a = account.key.description
                    tree[p, default: [:]][a] = strings(account.value.table?["keys"])
                    let servers = strings(account.value.table?["serverNamespaces"])
                    if !servers.isEmpty { namespaces[p, default: [:]][a] = servers }
                }
            }
            out[name] = CompanionSVLayout(name: name, ctor: c["ctor"]?.string, profile: c["profile"]?.string,
                                          namespace: c["namespace"]?.string, keyType: c["keyType"]?.string,
                                          version: text(c["version"]), addon: c["addon"]?.string, source: c["source"]?.string,
                                          zoShaped: bool(c["zoShaped"]) ?? false, tree: tree, serverNamespaces: namespaces,
                                          pathCount: int(c["pathCount"]))
        }
        return out
    }

    private static func parseLayoutScan(_ table: LuaTable?) -> CompanionLayoutScan? {
        guard let table else { return nil }
        return CompanionLayoutScan(at: date(table["at"]), requested: int(table["requested"]) ?? 0,
                                   found: int(table["found"]) ?? 0, missing: strings(table["missing"]))
    }

    private static func int(_ value: LuaValue?) -> Int? {
        switch value {
        case .integer(let n)?: Int(n)
        case .number(let d)?: Int(d)
        default: nil
        }
    }

    private static func bool(_ value: LuaValue?) -> Bool? {
        if case .bool(let b)? = value { return b }
        return nil
    }
}
