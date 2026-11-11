import Foundation

/// The Lua lines that use one saved key: what an AI model reads to name it.
public struct SVKeyEvidence: Sendable, Equatable {
    public let key: String
    public let lines: [String]
}

/// Names for saved keys the source rules can't name, asked of the configured AI (docs/SOURCE-NAMES.md).
/// Only the addon's name, the table's path, key names, and lines of the addon's public Lua are sent:
/// never a saved value, so no account, character, or guild names leave the Mac.
public enum SVAINaming {
    public static let linesPerKey = 6
    public static let keysPerRequest = 40
    public static let maxLineLength = 160

    /// For each key, up to `linesPerKey` distinct lines that read or write it. Keys the source never
    /// mentions are left out: a model would only guess from the key's own name.
    public static func evidence(keys: [String], sources: [String]) -> [SVKeyEvidence] {
        let lines = sources.flatMap { $0.split(whereSeparator: \.isNewline) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("--") }
        return keys.prefix(keysPerRequest).compactMap { key in
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let pattern = #"(\.\s*\#(escaped)\b|\[\s*"\#(escaped)"\s*\]|^\#(escaped)\s*=)"#
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            var seen = Set<String>(), found: [String] = []
            for line in lines where found.count < linesPerKey {
                guard re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { continue }
                let short = line.count > maxLineLength ? String(line.prefix(maxLineLength)) + "…" : line
                if seen.insert(short).inserted { found.append(short) }
            }
            return found.isEmpty ? nil : SVKeyEvidence(key: key, lines: found)
        }
    }

    public static let system = """
    You name the saved settings of Elder Scrolls Online addons from their Lua source. \
    Answer only with lines in the form key = Name, one per key, nothing else. \
    A name is 2 to 6 words in sentence case that says what the setting does for the player, \
    using only what the code shows. When the code doesn't show what a key is for, write key = ?
    """

    public static func prompt(addon: String, table: String, evidence: [SVKeyEvidence]) -> String {
        var text = "Addon: \(addon)\nSaved table: \(table)\n\nFor each key, the lines of the addon's Lua source that use it:\n"
        for e in evidence {
            text += "\n[\(e.key)]\n" + e.lines.map { "    \($0)" }.joined(separator: "\n") + "\n"
        }
        return text
    }

    /// `key = Name` lines (or a JSON object), for the keys that were asked about only. "?" means unknown.
    public static func parse(_ answer: String, keys: Set<String>) -> [String: String] {
        var found: [String: String] = [:]
        func keep(_ key: String, _ raw: String) {
            let name = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'`*.").union(.whitespaces))
            guard keys.contains(key), !name.isEmpty, name != "?", name.count <= 60, !name.contains("=") else { return }
            found[key] = name.prefix(1).uppercased() + name.dropFirst()
        }
        let unfenced = answer.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if unfenced.hasPrefix("{"), let data = unfenced.data(using: .utf8),
           let object = try? JSONDecoder().decode([String: String].self, from: data) {
            for (key, name) in object { keep(key, name) }
            return found
        }
        for line in unfenced.split(whereSeparator: \.isNewline) {
            let parts = SVSourceNames.matches(#"^\s*(?:[-•*]\s*)?`?\[?([A-Za-z_$][\w$]*)\]?`?\s*[=:]\s*(.+)$"#, String(line))
            if let m = parts.first { keep(m[1], m[2]) }
        }
        return found
    }
}

/// AI names kept between launches, per addon version: a new version may change what a key means.
public struct SVAINameCache: Codable, Sendable, Equatable {
    /// "folder|version|parent|key" -> name.
    public var names: [String: String] = [:]

    public init() {}

    static func id(_ folder: String, _ version: String, _ parent: String, _ key: String) -> String {
        [folder.lowercased(), version, parent, key].joined(separator: "|")
    }

    public subscript(folder: String, version: String, parent: String, key: String) -> String? {
        get { names[Self.id(folder, version, parent, key)] }
        set { names[Self.id(folder, version, parent, key)] = newValue }
    }

    /// Every cached name for one addon version, as (parent, key, name).
    public func entries(folder: String, version: String) -> [(parent: String, key: String, name: String)] {
        let prefix = Self.id(folder, version, "", "").dropLast(1)
        return names.compactMap { id, name in
            guard id.hasPrefix(prefix) else { return nil }
            let rest = id.dropFirst(prefix.count).split(separator: "|", omittingEmptySubsequences: false)
            return rest.count == 2 ? (String(rest[0]), String(rest[1]), name) : nil
        }
    }
}
