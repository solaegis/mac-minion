import Foundation

/// Where AI requests go. Off sends nothing anywhere.
public enum AIProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case off, ollama, claude, openai

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .ollama: "Ollama (on this Mac)"
        case .claude: "Claude"
        case .openai: "OpenAI"
        }
    }

    public var needsKey: Bool { self == .claude || self == .openai }
}

/// Everything needed to send one request. The single place that knows which provider, model, URL,
/// and key are in use.
public struct AIConfig: Sendable, Equatable {
    public var provider: AIProvider
    public var ollamaURL: URL
    public var ollamaModel: String
    public var claudeModel: String
    public var claudeKey: String
    public var openAIModel: String
    public var openAIKey: String

    public init(provider: AIProvider, ollamaURL: URL = AIConfig.defaultOllamaURL, ollamaModel: String = "",
                claudeModel: String = AnthropicProvider.defaultModelID, claudeKey: String = "",
                openAIModel: String = OpenAIProvider.defaultModelID, openAIKey: String = "") {
        self.provider = provider; self.ollamaURL = ollamaURL; self.ollamaModel = ollamaModel
        self.claudeModel = claudeModel; self.claudeKey = claudeKey
        self.openAIModel = openAIModel; self.openAIKey = openAIKey
    }

    public static let defaultOllamaURL = URL(string: "http://localhost:11434")!

    /// The selected provider's adapter, or nil when AI is off.
    public var llm: (any LLMProvider)? {
        switch provider {
        case .off: nil
        case .ollama: OllamaProvider(base: ollamaURL)
        case .claude: AnthropicProvider(key: claudeKey)
        case .openai: OpenAIProvider(key: openAIKey)
        }
    }

    /// The selected provider's model.
    public var model: String {
        switch provider {
        case .off: ""
        case .ollama: ollamaModel
        case .claude: claudeModel
        case .openai: openAIModel
        }
    }

    /// Why this config can't send a request yet, or nil when it can.
    public var problem: String? {
        switch provider {
        case .off: "AI is turned off in Settings."
        case .ollama: ollamaModel.isEmpty ? "Choose an Ollama model in Settings." : nil
        case .claude: claudeKey.isEmpty ? "Add a Claude API key in Settings." : claudeModel.isEmpty ? "Choose a Claude model in Settings." : nil
        case .openai: openAIKey.isEmpty ? "Add an OpenAI API key in Settings." : openAIModel.isEmpty ? "Choose an OpenAI model in Settings." : nil
        }
    }
}

/// What went wrong, in words for the person using the app. Never contains an API key.
public enum AIError: LocalizedError, Equatable {
    case notConfigured(String)
    case badKey(String)
    case rateLimited(String)
    case outage(String)
    case unreachable(String)
    case timedOut
    case http(Int, String)
    case refused(String?)
    case empty

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let why): why
        case .badKey(let provider): "\(provider) didn't accept the API key. Check your API key in Settings > AI."
        case .rateLimited(let provider): "\(provider) is rate limiting requests. Wait a minute and try again."
        case .outage(let provider): "\(provider) is having problems right now. Try again later."
        case .unreachable(let message): message
        case .timedOut: "The AI took too long to answer. Try again."
        case .http(let code, let message): message.isEmpty ? "The AI service answered \(code)." : message
        case .refused(let why): why.map { "The model declined: \($0)" } ?? "The model declined to answer."
        case .empty: "The answer was empty."
        }
    }

    /// Worth another try on a setup request: rate limits and outages.
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .outage: true
        default: false
        }
    }

    /// 401/403: the key; 429: rate limit; 5xx and Anthropic's 529: outage; anything else: the provider's message.
    public static func forStatus(_ status: Int, body: Data, provider: String) -> AIError {
        switch status {
        case 401, 403: .badKey(provider)
        case 429: .rateLimited(provider)
        case 500...599: .outage(provider)
        default: .http(status, redacted(AIClient.errorMessage(body)))
        }
    }

    /// Network failures in plain words; cancellation stays a CancellationError.
    static func wrap(_ error: Error, provider: any LLMProvider) -> Error {
        if error is AIError || error is CancellationError { return error }
        guard let url = error as? URLError else { return error }
        switch url.code {
        case .cancelled: return CancellationError()
        case .timedOut: return AIError.timedOut
        case .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed:
            return AIError.unreachable(provider.unreachableMessage)
        default: return error
        }
    }

    /// Provider messages sometimes quote part of a bad key ("Incorrect API key provided: sk-ab***yz").
    public static func redacted(_ text: String) -> String {
        text.replacingOccurrences(of: #"(sk-[A-Za-z0-9_\-*.]+|Bearer\s+\S+)"#, with: "[key]", options: .regularExpression)
    }
}

