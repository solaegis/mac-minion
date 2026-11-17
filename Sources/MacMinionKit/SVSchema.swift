import Foundation

/// What an addon's source says a saved value may be: a LibAddonMenu control's type, a slider's range,
/// or a dropdown's choices, and the constants the code compares the key with. See docs/SOURCE-NAMES.md.
public struct SVControl: Sendable, Equatable {
    /// One value the setting can take, and what the addon calls it.
    public struct Choice: Sendable, Equatable {
        /// The saved value, normalized by `SVControl.normalize`: "3", "true", or the string itself.
        public let value: String
        public let label: String
        public init(value: String, label: String) { self.value = value; self.label = label }
    }

    /// The LibAddonMenu control type ("slider", "dropdown", "checkbox", …), or "constants" when the
    /// choices come from constants the code compares the key with.
    public var type: String
    public var min: Double?
    public var max: Double?
    public var step: Double?
    public var choices: [Choice]
    /// The control's `default`, normalized like a choice's value.
    public var defaultValue: String?

    public init(type: String, min: Double? = nil, max: Double? = nil, step: Double? = nil,
                choices: [Choice] = [], defaultValue: String? = nil) {
        self.type = type; self.min = min; self.max = max; self.step = step
        self.choices = choices; self.defaultValue = defaultValue
    }

    /// Nothing worth showing: no range and no choices.
    public var isEmpty: Bool { min == nil && max == nil && choices.isEmpty }

    public var range: ClosedRange<Double>? {
        guard let min, let max, min <= max else { return nil }
        return min...max
    }

    /// The label of the choice a value is, when it is one.
    public func choice(for value: LuaValue) -> Choice? {
        guard let v = Self.normalize(value) else { return nil }
        return choices.first { $0.value == v }
    }

    /// A number outside the slider's range.
    public func isOutOfRange(_ value: LuaValue) -> Bool {
        guard let range, let n = Self.number(value) else { return false }
        return !range.contains(n)
    }

    /// A value as text a choice can match: integers and whole numbers alike ("3"), decimals as written.
    public static func normalize(_ value: LuaValue) -> String? {
        switch value {
        case .string(let s): s
        case .bool(let b): b ? "true" : "false"
        case .integer(let n): String(n)
        case .number(let d): d.rounded() == d && abs(d) < 1e15 ? String(Int64(d)) : String(d)
        case .nil, .table: nil
        }
    }

    /// A Lua literal from source as a normalized value; nil for anything that isn't a literal.
    static func normalize(literal raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 { return SVSourceNames.unescape(String(s.dropFirst().dropLast())) }
        if s == "true" || s == "false" { return s }
        if let d = Double(s) { return normalize(.number(d)) }
        return nil
    }

    static func number(_ value: LuaValue) -> Double? {
        switch value {
        case .integer(let n): Double(n)
        case .number(let d): d
        default: nil
        }
    }
}
