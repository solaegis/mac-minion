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

    /// Seconds to wait for the next bytes. Ollama may load a large model before the first token.
    public static let idleTimeout: TimeInterval = 600

    public func complete(system: String, prompt: String) async throws -> String {
        try await stream(system: system, prompt: prompt) { _ in }
    }

    /// Streams the answer: `onText` gets the whole answer so far after every chunk. Streaming keeps the
    /// connection busy, so a slow local model never trips the request timeout.
    public func stream(system: String, prompt: String, onText: @Sendable (String) async -> Void) async throws -> String {
        if let problem = config.problem { throw AIError.notConfigured(problem) }
        let request = try makeRequest(system: system, prompt: prompt, streaming: true)
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw AIError.http(status, Self.errorMessage(body))
        }
        var text = ""
        for try await line in bytes.lines {
            guard let piece = try config.provider == .claude ? Self.claudeEvent(line) : Self.ollamaChunk(line) else { continue }
            text += piece
            await onText(text)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.empty }
        return trimmed
    }

    /// One Server-Sent Events line from the Messages API: the text it adds, or nil.
    static func claudeEvent(_ line: String) throws -> String? {
        guard line.hasPrefix("data:") else { return nil }
        struct Delta: Decodable { let type: String?; let text: String?; let stop_reason: String? }
        struct ErrorBody: Decodable { let message: String }
        struct Details: Decodable { let explanation: String? }
        struct Event: Decodable { let type: String; let delta: Delta?; let error: ErrorBody?; let stop_details: Details? }
        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let event = try? JSONDecoder().decode(Event.self, from: Data(json.utf8)) else { return nil }
        switch event.type {
        case "content_block_delta" where event.delta?.type == "text_delta": return event.delta?.text
        case "message_delta" where event.delta?.stop_reason == "refusal": throw AIError.refused(event.stop_details?.explanation)
        case "error": throw AIError.http(0, event.error?.message ?? "The stream failed.")
        default: return nil
        }
    }

    /// One NDJSON line from Ollama's /api/chat stream: the text it adds, or nil.
    static func ollamaChunk(_ line: String) throws -> String? {
        struct Message: Decodable { let content: String? }
        struct Chunk: Decodable { let message: Message?; let error: String? }
        guard !line.isEmpty, let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(line.utf8)) else { return nil }
        if let error = chunk.error { throw AIError.http(0, error) }
        return chunk.message?.content
    }

    func makeRequest(system: String, prompt: String, streaming: Bool = false) throws -> URLRequest {
        switch config.provider {
        case .off:
            throw AIError.notConfigured("AI is turned off in Settings.")
        case .ollama:
            var r = URLRequest(url: config.ollamaURL.appending(path: "api/chat"), timeoutInterval: Self.idleTimeout)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": config.ollamaModel,
                "stream": streaming,
                "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
                // Room for a long changelog: Ollama's default window cuts long prompts off silently.
                "options": ["num_ctx": 16_384],
                "keep_alive": "10m",
            ]
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            return r
        case .claude:
            var r = URLRequest(url: Self.anthropicURL, timeoutInterval: Self.idleTimeout)
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
            if streaming { body["stream"] = true }
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

    /// The chat models installed in Ollama (`GET /api/tags`), without embedding models.
    public static func ollamaModels(at base: URL, session: URLSession = .shared) async throws -> [OllamaModel] {
        let (data, response) = try await session.data(for: URLRequest(url: base.appending(path: "api/tags"), timeoutInterval: 10))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AIError.http(status, errorMessage(data)) }
        return try OllamaModel.decodeTags(data).filter { !$0.isEmbedding }.sorted { $0.name < $1.name }
    }
}

/// One model from Ollama's `/api/tags`.
public struct OllamaModel: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let bytes: Int64
    public let family: String
    /// Billions of parameters, from `parameter_size` ("14.7B") or, when Ollama leaves it out, from the file size.
    public let billions: Double
    public let contextLength: Int?

    public init(name: String, bytes: Int64, family: String = "", billions: Double, contextLength: Int? = nil) {
        self.name = name; self.bytes = bytes; self.family = family; self.billions = billions; self.contextLength = contextLength
    }

    var isEmbedding: Bool { name.contains("embed") || family.contains("bert") || billions < 1 }
    var isCodeModel: Bool { name.contains("coder") || name.contains("code") }

    static func decodeTags(_ data: Data) throws -> [OllamaModel] {
        struct Details: Decodable { let family: String?; let parameter_size: String?; let context_length: Int? }
        struct Tag: Decodable { let name: String; let size: Int64?; let details: Details? }
        struct Tags: Decodable { let models: [Tag] }
        return try JSONDecoder().decode(Tags.self, from: data).models.map { tag in
            let bytes = tag.size ?? 0
            return OllamaModel(name: tag.name, bytes: bytes, family: tag.details?.family ?? "",
                               billions: parseBillions(tag.details?.parameter_size) ?? Double(bytes) / 0.6e9,
                               contextLength: tag.details?.context_length)
        }
    }

    /// "14.7B" -> 14.7, "307.58M" -> 0.30758.
    static func parseBillions(_ text: String?) -> Double? {
        guard let text, let unit = text.last, let value = Double(text.dropLast()) else { return nil }
        switch unit.uppercased() {
        case "B": return value
        case "M": return value / 1_000
        case "T": return value * 1_000
        default: return nil
        }
    }
}

