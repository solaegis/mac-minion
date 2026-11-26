import Foundation

/// Saved settings as people read them (S-050): labels in words, and values recognized as switches,
/// colors, items, dates, gold, or named IDs. Anything not recognized stays its plain value.
public enum SVDisplay: Sendable, Equatable {
    case toggle(Bool)
    /// Components from 0 to 1.
    case color(red: Double, green: Double, blue: Double, alpha: Double)
    case item(title: String, detail: String?)
    case date(Date)
    case gold(Double)
    case name(SVName)
    case number(String)
    case text(String)
    /// A table: how many entries, and whether they're numbered like a list.
    case table(count: Int, isList: Bool)
    /// One of the choices the addon's settings panel or constants offer: what it calls it, and the saved value.
    case choice(label: String, value: String)
    /// A number with the range its slider allows; `outOfRange` when the saved value is outside it.
    case ranged(text: String, range: ClosedRange<Double>, outOfRange: Bool)
}

public enum SVReadable {
    // MARK: Labels

    /// `showMatCost` -> "Show mat cost", `bAutoAccept` -> "Auto accept", `$LastCharacterName` -> "Last character name",
    /// `incomplete_colour` -> "Incomplete colour", `UIScale` -> "UI scale", `[3]` -> "#3".
    /// A label that names a character ID key: "Masisi (8796093036412335)" rather than the bare ID.
    public static func label(_ key: LuaKey, names: SVNameIndex?) -> String {
        if case .string(let s) = key, CharacterID.isID(s), let name = names?.name(forString: s) { return name.titleWithID }
        return label(key)
    }

