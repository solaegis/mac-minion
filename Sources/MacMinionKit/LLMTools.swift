import Foundation
import FoundationModels

// Tool calling (S-076): the model asks MacMinion for data by name ("addon_settings" with an addon), and
// MacMinion answers from what it has already read. Requests are not streamed: each turn is either text,
// or tool calls to answer and send back. Every tool takes text parameters only.

/// A tool the model may call: its name, what it does, and its text parameters.
public struct AIToolSpec: Sendable, Equatable {
    public struct Parameter: Sendable, Equatable {
        public let name: String
        public let description: String
        public let required: Bool
        public init(_ name: String, _ description: String, required: Bool = true) {
            self.name = name; self.description = description; self.required = required
        }
    }

    public let name: String
    public let description: String
    public let parameters: [Parameter]

    public init(name: String, description: String, parameters: [Parameter] = []) {
        self.name = name; self.description = description; self.parameters = parameters
    }

    /// The JSON Schema the hosted APIs take.
    var jsonSchema: [String: Any] {
        [
            "type": "object",
            "properties": Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, ["type": "string", "description": $0.description]) }),
            "required": parameters.filter(\.required).map(\.name),
        ]
    }
}

public struct AIToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let arguments: [String: String]
    public init(id: String, name: String, arguments: [String: String]) {
        self.id = id; self.name = name; self.arguments = arguments
    }

    /// Any JSON object as text arguments: numbers and booleans as written, anything nested as JSON.
    static func arguments(_ object: Any?) -> [String: String] {
        var out: [String: String] = [:]
        let dict: [String: Any]? = switch object {
        case let d as [String: Any]: d
        case let s as String: (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
        default: nil
        }
        for (k, v) in dict ?? [:] {
            switch v {
            case let s as String: out[k] = s
            case let n as NSNumber: out[k] = n.stringValue
            case is NSNull: break
            default:
                if let data = try? JSONSerialization.data(withJSONObject: v) { out[k] = String(decoding: data, as: UTF8.self) }
            }
        }
        return out
    }
}

public struct AIToolResult: Sendable, Equatable {
    public let id: String
    public let name: String
    public let content: String
    public init(id: String, name: String, content: String) { self.id = id; self.name = name; self.content = content }
}

/// One message of a tool conversation, before each provider's wire format.
public enum AIToolMessage: Sendable, Equatable {
    case user(String)
    case assistant(text: String, calls: [AIToolCall])
    case results([AIToolResult])
}

/// One answer: text, tool calls, or both.
public struct AIToolTurn: Sendable, Equatable {
    public let text: String
    public let calls: [AIToolCall]
    public let stop: StopReason
    public init(text: String, calls: [AIToolCall], stop: StopReason) { self.text = text; self.calls = calls; self.stop = stop }
}

/// A provider that can call tools: builds one request and reads one whole response.
public protocol LLMToolProvider: LLMProvider {
    func toolRequest(messages: [AIToolMessage], model: String, system: String, tools: [AIToolSpec], options: ChatOptions) throws -> URLRequest
    func decodeToolTurn(_ data: Data) throws -> AIToolTurn
}

/// A tool and what answers it. Answers are text, cut at `AITool.maxResult`.
public struct AITool: Sendable {
    public let spec: AIToolSpec
    public let run: @Sendable ([String: String]) async -> String
    public init(_ spec: AIToolSpec, run: @escaping @Sendable ([String: String]) async -> String) { self.spec = spec; self.run = run }

    /// Characters of one tool answer: enough for a table of settings, small enough for a local model.
    public static let maxResult = 6_000

    static func clipped(_ text: String) -> String {
        text.count <= maxResult ? text : String(text.prefix(maxResult)) + "\n… (cut: ask about something narrower)"
    }
}

// MARK: Wire formats

private func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

