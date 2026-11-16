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
    /// Zone for the character that was logged in when the companion wrote (from GetZoneId).
    public var zoneId: Int? = nil
    public var zoneName: String? = nil
    /// GetCharacterInfo location ID for roster rows (not a zone ID).
    public var locationId: Int? = nil
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
    public var addonsTotal: Int? = nil
    public var addonsLoaded: Int? = nil
    public var addonsDisabled: Int? = nil
    /// From AddOnManager:GetLoadOutOfDateAddOns (the old allow-out-of-date CVar/UI is gone).
    public var loadOutOfDateAddOns: Bool? = nil
}

public struct CompanionAnswer: Sendable, Equatable {
    public let key: String
    public let name: String?
    public let quality: Int?
    public let set: Int?
    public let icon: String?
    /// The companion looked this ID up and the game had nothing for it (`{ missing = true }`).
    public var missing: Bool = false
    /// When the companion answered.
    public var at: Date? = nil
}

public struct CompanionSession: Sendable, Equatable {
    public let character: String?
    public let loginAt: Date?
    public let logoutAt: Date?
    public let zoneId: Int?

    public var played: TimeInterval? {
        guard let loginAt, let logoutAt, logoutAt >= loginAt else { return nil }
        return logoutAt.timeIntervalSince(loginAt)
    }
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
    /// Numeric AddOnManager:GetAddOnVersion when the companion recorded it.
    public var addOnVersion: Int? = nil
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
    public var firstAt: Date? = nil
    public var lastAt: Date? = nil
    public var session: Date? = nil
    public var addonVersion: Int? = nil
    public let count: Int
    public let character: String?
    public let message: String
    /// Where its newest occurrence is in the file, variable first (server, account, `$AccountWide`,
    /// `errors`, index), as the Inspector opens it. Empty when not read from a file.
    public var path: [LuaKey] = []
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
    /// The defaults table the addon passed the constructor, copied in the game with constants resolved (S-070).
    public var defaults: CompanionDefaults? = nil
}

/// An addon's defaults as the companion copied them; `truncated` when its size cap cut the copy short.
public struct CompanionDefaults: Sendable, Equatable {
    public let table: LuaTable
    public let truncated: Bool

    public init(table: LuaTable, truncated: Bool) {
        self.table = table
        self.truncated = truncated
    }

    public static func == (a: Self, b: Self) -> Bool { a.table === b.table && a.truncated == b.truncated }
}

/// When the companion last read the globals MacMinion asked for.
public struct CompanionLayoutScan: Sendable, Equatable {
    public let at: Date?
    public let requested: Int
    public let found: Int
    public let missing: [String]
}

/// Frame rate, latency, Lua memory, and load-screen times the companion sampled (`perf`).
public struct CompanionPerf: Sendable, Equatable {
    public struct Sample: Sendable, Equatable {
        public let at: Date?
        public let fps: Int?
        /// Latency in milliseconds.
        public let ms: Int?
        /// Lua memory in KB (`collectgarbage("count")`).
        public let luaKB: Int?
        public let zoneId: Int?
    }

    public struct Load: Sendable, Equatable {
        public let at: Date?
        public let seconds: Double
        public let zoneId: Int?
    }

    /// Oldest first.
    public var samples: [Sample] = []
    /// Oldest first.
    public var loads: [Load] = []

    public init(samples: [Sample] = [], loads: [Load] = []) {
        self.samples = samples
        self.loads = loads
    }

