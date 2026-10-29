import Foundation

/// "MacMinion/1.2 (macOS)", sent to the hosted APIs.
public let aiUserAgent = "MacMinion/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") (macOS)"

// MARK: Ollama

/// Ollama on this Mac (or another server). `POST /api/chat` answers newline-delimited JSON.
public struct OllamaProvider: LLMProvider {
    public let base: URL

    public init(base: URL = AIConfig.defaultOllamaURL) { self.base = base }

    public var id: AIProvider { .ollama }
    public var displayName: String { "Ollama" }
    public var requiresAPIKey: Bool { false }
    /// None: ModelAdvisor picks from the models installed on the server.
    public var defaultModel: String { "" }
    public var availableModels: [String] { [] }
    public var unreachableMessage: String { "Can't reach Ollama at \(base.absoluteString). Is it running?" }

    public func chatRequest(messages: [ChatMessage], model: String, system: String?, options: ChatOptions) throws -> URLRequest {
        var r = URLRequest(url: base.appending(path: "api/chat"), timeoutInterval: AIClient.idleTimeout)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Room for a long changelog: Ollama's default window cuts long prompts off silently.
        var ollamaOptions: [String: Any] = ["num_ctx": 16_384]
        if let t = options.temperature { ollamaOptions["temperature"] = t }
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": wireMessages(messages, system: system),
            "options": ollamaOptions,
            "keep_alive": "10m",
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    public func events(fromLine line: String) throws -> [ChatEvent] {
        struct Message: Decodable { let content: String? }
        struct Chunk: Decodable {
            let message: Message?; let error: String?; let done: Bool?; let done_reason: String?
            let prompt_eval_count: Int?; let eval_count: Int?
        }
        guard !line.isEmpty, let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(line.utf8)) else { return [] }
        if let error = chunk.error { throw AIError.http(0, error) }
        var events: [ChatEvent] = []
        if let text = chunk.message?.content, !text.isEmpty { events.append(.text(text)) }
        if chunk.done == true {
            if chunk.prompt_eval_count != nil || chunk.eval_count != nil {
                events.append(.usage(input: chunk.prompt_eval_count, output: chunk.eval_count))
            }
            let reason: StopReason = switch chunk.done_reason {
            case "stop", nil: .finished
            case "length": .maxTokens
            case let other?: .other(other)
            }
            events.append(.done(reason))
        }
        return events
    }

    public func modelsRequest() -> URLRequest {
        URLRequest(url: base.appending(path: "api/tags"), timeoutInterval: 10)
    }

    public func decodeModels(_ data: Data) throws -> [String] {
        try OllamaModel.decodeTags(data).filter { !$0.isEmbedding }.map(\.name).sorted()
    }
}

// MARK: Anthropic

/// Claude through the Messages API. Streams Server-Sent Events: message_start, content_block_delta,
/// message_delta (stop reason and output tokens), message_stop.
public struct AnthropicProvider: LLMProvider {
    public let key: String

    public init(key: String) { self.key = key }

    public static let baseURL = URL(string: "https://api.anthropic.com/v1/")!
    /// Checked against platform.claude.com/docs/en/api/versioning on 2026-10-28.
    public static let version = "2026-10-21"
    public static let defaultModelID = "claude-opus-5-5"
    /// Known IDs and their names. People can type any other ID in Settings.
    public static let knownModels: [(id: String, title: String)] = [
        ("claude-opus-5-5", "Claude Opus 5.5"), ("claude-sonnet-5-5", "Claude Sonnet 5.5"), ("claude-haiku-5-5", "Claude Haiku 5.5"),
    ]
    /// Opus 5.5 and Sonnet 5.5 can retry a refused request on another model server-side. Haiku 5.5 cannot.
    static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-sonnet-5-5"]

    public static func title(for model: String) -> String {
        knownModels.first { $0.id == model }?.title ?? model
    }