extension AnthropicProvider: LLMToolProvider {
    public func toolRequest(messages: [AIToolMessage], model: String, system: String, tools: [AIToolSpec], options: ChatOptions) throws -> URLRequest {
        var r = authorized(Self.baseURL.appending(path: "messages"), timeout: AIClient.idleTimeout)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let wire: [[String: Any]] = messages.map { m in
            switch m {
            case .user(let text): return ["role": "user", "content": text]
            case .assistant(let text, let calls):
                var blocks: [[String: Any]] = text.isEmpty ? [] : [["type": "text", "text": text]]
                blocks += calls.map { ["type": "tool_use", "id": $0.id, "name": $0.name, "input": $0.arguments] }
                return ["role": "assistant", "content": blocks]
            case .results(let results):
                return ["role": "user", "content": results.map { ["type": "tool_result", "tool_use_id": $0.id, "content": $0.content] }]
            }
        }
        var body: [String: Any] = [
            "model": model, "max_tokens": options.maxTokens, "system": system, "messages": wire,
            "tools": tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.jsonSchema] },
        ]
        if Self.fallbackModels.contains(model) {
            r.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        r.httpBody = try json(body)
        return r
    }

    public func decodeToolTurn(_ data: Data) throws -> AIToolTurn {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.empty }
        var text = "", calls: [AIToolCall] = []
        for block in object["content"] as? [[String: Any]] ?? [] {
            switch block["type"] as? String {
            case "text": text += block["text"] as? String ?? ""
            case "tool_use":
                calls.append(AIToolCall(id: block["id"] as? String ?? UUID().uuidString, name: block["name"] as? String ?? "",
                                        arguments: AIToolCall.arguments(block["input"])))
            default: break
            }
        }
        let stop: StopReason = switch object["stop_reason"] as? String {
        case "refusal": throw AIError.refused(nil)
        case "max_tokens": .maxTokens
        case "end_turn", "stop_sequence", "tool_use", nil: .finished
        case let other?: .other(other)
        }
        return AIToolTurn(text: text, calls: calls, stop: stop)
    }
}

/// OpenAI and Ollama share a message shape; they differ in how tool calls carry their arguments.
private func chatToolMessages(_ messages: [AIToolMessage], system: String, argumentsAsText: Bool) -> [[String: Any]] {
    var wire: [[String: Any]] = [["role": "system", "content": system]]
    for m in messages {
        switch m {
        case .user(let text): wire.append(["role": "user", "content": text])
        case .assistant(let text, let calls):
            var message: [String: Any] = ["role": "assistant", "content": text]
            if !calls.isEmpty {
                message["tool_calls"] = calls.map { call -> [String: Any] in
                    let arguments: Any = argumentsAsText
                        ? String(decoding: (try? JSONSerialization.data(withJSONObject: call.arguments)) ?? Data("{}".utf8), as: UTF8.self)
                        : call.arguments
                    return ["id": call.id, "type": "function", "function": ["name": call.name, "arguments": arguments]]
                }
            }
            wire.append(message)
        case .results(let results):
            for r in results { wire.append(["role": "tool", "tool_call_id": r.id, "tool_name": r.name, "content": r.content]) }
        }
    }
    return wire
}

private func chatTools(_ tools: [AIToolSpec]) -> [[String: Any]] {
    tools.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.jsonSchema]] }
}

/// Tool calls in a Chat Completions or Ollama message; Ollama gives no IDs, so they're numbered.
private func chatCalls(_ message: [String: Any]?) -> [AIToolCall] {
    (message?["tool_calls"] as? [[String: Any]] ?? []).enumerated().map { i, call in
        let function = call["function"] as? [String: Any]
        return AIToolCall(id: call["id"] as? String ?? "call_\(i)", name: function?["name"] as? String ?? "",
                          arguments: AIToolCall.arguments(function?["arguments"]))
    }
}

extension OpenAIProvider: LLMToolProvider {
    public func toolRequest(messages: [AIToolMessage], model: String, system: String, tools: [AIToolSpec], options: ChatOptions) throws -> URLRequest {
        var r = authorized(Self.baseURL.appending(path: "chat/completions"), timeout: AIClient.idleTimeout)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try json([
            "model": model, "messages": chatToolMessages(messages, system: system, argumentsAsText: true),
            "tools": chatTools(tools), "max_completion_tokens": options.maxTokens,
        ] as [String: Any])
        return r
    }

    public func decodeToolTurn(_ data: Data) throws -> AIToolTurn {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (object["choices"] as? [[String: Any]])?.first else { throw AIError.empty }
        let message = choice["message"] as? [String: Any]
        if let refusal = message?["refusal"] as? String, !refusal.isEmpty { throw AIError.refused(refusal) }
        let stop: StopReason = switch choice["finish_reason"] as? String {
        case "length": .maxTokens
        case "content_filter": .refused
        case "stop", "tool_calls", nil: .finished
        case let other?: .other(other)
        }
        return AIToolTurn(text: message?["content"] as? String ?? "", calls: chatCalls(message), stop: stop)
    }
}

extension OllamaProvider: LLMToolProvider {
    public func toolRequest(messages: [AIToolMessage], model: String, system: String, tools: [AIToolSpec], options: ChatOptions) throws -> URLRequest {
        var r = URLRequest(url: base.appending(path: "api/chat"), timeoutInterval: AIClient.idleTimeout)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try json([
            "model": model, "stream": false, "messages": chatToolMessages(messages, system: system, argumentsAsText: false),
            "tools": chatTools(tools), "options": ["num_ctx": 16_384], "keep_alive": "10m",
        ] as [String: Any])
        return r
    }

