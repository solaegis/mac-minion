import Foundation

/// A SavedVariables file read as data: the subset of Lua the game's serializer writes
/// (`Name = { ["key"] = value, [1] = value }`), never run. See docs/research/SAVEDVARIABLES.md.
public struct SVDocument: Sendable {
    /// The file's top-level assignments, in order.
    public let variables: [LuaEntry]
    /// Set when the file ends early or breaks; everything before it is in `variables`.
    public let error: LuaParseError?
    public let byteCount: Int

    public init(variables: [LuaEntry], error: LuaParseError?, byteCount: Int) {
        self.variables = variables; self.error = error; self.byteCount = byteCount
    }

    public static func read(_ url: URL) throws -> SVDocument {
        parse(try Data(contentsOf: url, options: .mappedIfSafe))
    }

    public static func parse(_ data: Data) -> SVDocument {
        data.withUnsafeBytes { raw in
            var parser = LuaParser(bytes: raw.bindMemory(to: UInt8.self))
            let variables = parser.parseFile()
            return SVDocument(variables: variables, error: parser.error, byteCount: data.count)
        }
    }

    public subscript(name: String) -> LuaValue? {
        variables.first { $0.key == .string(name) }?.value
    }

    /// The table literal assigned right after `marker` in a Lua source file, like LibZone's `["en"] = {`.
    /// Takes the first place the marker is followed by `= {` (or `{`) and the table parses, so a mention
    /// in a comment is skipped. Reads the data without running the file around it.
    public static func table(in data: Data, after marker: String) -> LuaTable? {
        let needle = Data(marker.utf8)
        var searchFrom = data.startIndex
        while let found = data.range(of: needle, in: searchFrom..<data.endIndex) {
            searchFrom = found.upperBound
            let table = data.withUnsafeBytes { raw -> LuaTable? in
                var parser = LuaParser(bytes: raw.bindMemory(to: UInt8.self))
                parser.pos = found.upperBound - data.startIndex
                parser.skipSpace()
                if parser.peek == UInt8(ascii: "=") { parser.pos += 1; parser.skipSpace() }
                guard parser.peek == UInt8(ascii: "{") else { return nil }
                let table = parser.parseTable()
                return parser.error == nil ? table : nil
            }
            if let table { return table }
        }
        return nil
    }
}

public enum LuaKey: Hashable, Sendable, CustomStringConvertible {
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)

    /// As written in a path: `NA Megaserver`, `42`.
    public var description: String {
        switch self {
        case .string(let s): s
        case .integer(let n): String(n)
        case .number(let n): String(n)
        case .bool(let b): String(b)
        }
    }
}

/// Not `indirect`: a table is already a class, so values sit inline in their entry instead of each taking
/// its own allocation (over a million of them in a big folder).
public enum LuaValue: Sendable {
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case `nil`
    case table(LuaTable)

    public var table: LuaTable? { if case .table(let t) = self { t } else { nil } }
    public var string: String? { if case .string(let s) = self { s } else { nil } }

    /// What kind of value, for type checks across files: "string", "number", "boolean", "nil", "table".
    public var typeName: String {
        switch self {
        case .string: "string"
        case .integer, .number: "number"
        case .bool: "boolean"
        case .nil: "nil"
        case .table: "table"
        }
    }
}

/// One `key = value` with the bytes it covers in the file, key through value.
public struct LuaEntry: Sendable {
    public let key: LuaKey
    public let value: LuaValue
    // Offsets as 32-bit numbers: SavedVariables files are far smaller than 4 GB, and a million entries save 8 bytes each.
    private let start: UInt32, end: UInt32
    public var span: Range<Int> { Int(start)..<Int(end) }

    public init(key: LuaKey, value: LuaValue, span: Range<Int>) {
        self.key = key; self.value = value
        start = UInt32(clamping: span.lowerBound); end = UInt32(clamping: span.upperBound)
    }