    public var medianFPS: Double? { Self.median(samples.compactMap(\.fps).map(Double.init)) }
    public var medianLatency: Double? { Self.median(samples.compactMap(\.ms).map(Double.init)) }
    /// Lua memory at the newest sample that has it, in KB.
    public var latestLuaKB: Int? { samples.last { $0.luaKB != nil }?.luaKB }
    public var medianLoad: Double? { Self.median(loads.map(\.seconds)) }
    public var slowestLoad: Double? { loads.map(\.seconds).max() }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted(), mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
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
    /// Name lookup answers keyed `kind:id`.
    public var answers: [String: CompanionAnswer] = [:]
    public var sessions: [CompanionSession] = []
    /// Last deactivate stamp from the companion (fresher than `written` for "log in once").
    public var savedAt: Date? = nil
    /// Performance samples and load times from every block; nil when there are none.
    public var perf: CompanionPerf? = nil
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
        // Collect every $AccountWide so written/env/layouts come from the newest logout, not file order.
        var blocks: [(stamp: Int, server: String, account: String, path: [LuaKey], wide: LuaTable)] = []
        for server in root.entries {
            for account in server.value.table?.entries ?? [] {
                guard let wide = account.value.table?["$AccountWide"]?.table else { continue }
                blocks.append((int(wide["written"]) ?? 0, server.key.description, account.key.description,
                               [.string(variable), server.key, account.key, .string("$AccountWide")], wide))
            }
        }
        guard !blocks.isEmpty else { return nil }

        let newestFirst = blocks.sorted { $0.stamp > $1.stamp }
        let best = newestFirst[0]
        let schema = int(best.wide["schema"]) ?? newestFirst.compactMap { int($0.wide["schema"]) }.first
        let written = best.stamp > 0 ? Date(timeIntervalSince1970: TimeInterval(best.stamp)) : nil
        let env = parseEnv(best.wide["env"]?.table)
            ?? newestFirst.lazy.compactMap { parseEnv($0.wide["env"]?.table) }.first
        let savedAt = date(best.wide["savedAt"])
            ?? newestFirst.lazy.compactMap { date($0.wide["savedAt"]) }.first

        var characters: [String: CompanionCharacter] = [:]
        var addons: [String: CompanionAddonState] = [:]
        var guilds: [Int64: CompanionGuild] = [:]
        var enabledBy: [String: CompanionEnabled] = [:]
        var addonsStamp = Int.min
        var layouts: [String: CompanionSVLayout] = [:]
        var layoutScan: CompanionLayoutScan?
        var requested: [String] = []
        var answers: [String: CompanionAnswer] = [:]
        var sessions: [CompanionSession] = []
        var seenSessions: Set<String> = []
        var perf = CompanionPerf()
        var seenSamples: Set<String> = [], seenLoads: Set<String> = []
        var mergedErrors: [String: CompanionError] = [:]