    public static func label(_ key: LuaKey) -> String {
        guard case .string(var s) = key else { return "#\(key)" }
        // Keys with spaces are already words, often names ("Ringil of Eskiath", "NA Megaserver"): keep them.
        if s.contains(" ") { return s }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "$_"))
        // Hungarian prefixes: bEnabled, nCount, sName, tList, iLevel, fScale.
        if s.count > 2, let first = s.first, "bnstif".contains(first), s.dropFirst().first?.isUppercase == true,
           s.dropFirst(2).first?.isLowercase == true {
            s.removeFirst()
        }
        var words: [String] = [], word = ""
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            if c == "_" || c == "-" || c == " " || c == "." {
                if !word.isEmpty { words.append(word); word = "" }
                continue
            }
            let previous = i > 0 ? chars[i - 1] : nil
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            let startsWord = c.isUppercase && (previous?.isLowercase == true || previous?.isNumber == true
                                               || (previous?.isUppercase == true && next?.isLowercase == true))
            let numberEdge = c.isNumber != (previous?.isNumber ?? c.isNumber)
            if (startsWord || numberEdge), !word.isEmpty { words.append(word); word = "" }
            word.append(c)
        }
        if !word.isEmpty { words.append(word) }
        guard !words.isEmpty else { return s }
        // Sentence case; words in capitals (UI, ID, NA) stay as they are, and short forms are written the usual way.
        let shortForms = ["id": "ID", "ids": "IDs", "url": "URL", "ui": "UI", "hud": "HUD", "cp": "CP", "ap": "AP", "xp": "XP"]
        return words.enumerated().map { i, w in
            if let short = shortForms[w.lowercased()] { return short }
            if w.count > 1, w.allSatisfy({ $0.isUppercase || $0.isNumber }) { return w }
            return i == 0 ? w.prefix(1).uppercased() + w.dropFirst().lowercased() : w.lowercased()
        }.joined(separator: " ")
    }

    // MARK: Values

    /// Unix times between 2014 (the game's launch) and a year from now.
    static func isTimestamp(_ n: Double, now: Date) -> Bool { n >= 1_388_534_400 && n <= now.timeIntervalSince1970 + 366 * 86_400 }

    static func hints(_ key: LuaKey) -> String { key.description.lowercased() }

    public static func display(_ value: LuaValue, key: LuaKey, at path: [LuaKey], names: SVNameIndex?,
                               control: SVControl? = nil, now: Date = .now) -> SVDisplay {
        if let control, let choice = control.choice(for: value), choice.label != choice.value {
            return .choice(label: control.guessedChoices == true ? "\(choice.label)?" : choice.label, value: choice.value)
        }
        // A game ID AI read the kind of: named like a key of that kind.
        if let kind = control?.idKind, case .integer(let id) = value, let name = names?.name(forID: id, kind: kind) {
            return .name(name)
        }
        let plain = plainDisplay(value, key: key, at: path, names: names, now: now)
        guard let control, case .number(var text) = plain else { return plain }
        if let unit = control.unit { text += unit == "%" ? "%" : " \(unit)" }
        if let range = control.range { return .ranged(text: text, range: range, outOfRange: control.isOutOfRange(value)) }
        return .number(text)
    }

    static func plainDisplay(_ value: LuaValue, key: LuaKey, at path: [LuaKey], names: SVNameIndex?, now: Date) -> SVDisplay {
        let k = hints(key)
        let colorKey = k.contains("color") || k.contains("colour")
        switch value {
        case .bool(let b):
            return .toggle(b)
        case .string(let s):
            if let color = color(fromString: s, colorKey: colorKey) { return color }
            if ItemLink.isLink(s), let name = names?.name(forValue: value, key: key, at: path) {
                return .item(title: name.title, detail: name.detail)
            }
            if let name = names?.name(forValue: value, key: key, at: path) ?? names?.name(forKey: .string(s), at: path) { return .name(name) }
            return .text(s)
        case .integer, .number:
            let n: Double = if case .integer(let i) = value { Double(i) } else if case .number(let d) = value { d } else { 0 }
            if let name = names?.name(forValue: value, key: key, at: path) { return .name(name) }
            if isTimestamp(n, now: now), ["time", "date", "stamp", "seen", "updated", "expire"].contains(where: k.contains) || k.hasPrefix("last") {
                return .date(Date(timeIntervalSince1970: n))
            }
            if ["gold", "money", "price", "cost", "spent", "budget"].contains(where: k.contains), !k.hasPrefix("use"), !k.hasPrefix("show") {
                return .gold(n)
            }
            // Versions and IDs read as written: 20251007, not 20,251,007.
            if k.contains("version") || k.hasSuffix("id") || k.hasSuffix("ids") { return .number(number(value, grouped: false)) }
            return .number(number(value))
        case .nil:
            return .text("nil")
        case .table(let t):
            if let color = color(fromTable: t, colorKey: colorKey) { return color }
            let isList = t.entries.allSatisfy { if case .integer = $0.key { true } else { false } }
            return .table(count: t.count, isList: isList)
        }
    }

    static func number(_ value: LuaValue, grouped: Bool = true) -> String {
        switch value {
        case .integer(let n): grouped ? n.formatted() : String(n)
        case .number(let d): d.formatted(.number.precision(.significantDigits(1...6)))
        default: ""
        }
    }

    /// `{ r, g, b, a }` anywhere; `{ 1, 0, 0[, 1] }` under a color key; components from 0 to 1.
    static func color(fromTable t: LuaTable, colorKey: Bool) -> SVDisplay? {
        func component(_ v: LuaValue?) -> Double? {
            switch v {
            case .integer(let n)?: (0...1).contains(n) ? Double(n) : nil
            case .number(let d)?: (0...1).contains(d) ? d : nil
            default: nil
            }
        }
        if let r = component(t["r"]), let g = component(t["g"]), let b = component(t["b"]), t.count <= 4 {
            return .color(red: r, green: g, blue: b, alpha: component(t["a"]) ?? 1)
        }
        if colorKey, (3...4).contains(t.count),
           let r = component(t[.integer(1)]), let g = component(t[.integer(2)]), let b = component(t[.integer(3)]) {
            return .color(red: r, green: g, blue: b, alpha: component(t[.integer(4)]) ?? 1)
        }
        return nil
    }

    /// `|cRRGGBB` (ESO's color code) anywhere; `RRGGBB` or `RRGGBBAA` under a color key.
    static func color(fromString s: String, colorKey: Bool) -> SVDisplay? {
        var hex = Substring(s)
        if hex.hasPrefix("|c") { hex = hex.dropFirst(2) } else if !colorKey { return nil }
        if hex.hasPrefix("#") { hex = hex.dropFirst() }
        guard hex.count == 6 || hex.count == 8, let v = UInt32(hex, radix: 16) else { return nil }
        let has = hex.count == 8
        let r = Double((v >> (has ? 24 : 16)) & 0xFF) / 255, g = Double((v >> (has ? 16 : 8)) & 0xFF) / 255
        let b = Double((v >> (has ? 8 : 0)) & 0xFF) / 255, a = has ? Double(v & 0xFF) / 255 : 1
        return .color(red: r, green: g, blue: b, alpha: a)
    }

    // MARK: Sheets

    public struct Row: Sendable, Identifiable, Equatable {
        public let label: String
        public let key: LuaKey
        public let path: [LuaKey]
        public let display: SVDisplay
        /// What the addon's source says the key is, when it says.
        public var source: SVSourceName?
        /// The range or choices the addon's source gives the key.
        public var control: SVControl? = nil
        public var id: String { path.map(\.description).joined(separator: "\u{1F}") }
    }

    public struct Section: Sendable, Identifiable, Equatable {
        public let title: String
        /// Where it sits: "@SOLAEGIS · NA".
        public let subtitle: String?
        /// The account and megaserver it belongs to. A character's megaserver is their own even when the table
        /// sits under the shared `Default` profile; nil when nothing says (then `profile` places it).
        public var account: String? = nil
        public var megaserver: String? = nil
        public var profile: String? = nil
        /// A name-keyed table the `Default` profile gives same-named characters on several megaservers:
        /// megaserver -> that character's ID. It is listed under each of their megaservers.
        public var sharedWith: [String: String] = [:]
        /// What the outline shows: a character's name alone ("Masisi"), or the ID when no file names them.
        public var rowTitle: String = ""
        /// The row's help: the name with its ID.
        public var rowHelp: String? = nil
        public let path: [LuaKey]
        public internal(set) var rows: [Row]
        /// Rows left out past the limit.
        public let more: Int
        /// What the table's keys are, from the addon's source: "Keyed by SETTING_TYPE_* values…".
        public var note: String?
        public var id: String { path.map(\.description).joined(separator: "\u{1F}") }
    }

    public static let rowsPerSection = 200
    /// Only one section is drawn at a time, so this guards the outline, not the page.
    public static let sectionsPerSheet = 500

    /// The entries of one table (or a file's variables) as sections of rows. Server and account
    /// tables, and the variables themselves, are see-through: their tables become sections titled by
    /// what they are ("Every character", a character's name), with the server and account as subtitle.
    public static func sheet(_ entries: [LuaEntry], at parentPath: [LuaKey], title: String, names: SVNameIndex?,
                             source: SVSourceNames? = nil, locations: CharacterLocations = CharacterLocations(),
                             now: Date = .now) -> [Section] {
        var sections: [Section] = []
        // Characters by name, for tables an addon keys by name: a name is unique only on one megaserver.
        var byName: [String: [String]] = [:]
        for (id, c) in names?.characters ?? [:] { byName[c.name, default: []].append(id) }
        func rows(_ entries: [LuaEntry], _ path: [LuaKey]) -> [Row] {
            entries.prefix(rowsPerSection).map { e in
                let named = source?.name(for: e.key, at: path)
                var control = source?.control(for: e.key, at: path)
                var itemLabel: String?
                // An item of a list: what the list's positions and items are, from AI.
                if case .integer(let n) = e.key, let list = source?.itemControl(at: path) {
                    if control == nil, list.idKind != nil || list.unit != nil {
                        var item = SVControl(type: "item")
                        item.unit = list.unit; item.idKind = list.idKind
                        control = item
                    }
                    itemLabel = list.indexMeaning.map { "\($0) \(n)" }
                }
                return Row(label: named?.title ?? itemLabel ?? label(e.key, names: names), key: e.key, path: path + [e.key],
                           display: display(e.value, key: e.key, at: path, names: names, control: control, now: now),
                           source: named, control: control)
            }
        }
        /// Where a table sits: its account, profile, and megaserver. The megaserver is the first real one in the
        /// path (a profile, or one an addon nests under `$AccountWide`), else the character's own: by ID, or by
        /// name on this account. `shared` lists the characters of one name on several megaservers that the
        /// `Default` profile gives one table.
        func whereIs(_ path: [LuaKey]) -> (account: String?, profile: String?, megaserver: String?, shared: [String]) {
            var account: String?, profile: String?, megaserver: String?, character: String?, nameKey: (index: Int, key: String)?
            for (i, k) in path.enumerated() {
                guard case .string(let s) = k else { continue }
                let level = SVLevel.of(k, at: Array(path.prefix(i)))
                if level == .profile { profile = s; megaserver = megaserver ?? SVLevel.megaserver(ofProfile: s) }
                else if level == .account { account = s }
                else if i > 1, megaserver == nil, path[i - 1] == .string("$AccountWide"), let m = SVLevel.megaserver(ofProfile: s) { megaserver = m }
                if CharacterID.isID(s) { character = character ?? s }
                else if level == .characterName || (level == .character && s.contains("^")) { nameKey = nameKey ?? (i, s) }
            }
            var shared: [String] = []
            if megaserver == nil, let character { megaserver = locations.location(character).megaserver }
            if megaserver == nil, character == nil, let nameKey, let account, let profile {
                let name = String(nameKey.key.split(separator: "^").first ?? Substring(nameKey.key))
                switch locations.resolve(name: name, account: account, profile: profile, among: byName[name] ?? []) {
                case .one(let id): megaserver = locations.location(id).megaserver
                case .shared(let ids): if nameKey.index == path.count - 1 { shared = ids }
                default: break
                }
            }
            return (account, profile, megaserver, shared)
        }
        func sectionTitle(_ key: LuaKey, _ parent: [LuaKey]) -> String {
            if SVLevel.of(key, at: parent) == .accountWide { return SVLevel.everyCharacter }
            if let name = names?.name(forKey: key, at: parent), name.kind == .character { return name.titleWithID }
            return label(key)
        }
        func section(title: String, path: [LuaKey], rows: [Row], more: Int, note: String?) -> Section {
            let place = whereIs(path)
            let server = place.megaserver.map(SettingsMatrix.shortServer) ?? place.profile
            let subtitle = [place.account, server].compactMap { $0 }
            var s = Section(title: title, subtitle: subtitle.isEmpty ? nil : subtitle.joined(separator: " · "), path: path,
                            rows: rows, more: more, note: note)
            s.account = place.account; s.megaserver = place.megaserver; s.profile = place.profile
            // Under Default, same-named characters on each megaserver share one table: it's listed under each.
            for id in place.shared { if let m = locations.location(id).megaserver { s.sharedWith[m] = id } }
            s.rowTitle = title
            if let key = path.last, case .string(let k) = key, CharacterID.isID(k) {
                let name = names?.name(forString: k)
                s.rowTitle = name.map { $0.title == SVName.unknownCharacter ? k : $0.title } ?? k
                s.rowHelp = name?.titleWithID ?? k
            }
            return s
        }
        func see(_ entries: [LuaEntry], _ path: [LuaKey]) {
            // Plain values at this level form one section, named for the table they're in.
            let plain = entries.filter { e in
                guard let t = e.value.table else { return true }
                return color(fromTable: t, colorKey: hints(e.key).contains("colo")) != nil
            }
            if !plain.isEmpty {
                sections.append(section(title: path.last.map { sectionTitle($0, Array(path.dropLast())) } ?? title,
                                        path: path, rows: rows(plain, path),
                                        more: max(0, plain.count - rowsPerSection), note: path.last.flatMap { source?.note(forTable: $0) }))
            }
            for e in entries where sections.count < sectionsPerSheet {
                guard let t = e.value.table, !plain.contains(where: { $0.key == e.key }) else { continue }
                let level = SVLevel.of(e.key, at: path)
                let wrapper = path.isEmpty || level == .profile || level == .account
                if wrapper {
                    see(t.entries, path + [e.key])
                } else {
                    // A section per table; tables inside it are rows that open.
                    sections.append(section(title: sectionTitle(e.key, path), path: path + [e.key],
                                            rows: rows(t.entries, path + [e.key]), more: max(0, t.count - rowsPerSection),
                                            note: source?.note(forTable: e.key)))
                }
            }
        }
        see(entries, parentPath)
        // Rows by label.
        return grouped(sections.map { section in
            var sorted = section
            sorted.rows = section.rows.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            return sorted
        }).flatMap(\.sections)
    }

    /// Sections that sit in the same place (account and megaserver), kept together.
    public struct Group: Sendable, Identifiable, Equatable {
        /// "@SOLAEGIS · NA"; nil for sections outside any account or profile.
        public let title: String?
        public let sections: [Section]
        /// Account, then megaserver (or profile, when no megaserver is known).
        public let id: String
    }

    /// The group a section goes in: its account and megaserver, never its account alone.
    static func groupKey(_ section: Section) -> String {
        "\(section.account ?? "")|\(section.megaserver ?? section.profile ?? "")"
    }

    /// Sections by account, accounts in the order they come: in each, the settings shared by every
    /// character first, then its characters and other tables by name.
    public static func grouped(_ sections: [Section]) -> [Group] {
        var order: [String] = [], byGroup: [String: [Section]] = [:]
        for section in sections {
            let key = groupKey(section)
            if byGroup[key] == nil { order.append(key) }
            byGroup[key, default: []].append(section)
        }
        return order.map { key in
            let members = byGroup[key] ?? []
            let sorted = members.enumerated().sorted { a, b in
                let shared = (a.element.title == SVLevel.everyCharacter, b.element.title == SVLevel.everyCharacter)
                if shared.0 != shared.1 { return shared.0 }
                let order = a.element.title.localizedStandardCompare(b.element.title)
                return order == .orderedSame ? a.offset < b.offset : order == .orderedAscending
            }
            return Group(title: members.first?.subtitle, sections: sorted.map(\.element), id: key)
        }
    }

    // MARK: Outline

    /// One row of the outline beside the settings. A table can be listed in more than one folder (a name
    /// same-named characters share under Default), so a row's ID is its folder and its section.
    public struct OutlineRow: Sendable, Identifiable, Equatable {
        public let id: String
        public let sectionID: String
        public let title: String
        public let help: String?
        /// The folder's megaserver; nil for the Default folder and for rows outside any account.
        public let megaserver: String?
    }

    /// A megaserver under an account ("NA"), or the Default folder: what every megaserver uses.
    public struct OutlineFolder: Sendable, Identifiable, Equatable {
        public let id: String
        /// Nil for the Default folder.
        public let megaserver: String?
        public let title: String
        public let rows: [OutlineRow]
    }

    /// An account and its folders. Tables outside any account are `loose` rows of an account of nil.
    public struct OutlineAccount: Sendable, Identifiable, Equatable {
        public let id: String
        public let account: String?
        public let folders: [OutlineFolder]
        public let loose: [OutlineRow]

        /// Every row, in the order the outline shows them.
        public var rows: [OutlineRow] { loose + folders.flatMap(\.rows) }
    }

    /// The folder title for tables under the Default profile.
    public static let defaultFolder = String(localized: "Default", bundle: .kit)

    /// Sections as an outline: account, then megaserver (real ones by name, then Default), then the
    /// account's settings for every character first and its characters and other tables by name.
    public static func outline(_ sections: [Section]) -> [OutlineAccount] {
        var order: [String] = []
        var folders: [String: [String: [Section]]] = [:]       // account -> megaserver ("" for Default) -> sections
        var loose: [String: [Section]] = [:]
        for section in sections {
            let account = section.account ?? ""
            if folders[account] == nil && loose[account] == nil { order.append(account) }
            if section.account == nil {
                loose[account, default: []].append(section)
            } else if !section.sharedWith.isEmpty {
                for m in section.sharedWith.keys { folders[account, default: [:]][m, default: []].append(section) }
            } else {
                folders[account, default: [:]][section.megaserver ?? "", default: []].append(section)
            }
        }
        func rows(_ list: [Section], folder: String) -> [OutlineRow] {
            list.enumerated().sorted { a, b in
                let shared = (a.element.title == SVLevel.everyCharacter, b.element.title == SVLevel.everyCharacter)
                if shared.0 != shared.1 { return shared.0 }
                // Characters no file names, shown by their ID, come after the named ones.
                let unnamed = (CharacterID.isID(a.element.rowTitle), CharacterID.isID(b.element.rowTitle))
                if unnamed.0 != unnamed.1 { return unnamed.1 }
                let order = a.element.rowTitle.localizedStandardCompare(b.element.rowTitle)
                return order == .orderedSame ? a.offset < b.offset : order == .orderedAscending
            }.map { _, s in
                OutlineRow(id: "\(folder)\u{1E}\(s.id)", sectionID: s.id, title: s.rowTitle.isEmpty ? s.title : s.rowTitle,
                           help: s.rowHelp, megaserver: folder.isEmpty ? nil : folder)
            }
        }
        return order.map { account in
            let byServer = folders[account] ?? [:]
            let names = byServer.keys.sorted { a, b in a.isEmpty != b.isEmpty ? b.isEmpty : a.localizedStandardCompare(b) == .orderedAscending }
            return OutlineAccount(
                id: account, account: account.isEmpty ? nil : account,
                folders: names.map { m in
                    OutlineFolder(id: "\(account)|\(m)", megaserver: m.isEmpty ? nil : m,
                                  title: m.isEmpty ? defaultFolder : SettingsMatrix.shortServer(m), rows: rows(byServer[m]!, folder: m))
                },
                loose: rows(loose[account] ?? [], folder: ""))
        }
    }
}
