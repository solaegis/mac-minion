import Foundation

/// What an addon's own Lua source says a saved key means. See docs/SOURCE-NAMES.md.
public struct SVSourceName: Sendable, Equatable, Codable {
    public enum Source: String, Sendable, Codable {
        /// The label of the LibAddonMenu control whose getFunc returns this key.
        case settingsPanel = "the addon's settings panel"
        /// A comment beside the key where the addon sets its defaults.
        case comment = "a comment in the addon's source"
        /// A constant the addon defines with this number, used to index the table.
        case constant = "a constant in the addon's source"
        /// An AI model's reading of the lines that use the key (SVAINaming). Always a guess.
        case ai = "an AI model, from the lines of the addon's source that use the key"

        /// Where the name came from, in the UI's language.
        public var description: String {
            switch self {
            case .settingsPanel: String(localized: "the addon's settings panel", bundle: .module)
            case .comment: String(localized: "a comment in the addon's source", bundle: .module)
            case .constant: String(localized: "a constant in the addon's source", bundle: .module)
            case .ai: String(localized: "an AI model, from the lines of the addon's source that use the key", bundle: .module)
            }
        }
    }

    /// A name to show instead of the key; nil when only a description is known.
    public let title: String?
    /// A tooltip or comment that says more.
    public let detail: String?
    public let source: Source
    /// Matched by the key's name alone, or by a number, so it may belong to another table with the same key.
    public let isGuess: Bool
    public init(title: String?, detail: String?, source: Source, isGuess: Bool) {
        self.title = title; self.detail = detail; self.source = source; self.isGuess = isGuess
    }
}

/// Names for one addon's saved keys, read from its Lua files.
public struct SVSourceNames: Sendable, Equatable, Codable {
    /// Parent key ("" for any) -> key -> name.
    var names: [String: [String: SVSourceName]] = [:]
    /// Table key -> what its keys are, for tables keyed by constants.
    var tableNotes: [String: String] = [:]
    /// Parent key ("" for any) -> key -> the settings-panel control or constants that say what values it takes.
    var controls: [String: [String: SVControl]] = [:]
    /// Parent key ("" for any) -> key -> what AI read past the name (S-074). Added on top, never cached here.
    var aiFields: [String: [String: SVAIField]] = [:]
    /// Parent key ("" for any) -> key -> the settings-panel control as the running game resolved it (S-077),
    /// from the companion. Wins over the source's; added on top, never cached here.
    var companionControls: [String: [String: SVControl]] = [:]

    public init() {}

    public var isEmpty: Bool { names.isEmpty && tableNotes.isEmpty && controls.isEmpty && aiFields.isEmpty }
    public var count: Int { names.values.reduce(0) { $0 + $1.count } }

    /// A name for `key` in the table at `parent`: matched with its parent key first, then by itself.
    public func name(for key: LuaKey, at parent: [LuaKey]) -> SVSourceName? {
        let k = key.description
        if let p = parent.last?.description, let exact = names[p]?[k] { return exact }
        return names[""]?[k]
    }

    /// The range or choices for `key` in the table at `parent`: matched with its parent key first, then by itself.
    /// What AI read about `key`, when it was asked; an empty reading means it was asked and knew nothing.
    public func aiField(for key: LuaKey, at parent: [LuaKey]) -> SVAIField? {
        let k = key.description
        if let p = parent.last?.description, let exact = aiFields[p]?[k] { return exact }
        return aiFields[""]?[k]
    }