        for block in newestFirst {
            let wide = block.wide
            for (id, character) in parseCharacters(wide["characters"]?.table, server: block.server, account: block.account) {
                if characters[id] == nil { characters[id] = character }
            }
            // The addon list is the same on every megaserver; newer companions keep it only in the block
            // written last. For older files with a list in every block, take the newest block's.
            if let list = wide["addons"]?.table, block.stamp >= addonsStamp {
                addons = parseAddons(list)
                addonsStamp = block.stamp
            }
            for error in parseErrors(wide["errors"]?.table, at: block.path + [.string("errors")]) {
                let key = "\(error.addon ?? "")\u{1F}\(error.message)"
                if let old = mergedErrors[key] {
                    let newerAt = (error.lastAt ?? error.at ?? .distantPast) >= (old.lastAt ?? old.at ?? .distantPast)
                    var merged = CompanionError(
                        addon: error.addon ?? old.addon,
                        at: newerAt ? (error.at ?? old.at) : (old.at ?? error.at),
                        count: old.count + error.count,
                        character: newerAt ? (error.character ?? old.character) : (old.character ?? error.character),
                        message: error.message
                    )
                    let firsts = [old.firstAt, old.at, error.firstAt, error.at].compactMap { $0 }
                    merged.firstAt = firsts.min()
                    let lasts = [old.lastAt, old.at, error.lastAt, error.at].compactMap { $0 }
                    merged.lastAt = lasts.max()
                    merged.session = newerAt ? (error.session ?? old.session) : (old.session ?? error.session)
                    merged.addonVersion = newerAt ? (error.addonVersion ?? old.addonVersion) : (old.addonVersion ?? error.addonVersion)
                    // Opens at the newest occurrence; on a tie, the newer block's (seen first).
                    let strictlyNewer = (error.lastAt ?? error.at ?? .distantPast) > (old.lastAt ?? old.at ?? .distantPast)
                    merged.path = strictlyNewer || old.path.isEmpty ? error.path : old.path
                    mergedErrors[key] = merged
                } else {
                    mergedErrors[key] = error
                }
            }
            for (id, guild) in parseGuilds(wide["guilds"]?.table) where guilds[id] == nil { guilds[id] = guild }
            for (id, row) in parseEnabledBy(wide["enabledBy"]?.table) {
                if let old = enabledBy[id], (old.at ?? .distantPast) > (row.at ?? .distantPast) { continue }
                enabledBy[id] = row
            }
            let layoutTable = wide["layouts"]?.table
            // Newest block first: keep its rows, fill gaps from older blocks.
            for (name, layout) in parseLayouts(layoutTable?["sv"]?.table) where layouts[name] == nil {
                layouts[name] = layout
            }
            if layoutScan == nil { layoutScan = parseLayoutScan(layoutTable?["scanned"]?.table) }
            if requested.isEmpty {
                requested = (wide["lookups"]?.table?["requests"]?.table?["svGlobals"]?.table?.entries ?? [])
                    .compactMap(\.value.string)
            }
            for (key, answer) in parseAnswers(wide["lookups"]?.table?["answers"]?.table) where answers[key] == nil {
                answers[key] = answer
            }
            // Every megaserver keeps its own logins: take them all, once each, newest block's row first.
            for session in parseSessions(wide["sessions"]?.table) {
                let key = "\(session.character ?? "")\u{1F}\(session.loginAt?.timeIntervalSince1970 ?? -1)"
                if seenSessions.insert(key).inserted { sessions.append(session) }
            }
            let perfTable = wide["perf"]?.table
            for sample in parseSamples(perfTable?["samples"]?.table) {
                let key = "\(sample.at?.timeIntervalSince1970 ?? -1)\u{1F}\(sample.zoneId ?? -1)"
                if seenSamples.insert(key).inserted { perf.samples.append(sample) }
            }
            for load in parseLoads(perfTable?["loads"]?.table) {
                let key = "\(load.at?.timeIntervalSince1970 ?? -1)\u{1F}\(load.zoneId ?? -1)"
                if seenLoads.insert(key).inserted { perf.loads.append(load) }
            }
        }

