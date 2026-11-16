import Foundation

/// Which addons each character loads, from `AddOnSettings.txt`: one block per character, named
/// `#<Megaserver>-<Name>`, and `#Default` for characters without their own block. Compare reads it and
/// Clone writes it back with `GameSettingsFile.settingAddOns` (S-069).
public struct AddOnChoices: Sendable, Equatable {
    public static let fileName = GameSettingsFile.Kind.addOns.fileName
    /// The block for characters without their own.
    public static let defaultHeader = "Default"

    /// Block header ("NA Megaserver-Masisi") -> addon folder -> on.
    public let blocks: [String: [String: Bool]]

    public init(_ file: GameSettingsFile) {
        var blocks: [String: [String: Bool]] = [:]
        for field in file.fields {
            guard let section = field.section else { continue }
            blocks[section, default: [:]][field.key] = field.value == "1"
        }
        self.blocks = blocks
    }

    /// A character's block header, as the game writes it.
    public static func header(server: String, name: String) -> String { "\(server)-\(name)" }

    /// What a character loads: their own block, or `#Default` when they have none.
    public func effective(for header: String) -> (choices: [String: Bool], fromDefault: Bool) {
        if let own = blocks[header] { return (own, false) }
        return (blocks[Self.defaultHeader] ?? [:], true)
    }

    /// One addon's state for two characters; nil where a character's list doesn't name it.
    public struct Row: Sendable, Equatable {
        public let addon: String
        public let a: Bool?
        public let b: Bool?
        public var differs: Bool { a != b }
    }

    /// Every addon either character's list names, by folder name.
    public func compare(_ a: String, _ b: String) -> [Row] {
        let ea = effective(for: a).choices, eb = effective(for: b).choices
        return Set(ea.keys).union(eb.keys)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { Row(addon: $0, a: ea[$0], b: eb[$0]) }
    }
}

extension GameSettingsFile {
    /// `AddOnSettings.txt` with these addons turned on or off, by block header. Lines that exist change in
    /// place; a missing addon is added at the end of its block; a missing block is added at the end of the
    /// file, starting from `#Default`'s list so the character loads the same addons apart from these.
    /// Every other line stays byte for byte.
    public func settingAddOns(_ changes: [String: [String: Bool]]) -> Data {
        guard kind == .addOns else { return Data(lines.map { $0.text + $0.ending }.joined().utf8) }
        let ending = lines.first { !$0.ending.isEmpty }?.ending ?? "\n"
        func line(_ addon: String, _ on: Bool) -> Line { Line(text: "\(addon) \(on ? "1" : "0")", ending: ending) }
        let byName: (String, String) -> Bool = { $0.localizedStandardCompare($1) == .orderedAscending }

        var lines = lines
        // Block header -> the line it's on.
        var headerLine: [String: Int] = [:]
        for (i, l) in lines.enumerated() {
            let trimmed = l.text.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }
            let name = String(trimmed.dropFirst())
            if let first = name.split(separator: " ", maxSplits: 1).first, Self.headers.contains(String(first)) { continue }
            headerLine[name] = headerLine[name] ?? i
        }
        // Insertions run bottom-up, so earlier line numbers stay right.
        var inserts: [(at: Int, lines: [Line])] = []
        var appended: [Line] = []
        for header in changes.keys.sorted(by: byName) {
            let wanted = changes[header] ?? [:]
            let fields = self.fields.filter { $0.section == header }
            if headerLine[header] != nil {
                for field in fields {
                    guard let on = wanted[field.key] else { continue }
                    lines[field.id].text = "\(field.key) \(on ? "1" : "0")"
                }
                let have = Set(fields.map(\.key))
                let missing = wanted.keys.filter { !have.contains($0) }.sorted(by: byName)
                guard !missing.isEmpty else { continue }
                let after = fields.map(\.id).max() ?? headerLine[header]!
                inserts.append((after + 1, missing.map { line($0, wanted[$0]!) }))
            } else {
                let base = self.fields.filter { $0.section == AddOnChoices.defaultHeader }
                var block = [Line(text: "#\(header)", ending: ending)]
                block += base.map { line($0.key, wanted[$0.key] ?? ($0.value == "1")) }
                let named = Set(base.map(\.key))
                block += wanted.keys.filter { !named.contains($0) }.sorted(by: byName).map { line($0, wanted[$0]!) }
                appended += block
            }
        }
        for insert in inserts.sorted(by: { $0.at > $1.at }) {
            // A block at the very end of a file with no final line break: the last line gets one first.
            if insert.at == lines.count, let last = lines.last, last.ending.isEmpty {
                lines[lines.count - 1] = Line(text: last.text, ending: ending)
            }
            lines.insert(contentsOf: insert.lines, at: insert.at)
        }
        if !appended.isEmpty {
            if let last = lines.last, last.ending.isEmpty, !last.text.isEmpty {
                lines[lines.count - 1] = Line(text: last.text, ending: ending)
            } else if let last = lines.last, last.text.isEmpty, last.ending.isEmpty {
                lines.removeLast()
            }
            lines += appended
        }
        return Data(lines.map { $0.text + $0.ending }.joined().utf8)
    }
}
