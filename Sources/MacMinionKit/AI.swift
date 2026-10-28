import Foundation

/// Where AI requests go. Off sends nothing anywhere.
public enum AIProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case off, ollama, claude

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .ollama: "Ollama (on this Mac)"
        case .claude: "Claude"
        }
    }
}

/// The Claude models offered in Settings. Opus 5.5 is the default.
public enum ClaudeModel: String, CaseIterable, Codable, Sendable, Identifiable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .opus: "Claude Opus 5.5"
        case .sonnet: "Claude Sonnet 5.5"
        case .haiku: "Claude Haiku 5.5"
        }
    }

    /// Opus 5.5 and Sonnet 5.5 can retry a refused request on another model server-side. Haiku 5.5 cannot.
    var supportsFallbacks: Bool { self != .haiku }
}

/// Everything needed to send one request.
public struct AIConfig: Sendable, Equatable {
    public var provider: AIProvider
    public var ollamaURL: URL
    public var ollamaModel: String
    public var claudeModel: ClaudeModel
    public var claudeKey: String

    public init(provider: AIProvider, ollamaURL: URL = AIConfig.defaultOllamaURL, ollamaModel: String = "",
                claudeModel: ClaudeModel = .opus, claudeKey: String = "") {
        self.provider = provider; self.ollamaURL = ollamaURL; self.ollamaModel = ollamaModel
        self.claudeModel = claudeModel; self.claudeKey = claudeKey
    }

    public static let defaultOllamaURL = URL(string: "http://localhost:11434")!

    /// Why this config can't send a request yet, or nil when it can.
    public var problem: String? {
        switch provider {
        case .off: "AI is turned off in Settings."
        case .ollama: ollamaModel.isEmpty ? "Choose an Ollama model in Settings." : nil
        case .claude: claudeKey.isEmpty ? "Add a Claude API key in Settings." : nil
        }
    }
}

public enum AIError: LocalizedError, Equatable {
    case notConfigured(String)
    case http(Int, String)
    case refused(String?)
    case empty

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let why): why
        case .http(let code, let message): message.isEmpty ? "The AI service answered \(code)." : message
        case .refused(let why): why.map { "Claude declined: \($0)" } ?? "Claude declined to answer."
        case .empty: "The answer was empty."
        }
    }
}

/// One request, one answer. Ollama runs on this Mac; Claude goes to api.anthropic.com.
public struct AIClient: Sendable {
    public let config: AIConfig
    let session: URLSession

    public static let anthropicURL = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let anthropicVersion = "2026-10-21"

    public init(config: AIConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func complete(system: String, prompt: String) async throws -> String {
        if let problem = config.problem { throw AIError.notConfigured(problem) }
        let request = try makeRequest(system: system, prompt: prompt)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AIError.http(status, Self.errorMessage(data))
        }
        let text = try config.provider == .claude ? Self.parseClaude(data) : Self.parseOllama(data)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.empty }
        return trimmed
    }

    func makeRequest(system: String, prompt: String) throws -> URLRequest {
        switch config.provider {
        case .off:
            throw AIError.notConfigured("AI is turned off in Settings.")
        case .ollama:
            var r = URLRequest(url: config.ollamaURL.appending(path: "api/chat"), timeoutInterval: 300)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": config.ollamaModel,
                "stream": false,
                "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
            ]
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            return r
        case .claude:
            var r = URLRequest(url: Self.anthropicURL, timeoutInterval: 300)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue(config.claudeKey, forHTTPHeaderField: "x-api-key")
            r.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
            var body: [String: Any] = [
                "model": config.claudeModel.rawValue,
                "max_tokens": 16_000,
                "system": system,
                "messages": [["role": "user", "content": prompt]],
                // Summaries are short and simple work.
                "output_config": ["effort": "low"],
            ]
            if config.claudeModel.supportsFallbacks {
                // A refused request is retried on a fitting model instead of failing.
                r.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                body["fallbacks"] = "default"
            }
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            return r
        }
    }

    static func parseClaude(_ data: Data) throws -> String {
        struct Block: Decodable { let type: String; let text: String? }
        struct StopDetails: Decodable { let explanation: String? }
        struct Response: Decodable { let content: [Block]; let stop_reason: String?; let stop_details: StopDetails? }
        let r = try JSONDecoder().decode(Response.self, from: data)
        if r.stop_reason == "refusal" { throw AIError.refused(r.stop_details?.explanation) }
        // Thinking blocks come first; only text blocks are the answer.
        return r.content.filter { $0.type == "text" }.compactMap(\.text).joined(separator: "\n")
    }

    static func parseOllama(_ data: Data) throws -> String {
        struct Message: Decodable { let content: String }
        struct Response: Decodable { let message: Message }
        return try JSONDecoder().decode(Response.self, from: data).message.content
    }

    static func errorMessage(_ data: Data) -> String {
        struct Claude: Decodable { struct E: Decodable { let message: String }; let error: E }
        struct Ollama: Decodable { let error: String }
        if let c = try? JSONDecoder().decode(Claude.self, from: data) { return c.error.message }
        if let o = try? JSONDecoder().decode(Ollama.self, from: data) { return o.error }
        return ""
    }

    /// The models installed in Ollama (`GET /api/tags`).
    public static func ollamaModels(at base: URL, session: URLSession = .shared) async throws -> [String] {
        struct Tag: Decodable { let name: String }
        struct Tags: Decodable { let models: [Tag] }
        let (data, response) = try await session.data(for: URLRequest(url: base.appending(path: "api/tags"), timeoutInterval: 10))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AIError.http(status, errorMessage(data)) }
        // Embedding models can't chat.
        return try JSONDecoder().decode(Tags.self, from: data).models.map(\.name).filter { !$0.contains("embed") }.sorted()
    }
}

/// The prompts MacMinion sends.
public enum AIPrompts {
    public static let system = """
    You help a player keep Elder Scrolls Online addons up to date. Answer in plain text for a small panel: \
    no headings, no Markdown tables. Use short bullet points that start with "• ". Name concrete changes, \
    skip version-bump noise like "updated API version" unless it is the only change, and say plainly when \
    an update fixes a crash, a Lua error, or a game-update breakage.
    """

    /// What changed in one addon, from the version the player has to the latest.
    public static func changes(name: String, installed: String?, latest: String, changelog: String) -> String {
        let since = installed.map { "The player has version \($0). Summarize only the changes after it, up to \(latest)." }
            ?? "Summarize the changes in the most recent versions, up to \(latest)."
        return """
        Addon: \(name)
        \(since)
        Use at most 5 bullets.

        Changelog:
        \(changelog)
        """
    }

    /// One digest over several pending updates.
    public static func digest(_ items: [(name: String, installed: String?, latest: String, changelog: String)]) -> String {
        var text = "These addons have updates waiting. For each addon, write its name on its own line, then one to three bullets on what the update brings. End with one line on which updates matter most.\n"
        for item in items {
            text += "\n=== \(item.name): \(item.installed ?? "unknown") -> \(item.latest)\n\(item.changelog)\n"
        }
        return text
    }
}