/// How a keyed provider stands, for Settings.
public enum ConnectionStatus: Equatable, Sendable {
    case noKey, untested, testing, connected, invalidKey, rateLimited, failed(String)

    public init(_ error: Error) {
        switch error as? AIError {
        case .badKey?: self = .invalidKey
        case .rateLimited?: self = .rateLimited
        default: self = .failed(error.localizedDescription)
        }
    }

    public var title: String {
        switch self {
        case .noKey: "No key configured"
        case .untested: "Not tested"
        case .testing: "Testing…"
        case .connected: "Connected"
        case .invalidKey: "Invalid key"
        case .rateLimited: "Rate limited"
        case .failed(let why): why
        }
    }
}

/// One request, one answer, through the provider in `config`. Ollama runs on this Mac; Claude goes to
/// api.anthropic.com; OpenAI to api.openai.com. Nothing else is sent anywhere.
public struct AIClient: Sendable {
    public let config: AIConfig
    let session: URLSession

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
        guard let llm = config.llm else { throw AIError.notConfigured("AI is turned off in Settings.") }
        var text = ""
        for try await event in llm.streamChat(messages: [ChatMessage(.user, prompt)], model: config.model, system: system,
                                              session: session) {
            switch event {
            case .text(let piece):
                text += piece
                await onText(text)
            case .done(.refused):
                throw AIError.refused(nil)
            case .usage, .done:
                break
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.empty }
        return trimmed
    }

    /// The `message` from an error body: Anthropic and OpenAI nest it in `error`; Ollama's `error` is the text.
    static func errorMessage(_ data: Data) -> String {
        struct Nested: Decodable { struct E: Decodable { let message: String }; let error: E }
        struct Flat: Decodable { let error: String }
        if let n = try? JSONDecoder().decode(Nested.self, from: data) { return n.error.message }
        if let f = try? JSONDecoder().decode(Flat.self, from: data) { return f.error }
        return ""
    }

    /// The chat models installed in Ollama (`GET /api/tags`), without embedding models.
    public static func ollamaModels(at base: URL, session: URLSession = .shared) async throws -> [OllamaModel] {
        let (data, response) = try await session.data(for: OllamaProvider(base: base).modelsRequest())
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AIError.http(status, errorMessage(data)) }
        return try OllamaModel.decodeTags(data).filter { !$0.isEmbedding }.sorted { $0.name < $1.name }
    }
}

extension AIClient {
    /// Models Ollama has in memory now (`GET /api/ps`).
    public static func loadedModels(at base: URL, session: URLSession = .shared) async -> Set<String> {
        struct Running: Decodable { let name: String }
        struct PS: Decodable { let models: [Running] }
        guard let (data, _) = try? await session.data(for: URLRequest(url: base.appending(path: "api/ps"), timeoutInterval: 5)),
              let ps = try? JSONDecoder().decode(PS.self, from: data) else { return [] }
        return Set(ps.models.map(\.name))
    }

