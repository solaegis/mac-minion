import Foundation

/// What an addon's own Lua source says a saved key means. See docs/SOURCE-NAMES.md.
public struct SVSourceName: Sendable, Equatable {
    public enum Source: String, Sendable {
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
public struct SVSourceNames: Sendable, Equatable {
    /// Parent key ("" for any) -> key -> name.
    var names: [String: [String: SVSourceName]] = [:]
    /// Table key -> what its keys are, for tables keyed by constants.
    var tableNotes: [String: String] = [:]

    public init() {}

    public var isEmpty: Bool { names.isEmpty && tableNotes.isEmpty }
    public var count: Int { names.values.reduce(0) { $0 + $1.count } }

    /// A name for `key` in the table at `parent`: matched with its parent key first, then by itself.
    public func name(for key: LuaKey, at parent: [LuaKey]) -> SVSourceName? {
        let k = key.description
        if let p = parent.last?.description, let exact = names[p]?[k] { return exact }
        return names[""]?[k]
    }

    /// What the keys of the table at `key` are, like "SETTING_TYPE_* values".
    public func note(forTable key: LuaKey) -> String? { tableNotes[key.description] }

    // MARK: Reading

    /// Lua files bigger than this are data, not code with settings: skipped.
    public static let maxFileBytes = 1_500_000

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
                guard let block = enclosingTable(u, at: m.location) else { continue }
                let title = block.firstMatch(#"(?<![\w.])name\s*=\s*("(?:[^"\\]|\\.)*"|GetString\s*\(\s*SI_\w+\s*\)|SI_[A-Z0-9_]+)"#, group: 1).flatMap(resolve)
                let tip = block.firstMatch(#"(?<![\w.])tooltip\s*=\s*("(?:[^"\\]|\\.)*"|GetString\s*\(\s*SI_\w+\s*\)|SI_[A-Z0-9_]+)"#, group: 1).flatMap(resolve)
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
        // Only the control's own level: nested tables (choices, a submenu's controls) are dropped.
        var flat: [UInt16] = [], level = 0
        for c in u[(start + 1)..<min(end, u.count)] {
            if c == open { level += 1 } else if c == close { level -= 1 } else if level == 0 { flat.append(c) }
        }
        return String(decoding: flat, as: UTF16.self)
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