    public func control(for key: LuaKey, at parent: [LuaKey]) -> SVControl? {
        let k = key.description
        let p = parent.last?.description
        var source = p.flatMap { controls[$0]?[k] } ?? controls[""]?[k]
        // The game's own reading of the control: its fields win, the source's fill what it left out.
        if let game = p.flatMap({ companionControls[$0]?[k] }) ?? companionControls[""]?[k] {
            var merged = game
            merged.min = game.min ?? source?.min
            merged.max = game.max ?? source?.max
            merged.step = game.step ?? source?.step
            merged.defaultValue = game.defaultValue ?? source?.defaultValue
            if merged.choices.isEmpty { merged.choices = source?.choices ?? [] }
            if merged.type == "control", let type = source?.type { merged.type = type }
            source = merged
        }
        guard let ai = p.flatMap({ aiFields[$0]?[k] }) ?? aiFields[""]?[k] else { return source }
        // AI fills only what the source left out.
        var merged = source ?? SVControl(type: "ai")
        merged.unit = merged.unit ?? ai.unit
        merged.idKind = merged.idKind ?? ai.idKind
        merged.indexMeaning = merged.indexMeaning ?? ai.indexMeaning
        if merged.choices.isEmpty, !ai.choices.isEmpty {
            merged.choices = ai.choices.sorted { a, b in
                if let x = Double(a.key), let y = Double(b.key) { return x < y }
                return a.key < b.key
            }.map { SVControl.Choice(value: $0.key, label: $0.value) }
            merged.guessedChoices = true
        }
        return merged
    }

    /// What an item of a list is: the range, choices, or ID kind of the table at `path`.
    public func itemControl(at path: [LuaKey]) -> SVControl? {
        guard let key = path.last else { return nil }
        return control(for: key, at: Array(path.dropLast()))
    }

    /// The companion's settings-panel controls (S-077), tied to keys by name: a control applies to every key the
    /// source ties to a settings-panel control of the same name. Returns how many keys it reached.
    @discardableResult
    public mutating func applyCompanion(_ controls: [CompanionLAMControl]) -> Int {
        func plain(_ s: String) -> String { Manifest.stripColors(s).trimmingCharacters(in: .whitespaces).lowercased() }
        var byName: [String: CompanionLAMControl] = [:]
        for c in controls { if let name = c.name, !name.isEmpty { byName[plain(name)] = byName[plain(name)] ?? c } }
        var reached = Set<String>()
        for (parent, keys) in names {
            for (key, name) in keys where name.source == .settingsPanel {
                guard let title = name.title, let c = byName[plain(title)] else { continue }
                companionControls[parent, default: [:]][key] = c.control
                // The game's tooltip is in the player's language and can't be a guess.
                if let tip = c.tooltip, !tip.isEmpty, name.detail == nil {
                    self.names[parent]?[key] = SVSourceName(title: title, detail: tip, source: name.source, isGuess: name.isGuess)
                }
                reached.insert(key)
            }
        }
        return reached.count
    }

    /// Whether AI read any key as holding game IDs: only then is a file walked for `idLookups`.
    public var hasIDKinds: Bool { aiFields.values.contains { $0.values.contains { $0.idKind != nil } } }

    /// Game IDs in a file that AI read the kind of, by kind (S-077): a key's own number, or every number in
    /// its list. For the companion to name; at most `cap` in all.
    public func idLookups(in doc: SVDocument, cap: Int = 200) -> [String: Set<Int>] {
        var found: [String: Set<Int>] = [:], count = 0
        func walk(_ entries: [LuaEntry], _ path: [LuaKey], depth: Int) {
            for e in entries where count < cap {
                if let kind = control(for: e.key, at: path)?.idKind {
                    let ids: [Int64] = switch e.value {
                    case .integer(let n): [n]
                    case .table(let t): t.entries.compactMap { if case .integer(let n) = $0.value { n } else { nil } }
                    default: []
                    }
                    for id in ids where id > 0 && count < cap {
                        if found[kind, default: []].insert(Int(id)).inserted { count += 1 }
                    }
                }
                if let t = e.value.table, depth < 8 { walk(t.entries, path + [e.key], depth: depth + 1) }
            }
        }
        walk(doc.variables, [], depth: 0)
        return found
    }

