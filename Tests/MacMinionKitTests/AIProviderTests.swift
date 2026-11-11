import Foundation
import Testing
@testable import MacMinionKit

// Adapter tests: request encoding, and parsing of recorded streams in Fixtures/. No network.

private func fixture(_ name: String) throws -> [String] {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
}

private func events(_ provider: any LLMProvider, _ name: String) throws -> [ChatEvent] {
    try fixture(name).flatMap { try provider.events(fromLine: $0) }
}

private func text(_ events: [ChatEvent]) -> String {
    events.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined()
}

private func body(_ r: URLRequest) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: r.httpBody ?? Data()) as? [String: Any])
}

// MARK: Ollama

@Test func ollamaRequestShape() throws {
    let r = try OllamaProvider().chatRequest(messages: [ChatMessage(.user, "P")], model: "llama3.2", system: "S", options: ChatOptions())
    #expect(r.url?.absoluteString == "http://localhost:11434/api/chat")
    #expect(r.httpMethod == "POST" && r.timeoutInterval == AIClient.idleTimeout)
    let b = try body(r)
    #expect(b["model"] as? String == "llama3.2" && b["stream"] as? Bool == true && b["keep_alive"] as? String == "10m")
    #expect((b["options"] as? [String: Any])?["num_ctx"] as? Int == 16_384)
    #expect(b["options"].flatMap { ($0 as? [String: Any])?["num_predict"] } == nil, "Ollama gets no token limit, as before")
    let messages = try #require(b["messages"] as? [[String: String]])
    #expect(messages == [["role": "system", "content": "S"], ["role": "user", "content": "P"]])
    #expect(r.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func ollamaParsesRecordedStream() throws {
    let e = try events(OllamaProvider(), "ollama-stream.ndjson")
    #expect(text(e) == "• Fixes a crash on login")
    #expect(e.suffix(2) == [.usage(input: 398, output: 11), .done(.finished)])
    #expect(throws: AIError.http(0, "model not found")) { try OllamaProvider().events(fromLine: #"{"error":"model not found"}"#) }
}

// MARK: Anthropic

@Test func anthropicRequestShape() throws {
    let r = try AnthropicProvider(key: "sk-test").chatRequest(messages: [ChatMessage(.user, "P")], model: "claude-opus-5-5",
                                                             system: "S", options: ChatOptions(maxTokens: 900, temperature: 0.2))
    #expect(r.url?.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(r.value(forHTTPHeaderField: "x-api-key") == "sk-test")
    #expect(r.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
    #expect(r.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
    #expect(r.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("MacMinion/") == true)
    let b = try body(r)
    #expect(b["model"] as? String == "claude-opus-5-5" && b["system"] as? String == "S" && b["max_tokens"] as? Int == 900)
    #expect(b["stream"] as? Bool == true && b["fallbacks"] as? String == "default")
    #expect(b["temperature"] == nil, "API version 2026-10-21 rejects temperature")
    #expect(b["messages"] as? [[String: String]] == [["role": "user", "content": "P"]], "system is top-level, not a message")

    let haiku = try AnthropicProvider(key: "k").chatRequest(messages: [ChatMessage(.user, "P")], model: "claude-haiku-5-5",
                                                           system: nil, options: ChatOptions())
    #expect(try body(haiku)["fallbacks"] == nil && haiku.value(forHTTPHeaderField: "anthropic-beta") == nil,
            "Haiku 5.5 has no server-side fallback")
    #expect(try body(haiku)["system"] == nil)
}

@Test func anthropicParsesRecordedStream() throws {
    let e = try events(AnthropicProvider(key: "k"), "anthropic-stream.sse")
    #expect(text(e) == "• Fixes a crash on login", "thinking deltas are not the answer")
    #expect(e.first == .usage(input: 412, output: nil))
    #expect(e.suffix(2) == [.usage(input: nil, output: 38), .done(.finished)])
}

@Test func anthropicStreamErrors() {
    let p = AnthropicProvider(key: "k")
    #expect(throws: AIError.refused("no")) {
        try p.events(fromLine: #"data: {"type":"message_delta","delta":{"stop_reason":"refusal"},"stop_details":{"explanation":"no"}}"#)
    }
    #expect(throws: AIError.outage("Claude")) {
        try p.events(fromLine: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
    }
    #expect(throws: AIError.rateLimited("Claude")) {
        try p.events(fromLine: #"data: {"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}"#)
    }
}

