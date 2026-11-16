import Foundation

/// An addon's default settings, read from its own Lua (S-070): the table it passes as `defaults` when it
/// makes its saved variables with `ZO_SavedVars:New…` or LibSavedVars. A character with no settings of their
/// own runs on these. Read, never run: game constants (`ITEM_FUNCTIONAL_QUALITY_ARCANE`) and expressions are
/// kept as unresolved text, never a guessed value, and defaults an addon fills in with code are missed. The
/// companion's capture from inside the game (`CompanionSVLayout.defaults`) is exact and wins when present.
public enum SVDefaults {
    /// One saved variable's defaults.
    public struct Found: Sendable {
        /// The saved variable, as the manifest declares it: `AutoResearch_Character`.
        public let variable: String
        public let table: LuaTable
        /// Paths in `table` whose value the source gives as a constant or expression, with that text.
        public let unresolved: [[LuaKey]: String]
        /// Made with LibSavedVars, which falls back to account-wide settings for a character without a table.
        public let libSavedVars: Bool

        public init(variable: String, table: LuaTable, unresolved: [[LuaKey]: String] = [:], libSavedVars: Bool) {
            self.variable = variable
            self.table = table
            self.unresolved = unresolved
            self.libSavedVars = libSavedVars
        }
    }

    static let constructors: Set<String> = ["New", "NewAccountWide", "NewCharacterIdSettings", "NewCharacterNameSettings",
                                            "NewCharacterSettings"]