    /// An entry that stands for a key alone, to rebuild a row's path or ID.
    public static func placeholder(_ key: LuaKey) -> LuaEntry { LuaEntry(key: key, value: .nil, span: 0..<0) }
}

/// A table's entries in file order. A class, so large trees are shared rather than copied.
public final class LuaTable: Sendable {
    public let entries: [LuaEntry]
    /// `{` through `}`, or to where the file broke.
    public let span: Range<Int>

    init(entries: [LuaEntry], span: Range<Int>) { self.entries = entries; self.span = span }

    public var count: Int { entries.count }

    public subscript(key: LuaKey) -> LuaValue? { entries.first { $0.key == key }?.value }
    public subscript(key: String) -> LuaValue? { self[.string(key)] }

    /// Follows `path` down from this table.
    public func value(at path: [LuaKey]) -> LuaValue? {
        var current = LuaValue.table(self)
        for key in path {
            guard let next = current.table?[key] else { return nil }
            current = next
        }
        return current
    }
}

public struct LuaParseError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public let offset: Int
    public let line: Int
    public let column: Int
    /// The keys around the break, outermost first: where to look in the file.
    public let path: [LuaKey]
    /// True when the file simply stops, as when the game quit while writing it.
    public let endedEarly: Bool

    public var description: String {
        String(localized: "\(message) at line \(line), column \(column)", bundle: .module) + (path.isEmpty ? "" : " " + String(localized: "in \(path.map(\.description).joined(separator: " › "))", bundle: .module))
    }
}

/// Recursive descent over bytes. Never throws: on the first error it records it, stops, and
/// returns everything read so far, so a broken file is still browsable up to the break.
struct LuaParser {
    let bytes: UnsafeBufferPointer<UInt8>
    var pos = 0
    var path: [LuaKey] = []
    private(set) var error: LuaParseError?

    init(bytes: UnsafeBufferPointer<UInt8>) { self.bytes = bytes }

    mutating func parseFile() -> [LuaEntry] {
        var variables: [LuaEntry] = []
        skipSpace()
        while error == nil, pos < bytes.count {
            let start = pos
            guard let name = identifier() else { fail(String(localized: "Expected a variable name", bundle: .module)); break }
            skipSpace()
            guard expect(UInt8(ascii: "=")) else { break }
            path = [.string(name)]
            let value = parseValue()
            variables.append(LuaEntry(key: .string(name), value: value, span: start..<pos))
            skipSpace()
            if peek == UInt8(ascii: ";") { pos += 1; skipSpace() }
        }
        return variables
    }

    // MARK: Values

