import Foundation

/// Changes values in a SavedVariables file in place: only the entry that changes is rewritten, in the game's own
/// format (`["key"] = value,`, four spaces a level), and every other byte stays as it was. The game must be
/// closed: it writes its own copy over the file when it quits.
public enum SVEdit {
    /// Set `value` at `path`, the variable first. Missing tables on the way are made.
    public struct Change: Sendable {
        public let path: [LuaKey]
        public let value: LuaValue

        public init(path: [LuaKey], value: LuaValue) { self.path = path; self.value = value }
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// The file doesn't read cleanly, so a change could land in the wrong place.
        case unreadable(String)
        /// The path names no variable in the file, or runs into a value that isn't a table.
        case noPlace(String)

        public var description: String {
            switch self {
            case .unreadable(let why): String(localized: "The file doesn't read cleanly: \(why)", bundle: .module)
            case .noPlace(let path): String(localized: "There's no place for \(path) in the file.", bundle: .module)
            }
        }
    }

    /// Applies the changes in order, reading the file again between them, so each lands on the latest text.
    public static func apply(_ changes: [Change], to data: Data) throws -> Data {
        var data = data
        for change in changes { data = try apply(change, to: data) }
        return data
    }

    static func apply(_ change: Change, to data: Data) throws -> Data {
        let doc = SVDocument.parse(data)
        if let error = doc.error { throw Failure.unreadable(error.description) }
        let where_ = change.path.map(\.description).joined(separator: " › ")
        guard let first = change.path.first, change.path.count > 1,
              var table = doc.variables.first(where: { $0.key == first })?.value.table else { throw Failure.noPlace(where_) }
        var depth = 1
        let rest = Array(change.path.dropFirst())
        for (i, key) in rest.enumerated() {
            let last = i == rest.count - 1
            if let entry = table.entries.first(where: { $0.key == key }) {
                if last {
                    let text = Self.key(key) + " = " + Self.value(change.value, indent: depth)
                    return splice(data, entry.span, Data(text.utf8))
                }
                guard let inner = entry.value.table else { throw Failure.noPlace(where_) }
                table = inner
                depth += 1
                continue
            }
            // Missing from here down: one new entry holding the rest of the path.
            var value = change.value
            for k in rest[(i + 1)...].reversed() { value = .table(LuaTable(entries: [LuaEntry(key: k, value: value, span: 0..<0)], span: 0..<0)) }
            return insert(Self.key(key) + " = " + Self.value(value, indent: depth), into: table, depth: depth, data: data)
        }
        throw Failure.noPlace(where_)
    }

    /// Adds an entry as the table's last, with a comma after the one before it if it has none.
    static func insert(_ entry: String, into table: LuaTable, depth: Int, data: Data) -> Data {
        let bytes = [UInt8](data)
        let close = table.span.upperBound - 1
        var end = close
        while end > table.span.lowerBound, [9, 10, 13, 32].contains(bytes[end - 1]) { end -= 1 }
        let previous = bytes[end - 1]
        var text = previous == UInt8(ascii: "{") || previous == UInt8(ascii: ",") ? "" : ","
        text += "\n" + indent(depth) + entry + ","
        if end == close { text += "\n" + indent(depth - 1) }
        return splice(data, end..<end, Data(text.utf8))
    }

    static func splice(_ data: Data, _ range: Range<Int>, _ text: Data) -> Data {
        var out = Data(data[data.startIndex..<data.startIndex + range.lowerBound])
        out.append(text)
        out.append(data[(data.startIndex + range.upperBound)...])
        return out
    }

    static func indent(_ depth: Int) -> String { String(repeating: "    ", count: max(depth, 0)) }

    /// `["name"]`, `[3]`, as the game writes keys.
    public static func key(_ key: LuaKey) -> String {
        switch key {
        case .string(let s): "[" + quoted(s) + "]"
        case .integer(let n): "[\(n)]"
        case .number(let n): "[\(number(n))]"
        case .bool(let b): "[\(b)]"
        }
    }

    /// A value as Lua; a table's entries go one level deeper than `indent`.
    public static func value(_ value: LuaValue, indent depth: Int) -> String {
        switch value {
        case .string(let s): quoted(s)
        case .integer(let n): String(n)
        case .number(let n): number(n)
        case .bool(let b): String(b)
        case .nil: "nil"
        case .table(let table):
            "{\n" + table.entries.map { indent(depth + 1) + key($0.key) + " = " + self.value($0.value, indent: depth + 1) + ",\n" }.joined()
                + indent(depth) + "}"
        }
    }

    static func number(_ n: Double) -> String {
        if n.isNaN { return "0" }
        if n.isInfinite { return n > 0 ? "math.huge" : "-math.huge" }
        return "\(n)"
    }

    static func quoted(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 { out += "\\" + String(scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }
}
