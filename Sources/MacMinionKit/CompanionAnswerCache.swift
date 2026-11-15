import Foundation

/// Persists companion name-lookup answers so they survive the companion's 2,000-answer trim.
public enum CompanionAnswerCache {
    public static let fileName = "companion-answers.json"

    public static func url(in store: URL) -> URL {
        store.appending(path: fileName)
    }

    public static func load(from store: URL) -> [String: CompanionAnswer] {
        let url = url(in: store)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Cached].self, from: data) else { return [:] }
        return decoded.mapValues { CompanionAnswer(key: $0.key, name: $0.name, quality: $0.quality, set: $0.set, icon: $0.icon) }
    }

    public static func save(_ answers: [String: CompanionAnswer], to store: URL) {
        guard !answers.isEmpty else { return }
        let encoded = answers.mapValues { Cached(key: $0.key, name: $0.name, quality: $0.quality, set: $0.set, icon: $0.icon) }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        try? FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try? data.write(to: url(in: store), options: .atomic)
    }

    /// File answers win over older cache rows; cache fills gaps the companion trimmed.
    public static func merge(file: [String: CompanionAnswer], cache: [String: CompanionAnswer]) -> [String: CompanionAnswer] {
        var out = cache
        for (key, answer) in file { out[key] = answer }
        return out
    }

    private struct Cached: Codable {
        var key: String
        var name: String?
        var quality: Int?
        var set: Int?
        var icon: String?
    }
}