    mutating func parseValue() -> LuaValue {
        skipSpace()
        guard let c = peek else { fail(String(localized: "The file ends where a value should be", bundle: .module)); return .nil }
        switch c {
        case UInt8(ascii: "{"): return .table(parseTable())
        case UInt8(ascii: "\""), UInt8(ascii: "'"): return .string(parseString() ?? "")
        case UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "0")...UInt8(ascii: "9"): return parseNumber() ?? .nil
        default:
            switch identifier() {
            case "true": return .bool(true)
            case "false": return .bool(false)
            case "nil": return .nil
            case "math": // math.huge, which some serializers write for infinity
                if consume(".huge") { return .number(.infinity) }
                fail(String(localized: "Unexpected word", bundle: .module)); return .nil
            default: fail(String(localized: "Unexpected character “\(String(Character(Unicode.Scalar(c))))”", bundle: .module)); return .nil
            }
        }
    }

    mutating func parseTable() -> LuaTable {
        let start = pos
        pos += 1 // {
        var entries: [LuaEntry] = []
        var nextIndex: Int64 = 1
        while error == nil {
            skipSpace()
            guard let c = peek else { fail(String(localized: "The file ends inside a table", bundle: .module)); break }
            if c == UInt8(ascii: "}") { pos += 1; break }
            let entryStart = pos
            let key: LuaKey
            if c == UInt8(ascii: "[") {
                pos += 1
                skipSpace()
                guard let k = parseKey() else { break }
                key = k
                skipSpace()
                guard expect(UInt8(ascii: "]")) else { break }
                skipSpace()
                guard expect(UInt8(ascii: "=")) else { break }
            } else if let name = identifierFollowedByEquals() {
                key = .string(name)
            } else {
                key = .integer(nextIndex) // a list item without a key
                nextIndex += 1
            }
            path.append(key)
            let value = parseValue()
            if error == nil { path.removeLast() }
            entries.append(LuaEntry(key: key, value: value, span: entryStart..<pos))
            if error != nil { break }
            skipSpace()
            if let sep = peek, sep == UInt8(ascii: ",") || sep == UInt8(ascii: ";") { pos += 1 }
        }
        // Exactly as big as it needs: a growing array keeps up to twice the room, over every table in the file.
        return LuaTable(entries: entries.count == entries.capacity ? entries : entries.withUnsafeBufferPointer { Array($0) }, span: start..<pos)
    }

    mutating func parseKey() -> LuaKey? {
        guard let c = peek else { fail(String(localized: "The file ends inside a key", bundle: .module)); return nil }
        switch c {
        case UInt8(ascii: "\""), UInt8(ascii: "'"):
            return parseString().map(LuaKey.string)
        default:
            switch parseValue() {
            case .integer(let n): return .integer(n)
            case .number(let n): return .number(n)
            case .bool(let b): return .bool(b)
            default: if error == nil { fail(String(localized: "A key must be a string, number, or boolean", bundle: .module)) }; return nil
            }
        }
    }

    mutating func parseString() -> String? {
        let quote = bytes[pos]
        pos += 1
        let start = pos
        // Fast path: no escapes, so the bytes are the string.
        while pos < bytes.count, bytes[pos] != quote, bytes[pos] != UInt8(ascii: "\\") { pos += 1 }
        if pos < bytes.count, bytes[pos] == quote {
            let s = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<pos]), as: UTF8.self)
            pos += 1
            return s
        }
        var out = Array(bytes[start..<pos])
        while pos < bytes.count {
            let c = bytes[pos]
            if c == quote { pos += 1; return String(decoding: out, as: UTF8.self) }
            if c == UInt8(ascii: "\\"), pos + 1 < bytes.count {
                let e = bytes[pos + 1]
                pos += 2
                switch e {
                case UInt8(ascii: "n"): out.append(10)
                case UInt8(ascii: "r"): out.append(13)
                case UInt8(ascii: "t"): out.append(9)
                case UInt8(ascii: "a"): out.append(7)
                case UInt8(ascii: "b"): out.append(8)
                case UInt8(ascii: "f"): out.append(12)
                case UInt8(ascii: "v"): out.append(11)
                case UInt8(ascii: "\n"): out.append(10)
                case UInt8(ascii: "0")...UInt8(ascii: "9"):
                    // \ddd: up to three decimal digits, one byte.
                    var n = Int(e - UInt8(ascii: "0")), digits = 1
                    while digits < 3, let d = peek, d >= UInt8(ascii: "0"), d <= UInt8(ascii: "9") {
                        n = n * 10 + Int(d - UInt8(ascii: "0")); pos += 1; digits += 1
                    }
                    out.append(UInt8(truncatingIfNeeded: n))
                default: out.append(e) // \" \' \\ and anything else stand for themselves
                }
                continue
            }
            out.append(c)
            pos += 1
        }
        fail(String(localized: "The file ends inside a string", bundle: .module))
        return nil
    }

    mutating func parseNumber() -> LuaValue? {
        let start = pos
        if peek == UInt8(ascii: "-") { pos += 1 }
        var isInteger = true
        while let c = peek {
            if c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") { pos += 1; continue }
            if c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E") { isInteger = false; pos += 1; continue }
            if (c == UInt8(ascii: "-") || c == UInt8(ascii: "+")),
               pos > start, bytes[pos - 1] == UInt8(ascii: "e") || bytes[pos - 1] == UInt8(ascii: "E") { pos += 1; continue }
            break
        }
        let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<pos]), as: UTF8.self)
        if isInteger, let n = Int64(text) { return .integer(n) }
        if let n = Double(text) { return .number(n) }
        if pos == bytes.count { fail(String(localized: "The file ends inside a number", bundle: .module)) } else { pos = start; fail(String(localized: "“\(text)” isn't a number", bundle: .module)) }
        return nil
    }

    // MARK: Lexing

    var peek: UInt8? { pos < bytes.count ? bytes[pos] : nil }

    /// Skips spaces, newlines, and `--` comments (line and `--[[ ]]`).
    mutating func skipSpace() {
        while pos < bytes.count {
            let c = bytes[pos]
            if c == 32 || c == 9 || c == 10 || c == 13 { pos += 1; continue }
            if c == UInt8(ascii: "-"), pos + 1 < bytes.count, bytes[pos + 1] == UInt8(ascii: "-") {
                pos += 2
                if consume("[[") {
                    while pos + 1 < bytes.count, !(bytes[pos] == UInt8(ascii: "]") && bytes[pos + 1] == UInt8(ascii: "]")) { pos += 1 }
                    pos = min(pos + 2, bytes.count)
                } else {
                    while pos < bytes.count, bytes[pos] != 10 { pos += 1 }
                }
                continue
            }
            break
        }
    }

    mutating func identifier() -> String? {
        let start = pos
        while let c = peek, c == UInt8(ascii: "_") || (c | 0x20 >= UInt8(ascii: "a") && c | 0x20 <= UInt8(ascii: "z"))
                || (pos > start && c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")) { pos += 1 }
        return pos > start ? String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<pos]), as: UTF8.self) : nil
    }

    /// `name =` inside a table; leaves the position alone when it isn't one.
    mutating func identifierFollowedByEquals() -> String? {
        let start = pos
        guard let name = identifier(), !["true", "false", "nil"].contains(name) else { pos = start; return nil }
        skipSpace()
        if peek == UInt8(ascii: "="), pos + 1 >= bytes.count || bytes[pos + 1] != UInt8(ascii: "=") { pos += 1; return name }
        pos = start
        return nil
    }

    mutating func consume(_ text: String) -> Bool {
        let utf8 = Array(text.utf8)
        guard pos + utf8.count <= bytes.count, zip(bytes[pos..<(pos + utf8.count)], utf8).allSatisfy({ $0 == $1 }) else { return false }
        pos += utf8.count
        return true
    }

    mutating func expect(_ c: UInt8) -> Bool {
        if peek == c { pos += 1; return true }
        fail(peek == nil ? String(localized: "The file ends where “\(String(Character(Unicode.Scalar(c))))” should be", bundle: .module) : String(localized: "Expected “\(String(Character(Unicode.Scalar(c))))”", bundle: .module))
        return false
    }

    mutating func fail(_ message: String) {
        guard error == nil else { return }
        let at = min(pos, bytes.count)
        var line = 1, lineStart = 0
        for i in 0..<at where bytes[i] == 10 { line += 1; lineStart = i + 1 }
        error = LuaParseError(message: message, offset: at, line: line, column: at - lineStart + 1, path: path,
                              endedEarly: at >= bytes.count)
    }
}

extension LuaKey {
    /// Order for showing keys: numbers in numeric order first, then everything else by name.
    public static func displayOrder(_ a: LuaKey, _ b: LuaKey) -> Bool {
        switch (a, b) {
        case (.integer(let x), .integer(let y)): return x < y
        case (.integer, _): return true
        case (_, .integer): return false
        default: return a.description.localizedStandardCompare(b.description) == .orderedAscending
        }
    }
}