    public var id: AIProvider { .claude }
    public var displayName: String { "Claude" }
    public var requiresAPIKey: Bool { true }
    public var defaultModel: String { Self.defaultModelID }
    public var availableModels: [String] { Self.knownModels.map(\.id) }

    func authorized(_ url: URL, timeout: TimeInterval) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        r.setValue(aiUserAgent, forHTTPHeaderField: "User-Agent")
        return r
    }

    public func chatRequest(messages: [ChatMessage], model: String, system: String?, options: ChatOptions) throws -> URLRequest {
        var r = authorized(Self.baseURL.appending(path: "messages"), timeout: AIClient.idleTimeout)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // `system` is a top-level field, not a message; a system role in `messages` is folded into it.
        let systemText = ([system] + messages.filter { $0.role == .system }.map(\.content)).compactMap { $0 }.joined(separator: "\n\n")
        var body: [String: Any] = [
            "model": model,
            "max_tokens": options.maxTokens,
            "messages": messages.filter { $0.role != .system }.map { ["role": $0.role.rawValue, "content": $0.content] },
            // Summaries are short and simple work.
            "output_config": ["effort": "low"],
            "stream": true,
        ]
        if !systemText.isEmpty { body["system"] = systemText }
        if Self.fallbackModels.contains(model) {
            // A refused request is retried on a fitting model instead of failing.
            r.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    public func events(fromLine line: String) throws -> [ChatEvent] {
        struct Usage: Decodable { let input_tokens: Int?; let output_tokens: Int? }
        struct Message: Decodable { let usage: Usage? }
        struct Delta: Decodable { let type: String?; let text: String?; let stop_reason: String? }
        struct ErrorBody: Decodable { let type: String?; let message: String }
        struct Details: Decodable { let explanation: String? }
        struct Event: Decodable {
            let type: String; let message: Message?; let delta: Delta?; let usage: Usage?
            let error: ErrorBody?; let stop_details: Details?
        }
        guard let json = SSE.data(line), let event = try? JSONDecoder().decode(Event.self, from: Data(json.utf8)) else { return [] }
        switch event.type {
        case "message_start":
            return event.message?.usage?.input_tokens.map { [.usage(input: $0, output: nil)] } ?? []
        case "content_block_delta" where event.delta?.type == "text_delta":
            return event.delta?.text.map { [.text($0)] } ?? []
        case "message_delta":
            var events: [ChatEvent] = []
            if let out = event.usage?.output_tokens { events.append(.usage(input: nil, output: out)) }
            switch event.delta?.stop_reason {
            case "refusal": throw AIError.refused(event.stop_details?.explanation)
            case "end_turn", "stop_sequence": events.append(.done(.finished))
            case "max_tokens": events.append(.done(.maxTokens))
            case let other?: events.append(.done(.other(other)))
            case nil: break
            }
            return events
        case "error":
            switch event.error?.type {
            case "overloaded_error", "api_error": throw AIError.outage(displayName)
            case "rate_limit_error": throw AIError.rateLimited(displayName)
            default: throw AIError.http(0, AIError.redacted(event.error?.message ?? "The stream failed."))
            }
        default:
            return []
        }
    }

    public func modelsRequest() -> URLRequest {
        authorized(Self.baseURL.appending(path: "models").appending(queryItems: [URLQueryItem(name: "limit", value: "100")]), timeout: 15)
    }

    public func decodeModels(_ data: Data) throws -> [String] {
        struct Model: Decodable { let id: String }
        struct List: Decodable { let data: [Model] }
        return try JSONDecoder().decode(List.self, from: data).data.map(\.id)
    }
}

// MARK: OpenAI

/// ChatGPT models through the Chat Completions API. Streams `data: {chunk}` lines ending in `data: [DONE]`.
/// OpenAI also has the Responses API (`/v1/responses`), with another request and event shape. This adapter
/// uses Chat Completions only; don't mix the two.
public struct OpenAIProvider: LLMProvider {
    public let key: String

    public init(key: String) { self.key = key }

    public static let baseURL = URL(string: "https://api.openai.com/v1/")!
    /// OpenAI's "start here" model, from developers.openai.com/api/docs/models on 2026-10-28.
    public static let defaultModelID = "gpt-6-astra"
    public static let knownModels: [(id: String, title: String)] = [
        ("gpt-6-astra", "GPT-6 Astra"), ("gpt-6.1-sol", "GPT-6.1 Sol"), ("gpt-6.1-terra", "GPT-6.1 Terra"), ("gpt-6-luna", "GPT-6 Luna"),
    ]

    public static func title(for model: String) -> String {
        knownModels.first { $0.id == model }?.title ?? model
    }

    public var id: AIProvider { .openai }
    public var displayName: String { "OpenAI" }
    public var requiresAPIKey: Bool { true }
    public var defaultModel: String { Self.defaultModelID }
    public var availableModels: [String] { Self.knownModels.map(\.id) }

    func authorized(_ url: URL, timeout: TimeInterval) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        r.setValue(aiUserAgent, forHTTPHeaderField: "User-Agent")
        return r
    }

    public func chatRequest(messages: [ChatMessage], model: String, system: String?, options: ChatOptions) throws -> URLRequest {
        var r = authorized(Self.baseURL.appending(path: "chat/completions"), timeout: AIClient.idleTimeout)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "messages": wireMessages(messages, system: system),
            // `max_tokens` is deprecated and rejected by reasoning models.
            "max_completion_tokens": options.maxTokens,
            "stream": true,
            // One more chunk before [DONE], with empty choices and the token counts.
            "stream_options": ["include_usage": true],
        ]
        if let t = options.temperature { body["temperature"] = t }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    public func events(fromLine line: String) throws -> [ChatEvent] {
        struct Delta: Decodable { let content: String?; let refusal: String? }
        struct Choice: Decodable { let delta: Delta?; let finish_reason: String? }
        struct Usage: Decodable { let prompt_tokens: Int?; let completion_tokens: Int? }
        struct ErrorBody: Decodable { let message: String? }
        struct Chunk: Decodable { let choices: [Choice]?; let usage: Usage?; let error: ErrorBody? }
        guard let json = SSE.data(line), json != "[DONE]",
              let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(json.utf8)) else { return [] }
        if let error = chunk.error { throw AIError.http(0, AIError.redacted(error.message ?? "The stream failed.")) }
        var events: [ChatEvent] = []
        for choice in chunk.choices ?? [] {
            if let refusal = choice.delta?.refusal, !refusal.isEmpty { throw AIError.refused(refusal) }
            if let text = choice.delta?.content, !text.isEmpty { events.append(.text(text)) }
            switch choice.finish_reason {
            case "stop": events.append(.done(.finished))
            case "length": events.append(.done(.maxTokens))
            case "content_filter": events.append(.done(.refused))
            case let other?: events.append(.done(.other(other)))
            case nil: break
            }
        }
        if let usage = chunk.usage { events.append(.usage(input: usage.prompt_tokens, output: usage.completion_tokens)) }
        return events
    }

    public func modelsRequest() -> URLRequest {
        authorized(Self.baseURL.appending(path: "models"), timeout: 15)
    }

    /// `GET /v1/models` lists every model the key can use, audio and images too. Keep the chat ones.
    public func decodeModels(_ data: Data) throws -> [String] {
        struct Model: Decodable { let id: String }
        struct List: Decodable { let data: [Model] }
        let skip = ["audio", "realtime", "tts", "transcribe", "image", "embedding", "search", "moderation"]
        return try JSONDecoder().decode(List.self, from: data).data.map(\.id)
            .filter { id in id.hasPrefix("gpt-") && !skip.contains { id.contains($0) } }
            .sorted()
    }
}

/// System first, as a message: the shape Ollama and OpenAI both take.
private func wireMessages(_ messages: [ChatMessage], system: String?) -> [[String: String]] {
    let all = (system.map { [ChatMessage(.system, $0)] } ?? []) + messages
    return all.map { ["role": $0.role.rawValue, "content": $0.content] }
}