        let errors = mergedErrors.values.sorted {
            ($0.at ?? .distantPast) > ($1.at ?? .distantPast)
        }
        let known = schema == nil || schema == knownSchema
        var snapshot = CompanionSnapshot(file: file, schema: schema, schemaKnown: known, written: written, env: env,
                                         characters: characters, addons: addons, errors: errors, guilds: guilds,
                                         skipped: known ? [] : [String(localized: "future schema \(schema ?? 0)", bundle: .module)])
        snapshot.enabledBy = enabledBy
        snapshot.layouts = layouts
        snapshot.layoutScan = layoutScan
        snapshot.requestedSvGlobals = requested
        snapshot.answers = answers
        snapshot.sessions = sessions.sorted { ($0.loginAt ?? .distantPast) < ($1.loginAt ?? .distantPast) }
        snapshot.savedAt = savedAt ?? written
        if !perf.samples.isEmpty || !perf.loads.isEmpty {
            perf.samples.sort { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) }
            perf.loads.sort { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) }
            snapshot.perf = perf
        }
        return snapshot
    }

    /// Total time played across companion sessions for one character ID.
    public static func playedTime(characterID: String, in snapshot: CompanionSnapshot) -> TimeInterval {
        snapshot.sessions.filter { $0.character == characterID }.compactMap(\.played).reduce(0, +)
    }

    /// Lua errors older than this are omitted from Problems (still present on the snapshot).
    public static let errorMaxAge: TimeInterval = 7 * 24 * 3600
    /// An error within this of `written` counts as the latest logout session.
    public static let errorSessionWindow: TimeInterval = 24 * 3600

    /// Errors young enough to show in Problems / HealthFindings.
    public static func recentErrors(in snapshot: CompanionSnapshot?, now: Date = .now) -> [CompanionError] {
        guard let snapshot else { return [] }
        return snapshot.errors.filter { isRecentError($0, now: now) }
    }

    public static func isRecentError(_ error: CompanionError, now: Date = .now) -> Bool {
        guard let at = error.lastAt ?? error.at else { return true }
        return now.timeIntervalSince(at) <= errorMaxAge
    }

    public static func isSameSession(_ error: CompanionError, written: Date?) -> Bool {
        guard let at = error.lastAt ?? error.at, let written else { return true }
        let lag = written.timeIntervalSince(at)
        return lag >= 0 && lag < errorSessionWindow
    }

    /// Load failures, out-of-date addons, and recent Lua errors. `installedVersions` is each installed
    /// manifest's `## AddOnVersion:` by lowercased folder name.
    public static func problems(from snapshot: CompanionSnapshot, installedVersions: [String: Int] = [:],
                                now: Date = .now) -> [SVProblem] {
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
        for (index, error) in snapshot.errors.enumerated() where isRecentError(error, now: now) {
            if isFixedSinceUpdate(error, installed: installedVersions, addons: snapshot.addons) { continue }
            let name = error.addon ?? String(localized: "An addon", bundle: .module)
            let times = error.count == 1 ? String(localized: "once", bundle: .module) : String(localized: "\(error.count) times", bundle: .module)
            let when: String = {
                if isSameSession(error, written: snapshot.written) {
                    return String(localized: "last session", bundle: .module)
                }
                guard let at = error.lastAt ?? error.at else { return String(localized: "last session", bundle: .module) }
                return at.formatted(.relative(presentation: .named, unitsStyle: .spellOut))
            }()
            let headline = errorFirstLine(error.message)
            // The newest occurrence's place in the file, so every error has its own id and opens at its own entry.
            let path = error.path.isEmpty ? [.string(variable), .string("errors"), .integer(Int64(index + 1))] : error.path
            var problem = SVProblem(file: file, path: path,
                                    kind: .luaError, severity: error.count >= 5 ? .error : .warning,
                                    message: String(localized: "\(name) threw Lua errors \(times) \(when).", bundle: .module) + " " + headline)
                .with(addon: error.addon)
            if headline != error.message { problem.detail = error.message }
            out.append(problem)
        }
        return out
    }

    /// True when the installed addon is newer than the version that threw the error (fixed by an update).
    /// The manifest on disk wins: an update installed since the last login isn't in the companion's list yet.
    public static func isFixedSinceUpdate(_ error: CompanionError, installed: [String: Int] = [:],
                                          addons: [String: CompanionAddonState]) -> Bool {
        guard let folder = error.addon, let then = error.addonVersion,
              let now = installed[folder.lowercased()] ?? addons[folder]?.addOnVersion else { return false }
        return now > then
    }

    /// First line of a Lua error string (before stack / Locals), trimmed.
    public static func errorFirstLine(_ message: String) -> String {
        let line = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Parse

    private static func parseEnv(_ table: LuaTable?) -> CompanionEnv? {
        guard let table else { return nil }
        var env = CompanionEnv(apiVersion: int(table["apiVersion"]), gameVersion: table["gameVersion"]?.string,
                               server: table["server"]?.string, language: table["language"]?.string,
                               companionVersion: table["companionVersion"]?.string)
        env.addonsTotal = int(table["addonsTotal"])
        env.addonsLoaded = int(table["addonsLoaded"])
        env.addonsDisabled = int(table["addonsDisabled"])
        env.loadOutOfDateAddOns = bool(table["loadOutOfDateAddOns"])
        return env
    }

    private static func parseCharacters(_ table: LuaTable?, server: String, account: String) -> [String: CompanionCharacter] {
        var out: [String: CompanionCharacter] = [:]
        for entry in table?.entries ?? [] {
            guard case .string(let id) = entry.key, let c = entry.value.table, let name = c["name"]?.string else { continue }
            var character = CompanionCharacter(id: id, name: name, server: server, account: account,
                                               classID: int(c["class"]), raceID: int(c["race"]), alliance: int(c["alliance"]),
                                               level: int(c["level"]), champion: int(c["champion"]),
                                               lastPlayed: int(c["lastPlayed"]).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                                               zoneId: int(c["zoneId"]), zoneName: c["zoneName"]?.string,
                                               locationId: int(c["locationId"]))
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
                                            addOnVersion: int(c["addOnVersion"]),
                                            rootPath: c["rootPath"]?.string, copies: copies)
        }
        return out
    }

    private static func parseErrors(_ table: LuaTable?, at path: [LuaKey]) -> [CompanionError] {
        (table?.entries ?? []).compactMap { entry in
            guard let c = entry.value.table, let message = c["message"]?.string, !message.isEmpty else { return nil }
            var error = CompanionError(addon: c["addon"]?.string, at: date(c["at"]),
                                       count: int(c["count"]) ?? 1, character: c["character"]?.string, message: message)
            error.firstAt = date(c["firstAt"])
            error.lastAt = date(c["lastAt"])
            error.session = date(c["session"])
            error.addonVersion = int(c["addonVersion"])
            error.path = path + [entry.key]
            return error
        }
    }

    private static func parseAnswers(_ table: LuaTable?) -> [String: CompanionAnswer] {
        var out: [String: CompanionAnswer] = [:]
        for entry in table?.entries ?? [] {
            guard case .string(let key) = entry.key, let c = entry.value.table else { continue }
            let missing = bool(c["missing"]) ?? false
            out[key] = CompanionAnswer(key: key, name: missing ? nil : c["name"]?.string, quality: int(c["quality"]),
                                       set: int(c["set"]), icon: c["icon"]?.string, missing: missing, at: date(c["at"]))
        }
        return out
    }

    private static func parseSessions(_ table: LuaTable?) -> [CompanionSession] {
        (table?.entries ?? []).compactMap { entry in
            guard let c = entry.value.table else { return nil }
            return CompanionSession(character: text(c["character"]), loginAt: date(c["loginAt"]),
                                    logoutAt: date(c["logoutAt"]), zoneId: int(c["zoneId"]))
        }
    }

    private static func parseSamples(_ table: LuaTable?) -> [CompanionPerf.Sample] {
        (table?.entries ?? []).compactMap { entry in
            guard let c = entry.value.table else { return nil }
            return CompanionPerf.Sample(at: date(c["at"]), fps: int(c["fps"]), ms: int(c["ms"]),
                                        luaKB: int(c["luaKB"]), zoneId: int(c["zoneId"]))
        }
    }

    private static func parseLoads(_ table: LuaTable?) -> [CompanionPerf.Load] {
        (table?.entries ?? []).compactMap { entry in
            guard let c = entry.value.table, let seconds = number(c["seconds"]), seconds >= 0 else { return nil }
            return CompanionPerf.Load(at: date(c["at"]), seconds: seconds, zoneId: int(c["zoneId"]))
        }
    }

    private static func number(_ value: LuaValue?) -> Double? {
        switch value {
        case .integer(let n)?: Double(n)
        case .number(let d)?: d
        default: nil
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
                                          pathCount: int(c["pathCount"]),
                                          defaults: c["defaults"]?.table.map { CompanionDefaults(table: $0, truncated: bool(c["defaultsTruncated"]) ?? false) })
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