    /// AI's reading of a key; its label becomes a name where the source gave none.
    public mutating func addAI(_ field: SVAIField, key: String, parent: String) {
        aiFields[parent, default: [:]][key] = field
        if let label = field.label { add(SVSourceName(title: label, detail: nil, source: .ai, isGuess: true), key: key, parent: parent) }
    }

    /// What the keys of the table at `key` are, like "SETTING_TYPE_* values".
    public func note(forTable key: LuaKey) -> String? { tableNotes[key.description] }

    // MARK: Reading

    /// Lua files bigger than this are data, not code with settings: skipped.
    public static let maxFileBytes = 1_500_000

    /// The same names with AI's left out: what the source alone says.
    public static func withoutAI(_ names: SVSourceNames) -> SVSourceNames {
        var copy = names
        copy.names = names.names.mapValues { $0.filter { $0.value.source != .ai } }.filter { !$0.value.isEmpty }
        copy.aiFields = [:]
        copy.companionControls = [:]
        return copy
    }

    /// Adds a name where the source gave none; a name from the source always wins.
    public mutating func add(_ new: SVSourceName, key: String, parent: String) {
        if name(for: .string(key), at: [.string(parent)])?.title != nil { return }
        names[parent, default: [:]][key] = new
    }

    /// Reads every `.lua` file in an addon folder, leaving out translations.
    public static func read(folder: URL) -> SVSourceNames { parse(sourceTexts(folder: folder)) }

