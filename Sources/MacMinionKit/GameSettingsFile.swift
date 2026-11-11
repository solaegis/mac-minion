import Foundation

/// One of the game's own settings files beside AddOns, read as fields to edit: `UserSettings.txt` and
/// `MachineSettings.txt` (`SET Key "value"` lines) and `AddOnSettings.txt` (headers, then which addons each
/// character loads). There's no official schema; see docs/research/SETTINGS-FILES.md for where each type comes from.
/// Saving rewrites only the lines that changed, each with its own line ending, so the rest stays byte for byte.
public struct GameSettingsFile: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable, Identifiable {
        case user, addOns, machine

        public var id: String { rawValue }
        public var fileName: String {
            switch self {
            case .user: "UserSettings.txt"
            case .addOns: "AddOnSettings.txt"
            case .machine: "MachineSettings.txt"
            }
        }
    }

    /// How a field is edited.
    public enum FieldType: Sendable, Equatable {
        case toggle
        case integer
        case decimal
        /// AARRGGBB hex, as the game writes colors.
        case color
        /// `<width>x<height>`.
        case size
        case choice([Choice])
        case text
    }

    public struct Choice: Sendable, Equatable, Hashable {
        public let value: String
        public let title: String
    }

    public struct Field: Sendable, Equatable, Identifiable {
        /// The line it's on, which is also how a change names it.
        public let id: Int
        /// The character block it's in (`Default`, `NA Megaserver-Masisi`), or nil for top-level settings.
        public let section: String?
        public let key: String
        public let value: String
        public let type: FieldType
    }

    struct Line: Sendable, Equatable {
        var text: String
        let ending: String
    }

    public let kind: Kind
    public let fields: [Field]
    let lines: [Line]

    /// Reads a file's text into fields; lines it doesn't understand are kept as they are.
    public static func parse(_ data: Data, kind: Kind) -> GameSettingsFile {
        // Split on the bytes: Swift reads "\r\n" as one character, so a search for "\n" in a String misses it.
        var lines: [Line] = []
        let bytes = [UInt8](data)
        var start = 0
        for (i, byte) in bytes.enumerated() where byte == 10 {
            let crlf = i > start && bytes[i - 1] == 13
            lines.append(Line(text: String(decoding: bytes[start..<(crlf ? i - 1 : i)], as: UTF8.self), ending: crlf ? "\r\n" : "\n"))
            start = i + 1
        }
        if start < bytes.count { lines.append(Line(text: String(decoding: bytes[start...], as: UTF8.self), ending: "")) }
        var fields: [Field] = []
        var section: String?
        for (i, line) in lines.enumerated() {
            switch kind {
            case .user, .machine:
                if let (key, value) = setLine(line.text) {
                    fields.append(Field(id: i, section: nil, key: key, value: value, type: type(key: key, value: value)))
                }
            case .addOns:
                let trimmed = line.text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                if trimmed.hasPrefix("#") {
                    let body = trimmed.dropFirst()
                    let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
                    if let name = parts.first, headers.contains(name) {
                        let value = parts.count > 1 ? parts[1] : ""
                        fields.append(Field(id: i, section: nil, key: name, value: value, type: type(key: "#" + name, value: value)))
                    } else {
                        section = String(body)
                    }
                } else {
                    let parts = trimmed.split(separator: " ").map(String.init)
                    guard parts.count == 2 else { continue }
                    fields.append(Field(id: i, section: section, key: parts[0], value: parts[1], type: .toggle))
                }
            }
        }
        return GameSettingsFile(kind: kind, fields: fields, lines: lines)
    }

    /// The file with these new values (by field ID), changing only their lines.
    public func applying(_ changes: [Int: String]) -> Data {
        var lines = lines
        for field in fields {
            guard let value = changes[field.id], value != field.value else { continue }
            let clean = value.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\n", with: "")
            switch kind {
            case .user, .machine:
                lines[field.id].text = "SET \(field.key) \"\(clean)\""
            case .addOns:
                lines[field.id].text = field.section == nil ? "#\(field.key) \(clean)" : "\(field.key) \(clean)"
            }
        }
        return Data(lines.map { $0.text + $0.ending }.joined().utf8)
    }

    // MARK: Types

    static let headers: Set<String> = ["Version", "AcknowledgedOutOfDateAddonsVersion", "AddOnsEnabled"]

    static func setLine(_ text: String) -> (String, String)? {
        guard text.hasPrefix("SET ") else { return nil }
        let rest = text.dropFirst(4)
        guard let space = rest.firstIndex(of: " ") else { return nil }
        let key = String(rest[..<space])
        let quoted = rest[rest.index(after: space)...]
        guard quoted.count >= 2, quoted.hasPrefix("\""), quoted.hasSuffix("\"") else { return nil }
        return (key, String(quoted.dropFirst().dropLast()))
    }

    /// The editor for a key: a curated one when MacMinion knows the key, else one that fits its current value.
    public static func type(key: String, value: String) -> FieldType {
        if let curated = curated(key: key, value: value) { return curated }
        let lower = key.lowercased()
        let switchName = lower.hasSuffix("enabled") || ["use", "show", "invert", "enable", "is"].contains { lower.hasPrefix($0) }
        if switchName, value == "0" || value == "1" { return .toggle }
        if value.range(of: #"^-?\d+$"#, options: .regularExpression) != nil { return .integer }
        if value.range(of: #"^-?\d*\.\d+$"#, options: .regularExpression) != nil { return .decimal }
        if value.range(of: #"^[0-9A-Fa-f]{8}$"#, options: .regularExpression) != nil { return .color }
        if value.range(of: #"^\d+x\d+$"#, options: .regularExpression) != nil { return .size }
        return .text
    }

    static func curated(key: String, value: String) -> FieldType? {
        func choices(_ options: [Choice]) -> FieldType {
            // The file's own value stays a choice, even when MacMinion doesn't know it.
            .choice(options.contains { $0.value == value } || value.isEmpty ? options : options + [Choice(value: value, title: value)])
        }
        switch key {
        case "LastRealm":
            return choices(["NA Megaserver", "EU Megaserver", "PTS"].map { Choice(value: $0, title: $0) })
        case "Language.2", "LastValidLanguage", "LastPlatformLanguage":
            return choices(languages.map { Choice(value: $0.code, title: $0.name) })
        case "#Version", "#AcknowledgedOutOfDateAddonsVersion":
            return choices(apiVersions.map { Choice(value: String($0.api), title: "\($0.api) · \($0.name)") })
        case "#AddOnsEnabled":
            return .toggle
        default:
            return nil
        }
    }

    static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("de", "Deutsch"), ("fr", "Français"), ("es", "Español"), ("ru", "Русский"), ("jp", "日本語"), ("zh", "中文"),
    ]

    /// API versions and the game updates they belong to, newest first, from the ESOUI wiki's APIVersion page.
    public static let apiVersions: [(api: Int, name: String)] = [
        (101052, "12.2.0 Echoes of Skyrim (PTS)"), (101051, "12.1.0 Season 1, Patch 51"), (101050, "12.0.0 Season 0, Part 2"),
        (101049, "11.3.0 Season 0"), (101048, "11.2.0 Season of the Worm Cult Part 2"), (101047, "11.1.0 Feast of Shadows"),
        (101046, "11.0.0 Seasons of the Worm Cult Part 1"), (101045, "10.3.0 Fallen Banners"), (101044, "10.2.5"),
        (101043, "10.1"), (101042, "10.0 Gold Road"), (101041, "9.3.5 Scions of Ithelia"), (101040, "9.2 Secret of the Telvanni"),
        (101039, "9.1.5"), (101038, "9.0 Necrom"), (101037, "8.3 Scribes of Fate"), (101036, "8.2 Firesong"),
        (101035, "8.1.5 Lost Depths"), (101034, "8.0 High Isle"), (101033, "7.3 Ascending Tide"), (101032, "7.2 Deadlands"),
        (101031, "7.1 Waking Flame"), (100035, "7.0 Blackwood"), (100034, "6.3.0 Flames of Ambition"), (100033, "6.2.0 Markarth"),
        (100032, "6.1.0 Stonethorn"), (100031, "6.0.0 Greymoor"), (100030, "5.3.0 Harrowstorm"),
    ]
}