// MARK: OpenAI

@Test func openAIRequestShape() throws {
    let r = try OpenAIProvider(key: "sk-test").chatRequest(messages: [ChatMessage(.user, "P")], model: "gpt-6-astra",
                                                          system: "S", options: ChatOptions(maxTokens: 900))
    #expect(r.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    #expect(r.value(forHTTPHeaderField: "x-api-key") == nil)
    let b = try body(r)
    #expect(b["model"] as? String == "gpt-6-astra" && b["stream"] as? Bool == true)
    #expect(b["max_completion_tokens"] as? Int == 900 && b["max_tokens"] == nil, "max_tokens is deprecated")
    #expect((b["stream_options"] as? [String: Bool]) == ["include_usage": true])
    #expect(b["messages"] as? [[String: String]] == [["role": "system", "content": "S"], ["role": "user", "content": "P"]])
}

@Test func openAIParsesRecordedStream() throws {
    let e = try events(OpenAIProvider(key: "k"), "openai-stream.sse")
    #expect(text(e) == "• Fixes a crash on login")
    #expect(e.suffix(2) == [.done(.finished), .usage(input: 405, output: 9)])
    #expect(try OpenAIProvider(key: "k").events(fromLine: "data: [DONE]").isEmpty)
    #expect(throws: AIError.refused("I can't help with that.")) {
        try OpenAIProvider(key: "k").events(fromLine: #"data: {"choices":[{"delta":{"refusal":"I can't help with that."},"finish_reason":null}]}"#)
    }
}

@Test func openAIModelListKeepsChatModels() throws {
    let json = #"{"object":"list","data":[{"id":"gpt-6-astra"},{"id":"gpt-6-luna"},{"id":"gpt-image-2"},{"id":"text-embedding-3-large"},{"id":"gpt-realtime"},{"id":"whisper-1"}]}"#
    #expect(try OpenAIProvider(key: "k").decodeModels(Data(json.utf8)) == ["gpt-6-astra", "gpt-6-luna"])
    let anthropic = #"{"data":[{"type":"model","id":"claude-opus-5-5","display_name":"Claude Opus 5.5"}],"has_more":false}"#
    #expect(try AnthropicProvider(key: "k").decodeModels(Data(anthropic.utf8)) == ["claude-opus-5-5"])
    #expect(AnthropicProvider(key: "k").modelsRequest().url?.absoluteString == "https://api.anthropic.com/v1/models?limit=100")
    #expect(OpenAIProvider(key: "k").modelsRequest().value(forHTTPHeaderField: "Authorization") == "Bearer k")
}

// MARK: Errors, config, retry

@Test func statusCodesBecomePlainMessages() {
    #expect(AIError.forStatus(401, body: Data(), provider: "OpenAI") == .badKey("OpenAI"))
    #expect(AIError.forStatus(403, body: Data(), provider: "Claude") == .badKey("Claude"))
    #expect(AIError.forStatus(429, body: Data(), provider: "Claude") == .rateLimited("Claude"))
    #expect(AIError.forStatus(529, body: Data(), provider: "Claude") == .outage("Claude"))
    #expect(AIError.forStatus(503, body: Data(), provider: "OpenAI").isRetryable)
    let anthropic = #"{"type":"error","error":{"type":"invalid_request_error","message":"model: not found"}}"#
    #expect(AIError.forStatus(404, body: Data(anthropic.utf8), provider: "Claude") == .http(404, "model: not found"))
    let openAI = #"{"error":{"message":"Incorrect API key provided: sk-proj-abc***xyz.","type":"invalid_request_error","code":"invalid_api_key"}}"#
    let message = AIError.forStatus(400, body: Data(openAI.utf8), provider: "OpenAI").localizedDescription
    #expect(!message.contains("sk-") && message.contains("[key]"), "keys never reach error messages")
    #expect(ConnectionStatus(AIError.badKey("OpenAI")) == .invalidKey)
    #expect(ConnectionStatus(AIError.rateLimited("OpenAI")).title == "Rate limited")
}