    /// The text of every `.lua` file in an addon folder that isn't a translation or data.
    public static func sourceTexts(folder: URL) -> [String] {
        let fm = FileManager.default
        var sources: [String] = []
        if let walker = fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in walker where url.pathExtension.lowercased() == "lua" && !isTranslation(url.lastPathComponent) {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                guard size <= maxFileBytes, let data = try? Data(contentsOf: url) else { continue }
                sources.append(String(decoding: data, as: UTF8.self))
            }
        }
        return sources
    }

    /// The addon's `.lua` files as one stamp: how many, their bytes, and the newest change. Cheap next to
    /// reading them, and it changes whenever the source does, even without a new version.
    public static func fingerprint(folder: URL) -> String {
        var count = 0, bytes = 0, newest = 0.0
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        if let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for case let url as URL in walker where url.pathExtension.lowercased() == "lua" {
                let values = try? url.resourceValues(forKeys: Set(keys))
                count += 1
                bytes += values?.fileSize ?? 0
                newest = max(newest, values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
            }
        }
        return "\(count)-\(bytes)-\(Int(newest))"
    }

    /// `de.lua`, `lang/fr.lua`, `MyAddon_ru.lua`: strings in other languages, which would replace the English ones.
    static func isTranslation(_ file: String) -> Bool {
        let base = file.lowercased().replacingOccurrences(of: ".lua", with: "")
        let languages = ["de", "fr", "ru", "es", "jp", "ja", "zh", "it", "pl", "br", "pt", "kr", "ko", "ua", "tr"]
        return languages.contains { base == $0 || base.hasSuffix("_\($0)") || base.hasSuffix("-\($0)") || base.hasSuffix(".\($0)") }
    }

    public static func parse(_ sources: [String]) -> SVSourceNames {
        // Strings first: panels name their controls with them.
        var strings: [String: String] = [:]
        var constants: [String: Int] = [:]
        for text in sources {
            for m in matches(#"ZO_CreateStringId\s*\(\s*"(SI_\w+)"\s*,\s*"((?:[^"\\]|\\.)*)""#, text) { strings[m[1]] = unescape(m[2]) }
            // String tables fed to ZO_CreateStringId in a loop: `SI_MYADDON_SHOW = "Show",`.
            if text.contains("ZO_CreateStringId") {
                for m in matches(#"\b(SI_[A-Z0-9_]+)\s*=\s*"((?:[^"\\]|\\.)*)""#, text) where strings[m[1]] == nil { strings[m[1]] = unescape(m[2]) }
            }
            for m in matches(#"(?m)^\s*(?:local\s+)?(?:[A-Za-z_]\w*\.)*([A-Z][A-Z0-9_]{2,})\s*=\s*(\d+)\s*,?\s*(?:--.*)?$"#, text) {
                constants[m[1]] = Int(m[2])
            }
        }

        var result = SVSourceNames()
        var ambiguous = Set<String>()
        func put(_ name: SVSourceName, key: String, parent: String) {
            let existing = result.names[parent]?[key]
            if parent.isEmpty, let existing, existing.source == .settingsPanel, name.source == .settingsPanel, existing.title != name.title {
                ambiguous.insert(key)
            }
            if keeps(existing, over: name) { return }
            result.names[parent, default: [:]][key] = name
        }
        func keeps(_ existing: SVSourceName?, over new: SVSourceName) -> Bool {
            guard let existing else { return false }
            return existing.source == .settingsPanel && new.source != .settingsPanel
        }
        func putControl(_ control: SVControl, key: String, parent: String) {
            guard !control.isEmpty else { return }
            if let existing = result.controls[parent]?[key], existing.type != "constants" { return }
            result.controls[parent, default: [:]][key] = control
        }
        func resolve(_ value: String) -> String? {
            let v = value.trimmingCharacters(in: .whitespaces)
            if v.hasPrefix("\"") { return Manifest.stripColors(unescape(String(v.dropFirst().dropLast()))) }
            if let id = v.firstMatch(#"SI_[A-Z0-9_]+"#) { return strings[id].map(Manifest.stripColors) }
            return nil
        }

        for text in sources {
            let u = Array(text.utf16)
            // Settings panels: `getFunc = function() return MyAddon.sv.group.key end` inside a control with a name.
            let getter = #"getFunc\s*=\s*function\s*\(\s*\)\s*return\s+([A-Za-z_]\w*(?:\s*(?:\.\s*[A-Za-z_]\w*|\[\s*"[^"]*"\s*\]))+)\s*end"#
            for m in rangedMatches(getter, text) {
                let chain = components(m.groups[1])
                guard chain.count >= 2, let key = chain.last else { continue }
                guard let bounds = enclosingBounds(u, at: m.location) else { continue }
                let block = flatten(u, bounds), full = String(decoding: u[(bounds.start + 1)..<bounds.end], as: UTF16.self)
                let title = block.firstMatch(#"(?<![\w.])name\s*=\s*("(?:[^"\\]|\\.)*"|GetString\s*\(\s*SI_\w+\s*\)|SI_[A-Z0-9_]+)"#, group: 1).flatMap(resolve)
                let tip = block.firstMatch(#"(?<![\w.])tooltip\s*=\s*("(?:[^"\\]|\\.)*"|GetString\s*\(\s*SI_\w+\s*\)|SI_[A-Z0-9_]+)"#, group: 1).flatMap(resolve)
                let control = lamControl(block: block, full: full, sources: sources, constants: constants, resolve: resolve)
                if chain.count >= 3 { putControl(control, key: key, parent: chain[chain.count - 2]) }
                putControl(control, key: key, parent: "")
                guard let title, !title.isEmpty else { continue }
                // The parent key is only known when the chain has one between the saved table and the key.
                if chain.count >= 3 {
                    put(SVSourceName(title: title, detail: tip, source: .settingsPanel, isGuess: false), key: key, parent: chain[chain.count - 2])
                }
                put(SVSourceName(title: title, detail: tip, source: .settingsPanel, isGuess: false), key: key, parent: "")
            }
            // Defaults with a comment: `showMap = true, -- Show the map when crafting`.
            for m in matches(#"(?m)^\s*(?:\[\s*")?([A-Za-z_]\w*)(?:"\s*\])?\s*=\s*[^=\n-][^\n]*?,\s*--+\s*([^\n]+?)\s*$"#, text) {
                let comment = m[2]
                // Prose only: three or more words, not example values, code, or notes to self.
                let words = comment.split(separator: " ").filter { $0.contains(where: \.isLetter) }
                guard words.count >= 3, comment.first?.isLetter == true, comment != comment.uppercased(),
                      !comment.contains(where: { "=(){}[]|\"'".contains($0) }),
                      !["todo", "fixme", "xxx", "hack"].contains(where: { comment.lowercased().hasPrefix($0) }) else { continue }
                // Matched by the key's name anywhere in the source, so it may describe another table's key.
                put(SVSourceName(title: nil, detail: comment, source: .comment, isGuess: true), key: m[1], parent: "")
            }
            // Tables keyed by constants: `for _, x in pairs(MyAddon.Types) do MyAddon.Default.byType[x] = {} end`.
            for m in matches(#"for\s+\w+\s*,\s*(\w+)\s+in\s+i?pairs\s*\(\s*([\w.]+)\s*\)\s*do\s+[\w.]+\.(\w+)\s*\[\s*\1\s*\]\s*="#, text) {
                let list = m[2].split(separator: ".").last.map(String.init) ?? m[2], table = m[3]
                guard let literal = tableLiteral(named: list, in: sources) else { continue }
                let names = literal.split(whereSeparator: \.isNewline)
                    .map { $0.components(separatedBy: "--")[0] }
                    .flatMap { $0.split(whereSeparator: { ",{} \t".contains($0) }) }
                    .map(String.init)
                    .filter { $0.firstMatch(#"^[A-Z][A-Z0-9_]+$"#) != nil }
                guard !names.isEmpty else { continue }
                let prefix = commonPrefix(names)
                let known = names.compactMap { name in constants[name].map { (name, $0) } }
                if known.count == names.count {
                    for (name, n) in known {
                        put(SVSourceName(title: name, detail: nil, source: .constant, isGuess: true), key: String(n), parent: table)
                    }
                } else {
                    let sample = names.prefix(3).joined(separator: ", ")
                    let keyedBy = prefix.isEmpty ? String(localized: "game constants", bundle: .module) : String(localized: "\(prefix)* values", bundle: .module)
                    result.tableNotes[table] = String(localized: "Keyed by \(keyedBy), like \(sample): numbers the game sets, which the addon's source doesn't spell out.", bundle: .module)
                }
            }
            // Addon constants used directly as keys: `MyAddon.sv.modes[MODE_FAST] = …`.
            for m in matches(#"\.(\w+)\s*\[\s*(?:[A-Za-z_]\w*\.)*([A-Z][A-Z0-9_]{2,})\s*\]"#, text) {
                guard let n = constants[m[2]] else { continue }
                put(SVSourceName(title: m[2], detail: nil, source: .constant, isGuess: true), key: String(n), parent: m[1])
            }
        }
        // Constants the code compares a key with: `if sv.mode == MyAddon.MODE_COMBAT then`.
        var compared: [String: [String: Int]] = [:]
        for text in sources {
            let pattern = #"\.([A-Za-z_]\w*)\s*[~=]=\s*(?:[A-Za-z_]\w*\.)*([A-Z][A-Z0-9_]{2,})\b|\b(?:[A-Za-z_]\w*\.)*([A-Z][A-Z0-9_]{2,})\s*[~=]=\s*[\w.]*\.([A-Za-z_]\w*)\b"#
            for m in matches(pattern, text) {
                let key = m[1].isEmpty ? m[4] : m[1], name = m[1].isEmpty ? m[3] : m[2]
                guard let n = constants[name], !key.isEmpty else { continue }
                compared[key, default: [:]][name] = n
            }
        }
        for (key, found) in compared where found.count >= 2 {
            let prefix = commonPrefix(Array(found.keys))
            let choices = found.sorted { $0.value < $1.value }.map { name, n in
                SVControl.Choice(value: String(n), label: SVReadable.label(.string(name.dropFirst(prefix.count).lowercased())))
            }
            putControl(SVControl(type: "constants", choices: choices), key: key, parent: "")
        }
        // A key named differently by two panels is left to its parent's match.
        for key in ambiguous { result.names[""]?[key] = nil }
        // A key matched only by its name might be in another table: a guess, unless the key is distinctive.
        for (key, name) in result.names[""] ?? [:] where name.source == .settingsPanel && key.count < 4 {
            result.names[""]?[key] = SVSourceName(title: name.title, detail: name.detail, source: name.source, isGuess: true)
        }
        if result.names[""]?.isEmpty == true { result.names[""] = nil }
        return result
    }

    // MARK: Text helpers

    /// `MyAddon.sv["a b"].c` -> ["MyAddon", "sv", "a b", "c"].
    static func components(_ chain: String) -> [String] {
        matches(#"[A-Za-z_]\w*|\[\s*"([^"]*)"\s*\]"#, chain).map { $0[1].isEmpty ? $0[0] : $0[1] }
    }

    /// The `{ … }` around a position, as text; nil when it's longer than a control would be.
    static func enclosingTable(_ u: [UInt16], at location: Int) -> String? {
        enclosingBounds(u, at: location).map { flatten(u, $0) }
    }

    /// The offsets of the `{` and `}` around a position; nil when it's longer than a control would be.
    static func enclosingBounds(_ u: [UInt16], at location: Int) -> (start: Int, end: Int)? {
        let open = UInt16(UInt8(ascii: "{")), close = UInt16(UInt8(ascii: "}"))
        var depth = 0, start = location - 1
        while start >= 0 {
            if u[start] == close { depth += 1 } else if u[start] == open { if depth == 0 { break }; depth -= 1 }
            start -= 1
            if location - start > 8_000 { return nil }
        }
        guard start >= 0 else { return nil }
        depth = 0
        var end = start + 1
        while end < u.count {
            if u[end] == open { depth += 1 } else if u[end] == close { if depth == 0 { break }; depth -= 1 }
            end += 1
            if end - start > 16_000 { return nil }
        }
        return end < u.count ? (start, end) : nil
    }

    /// Only the control's own level: nested tables (choices, a submenu's controls) are dropped.
    static func flatten(_ u: [UInt16], _ bounds: (start: Int, end: Int)) -> String {
        let open = UInt16(UInt8(ascii: "{")), close = UInt16(UInt8(ascii: "}"))
        var flat: [UInt16] = [], level = 0
        for c in u[(bounds.start + 1)..<bounds.end] {
            if c == open { level += 1 } else if c == close { level -= 1 } else if level == 0 { flat.append(c) }
        }
        return String(decoding: flat, as: UTF16.self)
    }

    /// A LibAddonMenu control's type, range, default, and choices. `block` is the control's own level,
    /// `full` includes its nested tables, where `choices` and `choicesValues` are.
    static func lamControl(block: String, full: String, sources: [String], constants: [String: Int],
                           resolve: (String) -> String?) -> SVControl {
        let type = block.firstMatch(#"(?<![\w.])type\s*=\s*"(\w+)""#, group: 1) ?? "control"
        func number(_ field: String) -> Double? {
            block.firstMatch(#"(?<![\w.])\#(field)\s*=\s*(-?\d+(?:\.\d+)?)\b"#, group: 1).flatMap(Double.init)
        }
        /// The items of `field = { … }` in the control, or of the table a name there points to.
        func list(_ field: String) -> [String]? {
            if let r = full.range(of: #"(?<![\w.])\#(field)\s*=\s*\{"#, options: .regularExpression) {
                var depth = 1, i = r.upperBound
                while i < full.endIndex, depth > 0 {
                    if full[i] == "{" { depth += 1 } else if full[i] == "}" { depth -= 1 }
                    i = full.index(after: i)
                }
                return items(String(full[r.upperBound..<full.index(before: i)]))
            }
            if let name = block.firstMatch(#"(?<![\w.])\#(field)\s*=\s*([A-Za-z_][\w.]*)"#, group: 1),
               let last = name.split(separator: ".").last, let literal = tableLiteral(named: String(last), in: sources) {
                return items(literal)
            }
            return nil
        }
        func value(_ raw: String) -> String? {
            if let v = SVControl.normalize(literal: raw) { return v }
            let name = raw.split(separator: ".").last.map(String.init) ?? raw
            return constants[name].map(String.init)
        }
        var choices: [SVControl.Choice] = []
        if let labels = list("choices") {
            let names = labels.map { resolve($0) ?? SVControl.normalize(literal: $0) }
            if let values = list("choicesValues"), values.count == labels.count {
                for (label, raw) in zip(names, values) { if let label, let v = value(raw) { choices.append(.init(value: v, label: label)) } }
            } else {
                // Without choicesValues, LibAddonMenu saves the label itself.
                for label in names { if let label { choices.append(.init(value: label, label: label)) } }
            }
        }
        let defaultValue = block.firstMatch(#"(?<![\w.])default\s*=\s*("(?:[^"\\]|\\.)*"|true|false|-?\d+(?:\.\d+)?)"#, group: 1)
            .flatMap(SVControl.normalize(literal:))
        let isSlider = type == "slider"
        return SVControl(type: type, min: isSlider ? number("min") : nil, max: isSlider ? number("max") : nil,
                         step: isSlider ? number("step") : nil, choices: choices, defaultValue: defaultValue)
    }

    /// The top-level items of a table literal's contents: `"A", "B", SI_X` -> ["\"A\"", "\"B\"", "SI_X"].
    static func items(_ text: String) -> [String] {
        var out: [String] = [], current = "", depth = 0, inString = false, inComment = false, escaped = false
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            if inComment { if c == "\n" { inComment = false }; continue }
            if inString {
                current.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "-" where i + 1 < chars.count && chars[i + 1] == "-": inComment = true
            case "\"": inString = true; current.append(c)
            case "{", "(": depth += 1; current.append(c)
            case "}", ")": depth -= 1; current.append(c)
            case "," where depth == 0, ";" where depth == 0: out.append(current); current = ""
            default: current.append(c)
            }
        }
        out.append(current)
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// The text of `Name = { … }` in any of the sources.
    static func tableLiteral(named name: String, in sources: [String]) -> String? {
        for text in sources {
            guard let r = text.range(of: #"(?<![\w])\#(NSRegularExpression.escapedPattern(for: name))\s*=\s*\{"#, options: .regularExpression) else { continue }
            var depth = 1, i = r.upperBound
            while i < text.endIndex, depth > 0 {
                if text[i] == "{" { depth += 1 } else if text[i] == "}" { depth -= 1 }
                i = text.index(after: i)
            }
            return String(text[r.upperBound..<text.index(before: i)])
        }
        return nil
    }

    static func commonPrefix(_ names: [String]) -> String {
        guard var prefix = names.first else { return "" }
        for n in names.dropFirst() { while !n.hasPrefix(prefix) { prefix.removeLast() } }
        // Up to a whole word: "SETTING_TYPE_A" and "SETTING_TYPE_AUDIO" share "SETTING_TYPE_".
        if let i = prefix.lastIndex(of: "_") { return String(prefix[...i]) }
        return ""
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: #"\""#, with: "\"").replacingOccurrences(of: #"\n"#, with: " ")
    }

    static func matches(_ pattern: String, _ text: String) -> [[String]] { rangedMatches(pattern, text).map(\.groups) }

    static func rangedMatches(_ pattern: String, _ text: String) -> [(location: Int, groups: [String])] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (m.range.location, (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) })
        }
    }
}

extension String {
    func firstMatch(_ pattern: String, group: Int = 0) -> String? {
        SVSourceNames.matches(pattern, self).first.map { $0[group] }
    }
}
