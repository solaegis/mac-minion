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

    public static func display(_ value: LuaValue, key: LuaKey, at path: [LuaKey], names: SVNameIndex?, now: Date = .now) -> SVDisplay {
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
        public var id: String { path.map(\.description).joined(separator: "\u{1F}") }
    }

    public struct Section: Sendable, Identifiable, Equatable {
        public let title: String
        /// Where it sits: "NA Megaserver · @SOLAEGIS".
        public let subtitle: String?
        public let path: [LuaKey]
        public let rows: [Row]
        /// Rows left out past the limit.
        public let more: Int
        /// What the table's keys are, from the addon's source: "Keyed by SETTING_TYPE_* values…".
        public var note: String?
        public var id: String { path.map(\.description).joined(separator: "\u{1F}") }
    }

    public static let rowsPerSection = 200
    public static let sectionsPerSheet = 60

    /// The entries of one table (or a file's variables) as sections of rows. Server and account
    /// tables, and the variables themselves, are see-through: their tables become sections titled by
    /// what they are ("Every character", a character's name), with the server and account as subtitle.
    public static func sheet(_ entries: [LuaEntry], at parentPath: [LuaKey], title: String, names: SVNameIndex?,
                             source: SVSourceNames? = nil, now: Date = .now) -> [Section] {
        var sections: [Section] = []
        func rows(_ entries: [LuaEntry], _ path: [LuaKey]) -> [Row] {
            entries.prefix(rowsPerSection).map { e in
                let named = source?.name(for: e.key, at: path)
                return Row(label: named?.title ?? label(e.key, names: names), key: e.key, path: path + [e.key],
                           display: display(e.value, key: e.key, at: path, names: names, now: now), source: named)
            }
        }
        func sectionTitle(_ key: LuaKey, _ parent: [LuaKey]) -> String {
            if SVLevel.of(key, at: parent) == .accountWide { return SVLevel.everyCharacter }
            if let name = names?.name(forKey: key, at: parent), name.kind == .character { return name.titleWithID }
            return label(key)
        }
        func subtitle(_ path: [LuaKey]) -> String? {
            let levels = path.enumerated().compactMap { i, k -> String? in
                let level = SVLevel.of(k, at: Array(path.prefix(i)))
                return level == .profile || level == .account ? k.description : nil
            }
            return levels.isEmpty ? nil : levels.joined(separator: " · ")
        }
        func see(_ entries: [LuaEntry], _ path: [LuaKey]) {
            // Plain values at this level form one section, named for the table they're in.
            let plain = entries.filter { e in
                guard let t = e.value.table else { return true }
                return color(fromTable: t, colorKey: hints(e.key).contains("colo")) != nil
            }
            if !plain.isEmpty {
                sections.append(Section(title: path.last.map { sectionTitle($0, Array(path.dropLast())) } ?? title,
                                        subtitle: subtitle(path), path: path, rows: rows(plain, path),
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
                    sections.append(Section(title: sectionTitle(e.key, path), subtitle: subtitle(path + [e.key]), path: path + [e.key],
                                            rows: rows(t.entries, path + [e.key]), more: max(0, t.count - rowsPerSection),
                                            note: source?.note(forTable: e.key)))
                }
            }
        }
        see(entries, parentPath)
        // Settings shared by every character first, then the rest by name; rows by label.
        return sections.map { section in
            Section(title: section.title, subtitle: section.subtitle, path: section.path,
                    rows: section.rows.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }, more: section.more, note: section.note)
        }
        .enumerated().sorted { a, b in
            let shared = (a.element.title == SVLevel.everyCharacter, b.element.title == SVLevel.everyCharacter)
            if shared.0 != shared.1 { return shared.0 }
            if a.element.subtitle != b.element.subtitle { return a.offset < b.offset }
            return a.element.title.localizedStandardCompare(b.element.title) == .orderedAscending
        }
        .map(\.element)
    }
}