/// Picks the Ollama model that suits changelog summaries on this Mac: a general chat model (not a coding
/// or embedding model) that fits in memory with room to spare, near 8 to 16 billion parameters (fast,
/// and good at following instructions), from a recent family.
public enum ModelAdvisor {
    public struct Pick: Sendable, Equatable {
        public let model: String
        public let reason: String
    }

    public static func rank(_ models: [OllamaModel], memoryBytes: UInt64) -> [OllamaModel] {
        models.filter { suitable($0, memoryBytes: memoryBytes) }.sorted { score($0) > score($1) }
    }

    public static func recommend(_ models: [OllamaModel], memoryBytes: UInt64) -> Pick? {
        guard let best = rank(models, memoryBytes: memoryBytes).first else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: best.bytes, countStyle: .memory)
        let params = best.billions >= 1 ? String(format: "%.0fB", best.billions) : "small"
        return Pick(model: best.name, reason: "\(params) parameters, \(size): quick on this Mac and good at following instructions. Coding and embedding models were left out.")
    }

    static func suitable(_ m: OllamaModel, memoryBytes: UInt64) -> Bool {
        // 60% of memory leaves room for the game and macOS while the model is loaded.
        !m.isEmbedding && !m.isCodeModel && Double(m.bytes) < Double(memoryBytes) * 0.6
    }

    static func score(_ m: OllamaModel) -> Double {
        // Closest to 12B wins; each doubling away costs as much as a generation of family.
        var score = -abs(log2(max(m.billions, 0.5) / 12)) * 10
        let name = m.name.lowercased() + " " + m.family.lowercased()
        // Newer families follow instructions better; the newest get the most.
        let families: [(String, Double)] = [("gemma4", 10), ("qwen3", 9), ("gemma3", 6), ("phi4", 5), ("phi3", 4),
                                            ("llama4", 4), ("llama3", 3), ("mistral", 3), ("qwen2", 2)]
        score += families.first { name.contains($0.0) }?.1 ?? 0
        if (m.contextLength ?? 0) >= 16_384 { score += 2 }
        return score
    }
}

/// Changelogs list the newest version first. Only the part after the installed version matters.
public enum ChangelogText {
    public struct Part: Sendable, Equatable {
        public let text: String
        /// True when older entries were left out to stay inside `limit`.
        public let shortened: Bool
    }

    /// The entries newer than `installed`, at most `limit` characters. When `installed` is the newest
    /// entry (nothing newer), the newest entry alone: what the current version changed.
    public static func since(_ installed: String?, in changelog: String, limit: Int) -> Part {
        var text = changelog
        let lines = changelog.components(separatedBy: "\n")
        if let installed, !installed.isEmpty, let cut = lines.firstIndex(where: { startsWithVersion($0, installed) }) {
            if cut > 0 {
                text = lines[..<cut].joined(separator: "\n")
            } else if let next = lines.indices.dropFirst().first(where: { isHeading(lines[$0]) }) {
                text = lines[..<next].joined(separator: "\n")
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return Part(text: text, shortened: false) }
        let end = text.index(text.startIndex, offsetBy: limit)
        let head = text[..<end]
        let clean = head.lastIndex(of: "\n").map { head[..<$0] } ?? head
        return Part(text: clean.trimmingCharacters(in: .whitespacesAndNewlines), shortened: true)
    }

    /// A line that starts a changelog entry: a short line that begins with a version number.
    static func isHeading(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count < 48 else { return false }
        return t.range(of: #"^(version\s+|v)?\d+(\.\d+)*\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A changelog heading for `version`: "2.0 r42", "v2.0 r42 (consoles only)", "Version 2.0 r42".
    static func startsWithVersion(_ line: String, _ version: String) -> Bool {
        var t = line.lowercased().trimmingCharacters(in: .whitespaces)
        for prefix in ["version ", "v", "-", "*", "•"] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        let v = version.lowercased()
        guard t.hasPrefix(v) else { return false }
        let rest = t.dropFirst(v.count)
        return rest.first.map { !$0.isNumber && !$0.isLetter && $0 != "." } ?? true
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
    public static func changes(name: String, installed: String?, latest: String, changelog: String, shortened: Bool = false) -> String {
        let since = installed.map { "The player has version \($0). Summarize only the changes after it, up to \(latest)." }
            ?? "Summarize the changes in the most recent versions, up to \(latest)."
        return """
        Addon: \(name)
        \(since)
        Use at most 5 bullets.\(shortened ? " Older changelog entries were left out." : "")

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
