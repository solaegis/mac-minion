import Foundation

/// The Lua lines that use one saved key: what an AI model reads to name it.
public struct SVKeyEvidence: Sendable, Equatable {
    public let key: String
    public let lines: [String]
}

/// The source lines AI reads about saved keys the source rules can't name (docs/SOURCE-NAMES.md); the
/// prompt and answer are `SVAISchema`.
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