    /// Writes a short summary with `model` and reports its speed from Ollama's own timings.
    public static func benchmark(_ model: String, at base: URL, session: URLSession = .shared) async throws -> ModelSpeed {
        var r = URLRequest(url: base.appending(path: "api/chat"), timeoutInterval: idleTimeout)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model, "stream": false, "keep_alive": "5m",
            "options": ["num_predict": 96, "num_ctx": 4_096],
            "messages": [["role": "system", "content": AIPrompts.system],
                         ["role": "user", "content": AIPrompts.changes(name: "LibAddonMenu-2.0", installed: "2.0 r42", latest: "2.0 r43",
                                                                       changelog: benchmarkChangelog)]],
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: r)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AIError.http(status, errorMessage(data)) }
        return try parseTimings(data)
    }

    static func parseTimings(_ data: Data) throws -> ModelSpeed {
        struct Timings: Decodable { let eval_count: Int?; let eval_duration: Int64?; let load_duration: Int64? }
        let t = try JSONDecoder().decode(Timings.self, from: data)
        guard let count = t.eval_count, let ns = t.eval_duration, ns > 0, count > 0 else { throw AIError.empty }
        return ModelSpeed(tokensPerSecond: Double(count) / (Double(ns) / 1e9), loadSeconds: Double(t.load_duration ?? 0) / 1e9)
    }

    static let benchmarkChangelog = """
    2.0 r43
    - fixed error when playing in XBox Game Pass PC version
    - fixed leaking global variable
    - fixed inconsistent behavior in multi select dropdown when using choiceValues
    - updated for Seasons Zero
    """
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

/// Picks the Ollama model that suits summaries on this Mac. It looks at the host (all memory, memory
/// free now), which models Ollama has loaded, and measured speed when a benchmark ran; then prefers a
/// general chat model (not coding or embedding) near 12 billion parameters from a recent family.
public enum ModelAdvisor {
    public struct Pick: Sendable, Equatable {
        public let model: String
        public let reason: String
    }

    /// Below this many tokens a second a summary feels slow.
    public static let comfortableSpeed = 15.0

    public static func rank(_ models: [OllamaModel], host: HostProfile, loaded: Set<String> = [],
                            speeds: [String: ModelSpeed] = [:]) -> [OllamaModel] {
        models.filter { suitable($0, host: host) }
            .sorted { score($0, host: host, loaded: loaded, speeds: speeds) > score($1, host: host, loaded: loaded, speeds: speeds) }
    }

    public static func recommend(_ models: [OllamaModel], host: HostProfile, loaded: Set<String> = [],
                                 speeds: [String: ModelSpeed] = [:]) -> Pick? {
        guard let best = rank(models, host: host, loaded: loaded, speeds: speeds).first else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: best.bytes, countStyle: .memory)
        var why = [String(format: "%.0fB parameters, %@", best.billions, size)]
        if let speed = speeds[best.name] {
            why.append(String(format: "writes %.0f tokens a second here", speed.tokensPerSecond))
        }
        if loaded.contains(best.name) { why.append("already loaded") }
        if Double(best.bytes) > Double(host.availableBytes) { why.append("needs more than the memory free now") }
        return Pick(model: best.name, reason: why.joined(separator: ", ") + " on \(host.summary). Coding and embedding models were left out.")
    }

    static func suitable(_ m: OllamaModel, host: HostProfile) -> Bool {
        // 60% of memory leaves room for the game and macOS while the model is loaded.
        !m.isEmbedding && !m.isCodeModel && Double(m.bytes) < Double(host.memoryBytes) * 0.6
    }

    static func score(_ m: OllamaModel, host: HostProfile, loaded: Set<String>, speeds: [String: ModelSpeed]) -> Double {
        // Closest to 12B wins; each doubling away costs as much as a generation of family.
        var score = -abs(log2(max(m.billions, 0.5) / 12)) * 10
        let name = m.name.lowercased() + " " + m.family.lowercased()
        // Newer families follow instructions better; the newest get the most.
        let families: [(String, Double)] = [("gemma4", 10), ("qwen3", 9), ("gemma3", 6), ("phi4", 5), ("phi3", 4),
                                            ("llama4", 4), ("llama3", 3), ("mistral", 3), ("qwen2", 2)]
        score += families.first { name.contains($0.0) }?.1 ?? 0
        if (m.contextLength ?? 0) >= 16_384 { score += 2 }
        // A loaded model answers without a load; one larger than free memory pushes apps out first.
        if loaded.contains(m.name) { score += 2 }
        if Double(m.bytes) > Double(host.availableBytes) { score -= 6 }
        // Measured speed beats the size guess.
        if let tps = speeds[m.name]?.tokensPerSecond {
            score += tps < comfortableSpeed ? -12 : min(4, (tps - comfortableSpeed) / 10)
        }
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

    public static let recommendSystem = """
    You know Elder Scrolls Online addons on ESOUI well. Suggest addons for one player from a list. \
    Follow the answer format exactly; write nothing else.
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