    /// Each declared saved variable's defaults that the sources make plain, by variable name.
    public static func parse(sources: [String], variables: [String]) -> [String: Found] {
        var aliases: Set<String> = ["LibSavedVars"]
        for text in sources {
            for m in SVSourceNames.matches(#"(?:local\s+)?([A-Za-z_]\w*)\s*=\s*LibSavedVars\b"#, text) { aliases.insert(m[1]) }
        }
        var found: [String: Found] = [:]
        for text in sources {
            let u = Array(text.utf16)
            for m in SVSourceNames.rangedMatches(#"([A-Za-z_]\w*)\s*:\s*(New\w*)\s*\("#, text) {
                let receiver = m.groups[1], ctor = m.groups[2]
                guard constructors.contains(ctor), receiver == "ZO_SavedVars" || aliases.contains(receiver) else { continue }
                // The match ends at "(": its offset plus the match's length, in UTF-16 like the text.
                guard let open = indexOfOpenParen(u, from: m.location) else { continue }
                let args = arguments(u, from: open + 1)
                guard let first = args.first, let variable = resolveVariable(first, variables: variables),
                      found[variable] == nil else { continue }
                // ZO_SavedVars and LibSavedVars both shift: a table where the version or namespace goes is the defaults.
                guard let literal = args.dropFirst().prefix(3).lazy.compactMap({ tableText($0, sources: sources) }).first else { continue }
                var parser = LiteralParser(text: literal)
                let table = parser.table(at: [])
                found[variable] = Found(variable: variable, table: table, unresolved: parser.unresolved,
                                        libSavedVars: receiver != "ZO_SavedVars")
            }
        }
        return found
    }

    static func indexOfOpenParen(_ u: [UInt16], from start: Int) -> Int? {
        var i = start
        while i < u.count { if u[i] == 40 { return i }; i += 1 }
        return nil
    }

    /// The call's arguments as text, split on top-level commas, up to its closing parenthesis.
    static func arguments(_ u: [UInt16], from start: Int) -> [String] {
        var args: [String] = []
        var depth = 0, i = start, from = start
        func flush(_ end: Int) {
            let text = String(decoding: u[from..<end], as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { args.append(text) }
        }
        while i < u.count {
            let c = u[i]
            if c == 34 || c == 39 { i = LiteralParser.skipString(u, at: i); continue }
            if c == 45, i + 1 < u.count, u[i + 1] == 45 { i = LiteralParser.skipComment(u, at: i); continue }
            if c == 40 || c == 123 || c == 91 { depth += 1 }
            if c == 41 || c == 125 || c == 93 {
                if depth == 0 { flush(i); return args }
                depth -= 1
            }
            if c == 44, depth == 0 { flush(i); from = i + 1 }
            i += 1
        }
        return args
    }

    /// The saved variable a name argument stands for: a string literal, or the one declared name that ends
    /// with the literal part of `self.name .. "_Character"`, or the only one declared.
    static func resolveVariable(_ arg: String, variables: [String]) -> String? {
        let pieces = SVSourceNames.matches(#""([^"]*)"|'([^']*)'"#, arg).map { $0[1].isEmpty ? $0[2] : $0[1] }
        if pieces.count == 1, arg.hasPrefix("\"") || arg.hasPrefix("'"), arg.dropFirst().dropLast() == pieces[0] {
            return variables.isEmpty || variables.contains(pieces[0]) ? pieces[0] : nil
        }
        if let piece = pieces.last, !piece.isEmpty {
            let matching = variables.filter { $0.hasSuffix(piece) }
            if matching.count == 1 { return matching[0] }
        }
        return variables.count == 1 ? variables[0] : nil
    }

    /// The text inside a table argument's braces: written in place, or a name (`self.defaults`) whose last part
    /// is assigned a table literal somewhere in the sources.
    static func tableText(_ arg: String, sources: [String]) -> String? {
        if arg.hasPrefix("{"), arg.hasSuffix("}") { return String(arg.dropFirst().dropLast()) }
        guard arg.range(of: #"^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$"#, options: .regularExpression) != nil,
              let last = arg.split(separator: ".").last else { return nil }
        return SVSourceNames.tableLiteral(named: String(last), in: sources)
    }
}

/// Reads a Lua table constructor's contents the way an addon writes them: `key = value`, `["key"] = value`,
/// `[1] = value`, and positional values, with comments. Values it can't read as a literal are recorded as
/// unresolved text.
struct LiteralParser {
    let u: [UInt16]
    var i = 0
    var unresolved: [[LuaKey]: String] = [:]

    init(text: String) { u = Array(text.utf16) }

    /// Entries up to the closing brace (or the end of the text).
    mutating func table(at path: [LuaKey]) -> LuaTable {
        var entries: [LuaEntry] = []
        var position: Int64 = 1
        while true {
            skipSpace()
            guard i < u.count else { break }
            let c = u[i]
            if c == 125 { i += 1; break }
            if c == 44 || c == 59 { i += 1; continue }
            var key: LuaKey?
            var keyKnown = true
            if c == 91, !(i + 1 < u.count && (u[i + 1] == 91 || u[i + 1] == 61)) {
                // [expr] = value
                i += 1
                let keyText = raw(until: [93]).trimmingCharacters(in: .whitespacesAndNewlines)
                if i < u.count { i += 1 }
                skipSpace()
                if i < u.count, u[i] == 61 { i += 1 }
                key = Self.literalKey(keyText)
                keyKnown = key != nil
            } else if let name = identifierThenEquals() {
                key = .string(name)
            }
            if key == nil, keyKnown {
                key = .integer(position)
                position += 1
            }
            skipSpace()
            guard i < u.count else { break }
            if u[i] == 123 {
                i += 1
                let inner = table(at: path + (key.map { [$0] } ?? []))
                if let key { entries.append(LuaEntry(key: key, value: .table(inner), span: 0..<0)) }
                continue
            }
            let text = raw(until: [44, 59, 125]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let key else { continue }
            if let value = Self.literalValue(text) {
                if case .nil = value { continue }
                entries.append(LuaEntry(key: key, value: value, span: 0..<0))
            } else if !text.isEmpty {
                unresolved[path + [key]] = text
            }
        }
        return LuaTable(entries: entries, span: 0..<0)
    }

    /// `name =` (not `==`) at the cursor: consumes it and returns the name; otherwise leaves the cursor.
    mutating func identifierThenEquals() -> String? {
        let start = i
        guard i < u.count, Self.isIdentStart(u[i]) else { return nil }
        while i < u.count, Self.isIdent(u[i]) { i += 1 }
        let name = String(decoding: u[start..<i], as: UTF16.self)
        skipSpace()
        if i < u.count, u[i] == 61, !(i + 1 < u.count && u[i + 1] == 61) {
            i += 1
            return name
        }
        i = start
        return nil
    }

    /// Text up to a top-level stop character (not consumed), past strings, comments, and brackets.
    mutating func raw(until stops: Set<UInt16>) -> String {
        let start = i
        var depth = 0
        while i < u.count {
            let c = u[i]
            if c == 34 || c == 39 { i = Self.skipString(u, at: i); continue }
            if c == 91, i + 1 < u.count, u[i + 1] == 91 || u[i + 1] == 61 { i = Self.skipLongBracket(u, at: i); continue }
            if c == 45, i + 1 < u.count, u[i + 1] == 45 { i = Self.skipComment(u, at: i); continue }
            if depth == 0, stops.contains(c) { break }
            if c == 40 || c == 123 || c == 91 { depth += 1 }
            if c == 41 || c == 125 || c == 93 { depth -= 1 }
            i += 1
        }
        return String(decoding: u[start..<min(i, u.count)], as: UTF16.self)
    }

    mutating func skipSpace() {
        while i < u.count {
            let c = u[i]
            if c == 32 || c == 9 || c == 10 || c == 13 { i += 1; continue }
            if c == 45, i + 1 < u.count, u[i + 1] == 45 { i = Self.skipComment(u, at: i); continue }
            break
        }
    }

    static func isIdentStart(_ c: UInt16) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 }
    static func isIdent(_ c: UInt16) -> Bool { isIdentStart(c) || (c >= 48 && c <= 57) }

    /// Past a quoted string starting at `at`.
    static func skipString(_ u: [UInt16], at: Int) -> Int {
        let quote = u[at]
        var i = at + 1
        while i < u.count {
            if u[i] == 92 { i += 2; continue }
            if u[i] == quote { return i + 1 }
            if u[i] == 10 { return i }
            i += 1
        }
        return i
    }

    /// Past `[[…]]` or `[==[…]==]` starting at `at`.
    static func skipLongBracket(_ u: [UInt16], at: Int) -> Int {
        var i = at + 1, level = 0
        while i < u.count, u[i] == 61 { level += 1; i += 1 }
        guard i < u.count, u[i] == 91 else { return at + 1 }
        i += 1
        while i < u.count {
            if u[i] == 93 {
                var j = i + 1, l = 0
                while j < u.count, u[j] == 61 { l += 1; j += 1 }
                if l == level, j < u.count, u[j] == 93 { return j + 1 }
            }
            i += 1
        }
        return i
    }

    /// Past a `--` comment, line or long.
    static func skipComment(_ u: [UInt16], at: Int) -> Int {
        var i = at + 2
        if i < u.count, u[i] == 91, i + 1 < u.count, u[i + 1] == 91 || u[i + 1] == 61 {
            let end = skipLongBracket(u, at: i)
            if end > i + 1 { return end }
        }
        while i < u.count, u[i] != 10 { i += 1 }
        return i
    }

    static func literalKey(_ text: String) -> LuaKey? {
        switch literalValue(text) {
        case .string(let s)?: .string(s)
        case .integer(let n)?: .integer(n)
        case .number(let d)?: .number(d)
        case .bool(let b)?: .bool(b)
        default: nil
        }
    }

    /// A value written as a literal: a string, a number, true, false, or nil. Nil for anything else.
    static func literalValue(_ text: String) -> LuaValue? {
        guard !text.isEmpty else { return nil }
        if text == "true" { return .bool(true) }
        if text == "false" { return .bool(false) }
        if text == "nil" { return .nil }
        if let first = text.first, first == "\"" || first == "'", text.count >= 2, text.last == first {
            let body = String(text.dropFirst().dropLast())
            // One string, not `"a" .. "b"`.
            var escaped = false
            for ch in body {
                if escaped { escaped = false; continue }
                if ch == "\\" { escaped = true; continue }
                if ch == first { return nil }
            }
            return .string(SVSourceNames.unescape(body))
        }
        if text.hasPrefix("[[") || text.hasPrefix("[="), text.hasSuffix("]") {
            let u = Array(text.utf16)
            if skipLongBracket(u, at: 0) == u.count, let open = text.firstIndex(of: "["), let inner = text[text.index(after: open)...].firstIndex(of: "[") {
                let level = text.distance(from: open, to: inner) - 1
                return .string(String(text[text.index(after: inner)..<text.index(text.endIndex, offsetBy: -(level + 2))]))
            }
        }
        let lower = text.lowercased()
        if lower.hasPrefix("0x") || lower.hasPrefix("-0x") {
            let negative = lower.hasPrefix("-")
            if let n = Int64(lower.dropFirst(negative ? 3 : 2), radix: 16) { return .integer(negative ? -n : n) }
            return nil
        }
        if let n = Int64(text) { return .integer(n) }
        if text.range(of: #"^-?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$"#, options: .regularExpression) != nil, let d = Double(text) {
            return .number(d)
        }
        return nil
    }
}