@Test func unconfiguredProvidersExplainWhy() {
    #expect(AIConfig(provider: .claude).problem == "Add a Claude API key in Settings.")
    #expect(AIConfig(provider: .openai).problem == "Add an OpenAI API key in Settings.")
    #expect(AIConfig(provider: .openai, openAIModel: "", openAIKey: "k").problem == "Choose an OpenAI model in Settings.")
    #expect(AIConfig(provider: .ollama).problem == "Choose an Ollama model in Settings.")
    #expect(AIConfig(provider: .ollama, ollamaModel: "m").problem == nil)
    #expect(AIConfig(provider: .off).llm == nil)
    #expect(AIConfig(provider: .openai, openAIKey: "k").model == "gpt-6-astra")
    #expect(AIConfig(provider: .claude, claudeKey: "k").model == "claude-opus-5-5")
    #expect(KeychainStore.account(for: .claude) == "claude-api-key", "saved Claude keys carry over")
    #expect(KeychainStore.account(for: .openai) == "openai-api-key")
}

@Test func retryBacksOffOnlyOnRateLimitsAndOutages() async throws {
    #expect(AIRetry.delay(attempt: 3, base: .milliseconds(100), jitter: 1) == .milliseconds(400))
    #expect(AIRetry.delay(attempt: 1, base: .milliseconds(100), jitter: 0.5) == .milliseconds(50))
    final class Counter: @unchecked Sendable { var n = 0 }
    let tries = Counter()
    let answer = try await AIRetry.run(base: .milliseconds(1)) {
        tries.n += 1
        if tries.n < 3 { throw AIError.rateLimited("OpenAI") }
        return "ok"
    }
    #expect(answer == "ok" && tries.n == 3)
    let once = Counter()
    await #expect(throws: AIError.badKey("OpenAI")) {
        try await AIRetry.run(base: .milliseconds(1)) { () async throws -> String in
            once.n += 1
            throw AIError.badKey("OpenAI")
        }
    }
    #expect(once.n == 1, "a bad key is not retried")
}

/// A server that sends headers, then nothing. Records when URLSession stops the request.
final class HangingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
    override func stopLoading() { Self.stopped = true }
}

@Test func cancellingStopsTheRequest() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [HangingProtocol.self]
    let session = URLSession(configuration: config)
    let task = Task {
        for try await _ in OllamaProvider().streamChat(messages: [ChatMessage(.user, "P")], model: "m", system: nil, session: session) {}
    }
    try await Task.sleep(for: .milliseconds(200))
    task.cancel()
    _ = await task.result
    for _ in 0..<20 where !HangingProtocol.stopped { try await Task.sleep(for: .milliseconds(50)) }
    #expect(HangingProtocol.stopped, "cancelling the consumer aborts the HTTP request")
}

// MARK: Live smoke tests, skipped unless a key is in the environment. Keys are never committed.

private let env = ProcessInfo.processInfo.environment

@Test(.enabled(if: env["MACMINION_LIVE_ANTHROPIC_KEY"] != nil))
func liveAnthropic() async throws {
    let config = AIConfig(provider: .claude, claudeKey: env["MACMINION_LIVE_ANTHROPIC_KEY"] ?? "")
    #expect(try await !AIClient(config: config).complete(system: "Answer in five words or fewer.", prompt: "Say hello.").isEmpty)
}

@Test(.enabled(if: env["MACMINION_LIVE_OPENAI_KEY"] != nil))
func liveOpenAI() async throws {
    let config = AIConfig(provider: .openai, openAIKey: env["MACMINION_LIVE_OPENAI_KEY"] ?? "")
    #expect(try await !AIClient(config: config).complete(system: "Answer in five words or fewer.", prompt: "Say hello.").isEmpty)
}

@Test(.enabled(if: env["MACMINION_LIVE_OLLAMA_MODEL"] != nil))
func liveOllama() async throws {
    let config = AIConfig(provider: .ollama, ollamaModel: env["MACMINION_LIVE_OLLAMA_MODEL"] ?? "")
    #expect(try await !AIClient(config: config).complete(system: "Answer in five words or fewer.", prompt: "Say hello.").isEmpty)
}
