import Foundation

// The provider-neutral AI layer. Each backend (Ollama, Anthropic, OpenAI) is an adapter that turns
// these types into its own wire format and parses its own stream back into `ChatEvent`s.
//
// Tool calling is not here: MacMinion only asks for text (summaries, suggestions, search), so no
// adapter sends tool definitions. Add a neutral tool schema here before any feature needs one.

public enum ChatRole: String, Sendable, Codable {
    case system, user, assistant, tool
}

public struct ChatMessage: Sendable, Equatable {
    public var role: ChatRole
    public var content: String

    public init(_ role: ChatRole, _ content: String) {
        self.role = role; self.content = content
    }
}

public struct ChatOptions: Sendable, Equatable {
    /// Required by Anthropic; OpenAI's `max_completion_tokens`. Ollama is sent no limit, as before.
    public var maxTokens: Int
    /// Ollama and OpenAI only. Anthropic API version 2026-10-21 rejects `temperature` with a 400.
    public var temperature: Double?

    public init(maxTokens: Int = 16_000, temperature: Double? = nil) {
        self.maxTokens = maxTokens; self.temperature = temperature
    }
}

/// Why the model stopped, in the same words for every provider.
public enum StopReason: Sendable, Equatable {
    case finished, maxTokens, refused, other(String)
}

public enum ChatEvent: Sendable, Equatable {
    case text(String)
    /// Token counts, when the provider reports them. Either can come alone.
    case usage(input: Int?, output: Int?)
    case done(StopReason)
}

/// One AI backend. Adapters only build requests and parse lines; `streamChat` does the networking.
public protocol LLMProvider: Sendable {
    var id: AIProvider { get }
    var displayName: String { get }
    var requiresAPIKey: Bool { get }
    var defaultModel: String { get }
    /// Models offered before a fetch, or when offline with no cached list.
    var availableModels: [String] { get }
    /// What to say when the server can't be reached.
    var unreachableMessage: String { get }

    func chatRequest(messages: [ChatMessage], model: String, system: String?, options: ChatOptions) throws -> URLRequest
    /// One line of the response stream (an NDJSON object or an SSE line): the events it carries.
    func events(fromLine line: String) throws -> [ChatEvent]
    func modelsRequest() -> URLRequest
    func decodeModels(_ data: Data) throws -> [String]
}

extension LLMProvider {
    public var unreachableMessage: String { "Can't reach \(displayName). Check your internet connection." }

    /// Streams one answer. Cancelling the consuming task (or dropping the stream) cancels the HTTP request.
    /// Nothing is retried mid-stream.
    public func streamChat(messages: [ChatMessage], model: String, system: String?, options: ChatOptions = ChatOptions(),
                           session: URLSession = .shared) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try chatRequest(messages: messages, model: model, system: system, options: options)
                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        var body = Data()
                        for try await byte in bytes where body.count < 65_536 { body.append(byte) }
                        throw AIError.forStatus(status, body: body, provider: displayName)
                    }
                    for try await line in bytes.lines {
                        for event in try events(fromLine: line) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AIError.wrap(error, provider: self))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The provider's model list. A setup request, so 429 and 5xx are retried with backoff.
    public func fetchModels(session: URLSession = .shared) async throws -> [String] {
        try await AIRetry.run {
            do {
                let (data, response) = try await session.data(for: modelsRequest())
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else { throw AIError.forStatus(status, body: data, provider: displayName) }
                return try decodeModels(data)
            } catch {
                throw AIError.wrap(error, provider: self)
            }
        }
    }
}

/// Limited exponential backoff with jitter, for setup requests only (model lists). Never for streams.
public enum AIRetry {
    public static func run<T: Sendable>(attempts: Int = 3, base: Duration = .milliseconds(500),
                                        _ work: @Sendable () async throws -> T) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await work()
            } catch let error as AIError where error.isRetryable && attempt < attempts {
                try await Task.sleep(for: delay(attempt: attempt, base: base))
                attempt += 1
            }
        }
    }

    /// base × 2^(attempt-1), scaled by a random 0.5–1.5 so clients don't retry in step.
    static func delay(attempt: Int, base: Duration, jitter: Double = .random(in: 0.5...1.5)) -> Duration {
        base * (Double(1 << (attempt - 1)) * jitter)
    }
}

/// Server-Sent Events: the JSON after `data:`, or nil for comments, `event:` lines, and blanks.
enum SSE {
    static func data(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        return line.dropFirst(5).trimmingCharacters(in: .whitespaces)
    }
}