    public func decodeToolTurn(_ data: Data) throws -> AIToolTurn {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.empty }
        if let error = object["error"] as? String { throw AIError.http(0, error) }
        let message = object["message"] as? [String: Any]
        let stop: StopReason = object["done_reason"] as? String == "length" ? .maxTokens : .finished
        return AIToolTurn(text: message?["content"] as? String ?? "", calls: chatCalls(message), stop: stop)
    }
}

// MARK: Apple Intelligence

/// One MacMinion tool as a Foundation Models tool: text parameters in a schema built at run time.
struct AppleTool: Tool {
    let tool: AITool
    let onCall: @Sendable (AIToolCall) async -> Void

    var name: String { tool.spec.name }
    var description: String { tool.spec.description }
    var parameters: GenerationSchema {
        let root = DynamicGenerationSchema(name: tool.spec.name, properties: tool.spec.parameters.map {
            .init(name: $0.name, description: $0.description, schema: DynamicGenerationSchema(type: String.self), isOptional: !$0.required)
        })
        // A schema of plain text fields can't fail to build.
        return (try? GenerationSchema(root: root, dependencies: [])) ?? GenerationSchema(type: String.self, properties: [])
    }

    func call(arguments: GeneratedContent) async throws -> String {
        var args: [String: String] = [:]
        for p in tool.spec.parameters {
            if let value = try? arguments.value(String?.self, forProperty: p.name) { args[p.name] = value }
        }
        let call = AIToolCall(id: UUID().uuidString, name: name, arguments: args)
        await onCall(call)
        return AITool.clipped(await tool.run(args))
    }
}

extension AppleIntelligence {
    /// One answer, with the session calling MacMinion's tools as it needs them.
    static func answer(system: String, prompt: String, tools: [AITool], onCall: @escaping @Sendable (AIToolCall) async -> Void) async throws -> String {
        if let why = unavailableReason { throw AIError.notConfigured(why) }
        let session = LanguageModelSession(tools: tools.map { AppleTool(tool: $0, onCall: onCall) }, instructions: system)
        do {
            let text = try await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AIError.empty }
            return text
        } catch {
            throw mapError(error)
        }
    }
}

// MARK: The loop

extension AIClient {
    /// Most rounds of tool calls before the model must answer.
    public static let maxToolRounds = 8

    /// Answers `prompt`, letting the model call `tools` for what it needs. `onCall` hears each call, to
    /// show what the model is looking at.
    public func answer(system: String, prompt: String, tools: [AITool],
                       onCall: @escaping @Sendable (AIToolCall) async -> Void = { _ in }) async throws -> String {
        if let problem = config.problem { throw AIError.notConfigured(problem) }
        if config.provider == .apple {
            return try await AppleIntelligence.answer(system: system, prompt: prompt, tools: tools, onCall: onCall)
        }
        guard let llm = config.llm as? any LLMToolProvider else {
            throw AIError.notConfigured(String(localized: "AI is turned off in Settings.", bundle: .kit))
        }
        let byName = Dictionary(tools.map { ($0.spec.name, $0) }, uniquingKeysWith: { a, _ in a })
        var messages: [AIToolMessage] = [.user(prompt)]
        for round in 0...Self.maxToolRounds {
            // The last round offers no tools, so the model answers with what it has.
            let offered = round == Self.maxToolRounds ? [] : tools.map(\.spec)
            let request = try llm.toolRequest(messages: messages, model: config.model, system: system, tools: offered,
                                              options: ChatOptions(maxTokens: 4_000))
            let turn = try await send(request, with: llm)
            if turn.stop == .refused { throw AIError.refused(nil) }
            guard !turn.calls.isEmpty else {
                let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw AIError.empty }
                return text
            }
            var results: [AIToolResult] = []
            for call in turn.calls {
                await onCall(call)
                let answer = await byName[call.name]?.run(call.arguments)
                    ?? "No tool is named \(call.name). Use one of: \(tools.map(\.spec.name).joined(separator: ", "))."
                results.append(AIToolResult(id: call.id, name: call.name, content: AITool.clipped(answer)))
            }
            messages += [.assistant(text: turn.text, calls: turn.calls), .results(results)]
        }
        throw AIError.empty
    }

    private func send(_ request: URLRequest, with llm: any LLMToolProvider) async throws -> AIToolTurn {
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                // Ollama refuses tools for models that weren't trained to use them.
                if status == 400, String(decoding: data, as: UTF8.self).contains("does not support tools") {
                    throw AIError.notConfigured(String(localized: "\(config.model) can't look things up. Choose a model with tool support in Settings > AI, like gemma4, llama3.3, or qwen2.5.", bundle: .kit))
                }
                throw AIError.forStatus(status, body: data, provider: llm.displayName)
            }
            return try llm.decodeToolTurn(data)
        } catch {
            throw AIError.wrap(error, provider: llm)
        }
    }
}
