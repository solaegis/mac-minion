import Foundation
import Testing
@testable import MacMinionKit

private let spec = AIToolSpec(name: "addon_settings", description: "One addon's settings.",
                              parameters: [.init("addon", "The addon."), .init("character", "Optional.", required: false)])
private let call = AIToolCall(id: "c1", name: "addon_settings", arguments: ["addon": "WritWorthy"])
private let conversation: [AIToolMessage] = [
    .user("Which characters have Auto craft off?"),
    .assistant(text: "Looking.", calls: [call]),
    .results([AIToolResult(id: "c1", name: "addon_settings", content: "Auto craft: Off on 1")]),
]

private func body(_ r: URLRequest) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: r.httpBody ?? Data()) as? [String: Any])
}

@Test func toolSchemasTakeTextParameters() {
    let schema = spec.jsonSchema
    #expect(schema["required"] as? [String] == ["addon"])
    let properties = schema["properties"] as? [String: [String: String]]
    #expect(properties?["addon"]?["type"] == "string" && properties?["character"]?["description"] == "Optional.")
}

@Test func anthropicToolTurns() throws {
    let r = try AnthropicProvider(key: "k").toolRequest(messages: conversation, model: "claude-haiku-5-5", system: "S", tools: [spec], options: ChatOptions())
    let b = try body(r)
    #expect(b["system"] as? String == "S" && b["stream"] == nil)
    #expect((b["tools"] as? [[String: Any]])?.first?["input_schema"] != nil)
    let messages = try #require(b["messages"] as? [[String: Any]])
    let assistant = try #require(messages[1]["content"] as? [[String: Any]])
    #expect(assistant.map { $0["type"] as? String } == ["text", "tool_use"])
    #expect((assistant[1]["input"] as? [String: String]) == ["addon": "WritWorthy"])
    let result = try #require((messages[2]["content"] as? [[String: Any]])?.first)
    #expect(result["type"] as? String == "tool_result" && result["tool_use_id"] as? String == "c1")
    let turn = try AnthropicProvider(key: "k").decodeToolTurn(Data(#"""
    {"content":[{"type":"text","text":"Let me check."},{"type":"tool_use","id":"t9","name":"setting_values","input":{"addon":"WW","limit":3}}],"stop_reason":"tool_use"}
    """#.utf8))
    #expect(turn.text == "Let me check." && turn.calls == [AIToolCall(id: "t9", name: "setting_values", arguments: ["addon": "WW", "limit": "3"])])
    #expect(throws: AIError.self) { try AnthropicProvider(key: "k").decodeToolTurn(Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8)) }
}

@Test func openAIToolTurns() throws {
    let b = try body(OpenAIProvider(key: "k").toolRequest(messages: conversation, model: "gpt-6-astra", system: "S", tools: [spec], options: ChatOptions()))
    let messages = try #require(b["messages"] as? [[String: Any]])
    #expect(messages.map { $0["role"] as? String } == ["system", "user", "assistant", "tool"])
    let function = ((messages[2]["tool_calls"] as? [[String: Any]])?.first?["function"]) as? [String: Any]
    #expect(function?["arguments"] as? String == #"{"addon":"WritWorthy"}"#, "OpenAI takes arguments as JSON text")
    #expect(messages[3]["tool_call_id"] as? String == "c1")
    #expect(((b["tools"] as? [[String: Any]])?.first?["type"]) as? String == "function")
    let turn = try OpenAIProvider(key: "k").decodeToolTurn(Data(#"""
    {"choices":[{"message":{"content":null,"tool_calls":[{"id":"x","type":"function","function":{"name":"list_addons","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}
    """#.utf8))
    #expect(turn.calls == [AIToolCall(id: "x", name: "list_addons", arguments: [:])] && turn.text.isEmpty)
}

@Test func ollamaToolTurns() throws {
    let b = try body(OllamaProvider().toolRequest(messages: conversation, model: "qwen3", system: "S", tools: [spec], options: ChatOptions()))
    #expect(b["stream"] as? Bool == false)
    let messages = try #require(b["messages"] as? [[String: Any]])
    let function = ((messages[2]["tool_calls"] as? [[String: Any]])?.first?["function"]) as? [String: Any]
    #expect(function?["arguments"] as? [String: String] == ["addon": "WritWorthy"], "Ollama takes arguments as an object")
    let turn = try OllamaProvider().decodeToolTurn(Data(#"""
    {"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"problems","arguments":{"addon":"Dustman"}}}]},"done":true}
    """#.utf8))
    #expect(turn.calls == [AIToolCall(id: "call_0", name: "problems", arguments: ["addon": "Dustman"])])
}

/// Answers each request with the next scripted Ollama reply, and keeps the bodies sent.
final class ScriptedProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var replies: [String] = []
    nonisolated(unsafe) static var sent: [[String: Any]] = []
    nonisolated(unsafe) static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
            stream.close()
        }
        Self.sent.append((try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
        let reply = Self.replies.isEmpty ? "{}" : Self.replies.removeFirst()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor Heard {
    var names: [String] = []
    func add(_ name: String) { names.append(name) }
}

@Test func longToolAnswersAreCut() {
    let long = String(repeating: "x", count: AITool.maxResult + 50)
    #expect(AITool.clipped(long).hasSuffix("ask about something narrower)"))
    #expect(AITool.clipped("short") == "short")
}

/// Both share `ScriptedProtocol`'s replies, so they run one after the other.
@Suite(.serialized) struct ToolLoopTests {
    @Test func theLoopAnswersToolCallsUntilTheModelReplies() async throws {
        ScriptedProtocol.sent = []
        ScriptedProtocol.status = 200
        ScriptedProtocol.replies = [
            #"{"message":{"content":"","tool_calls":[{"function":{"name":"addon_settings","arguments":{"addon":"WritWorthy"}}},{"function":{"name":"nope","arguments":{}}}]},"done":true}"#,
            #"{"message":{"content":"Alpha Top has Auto craft off."},"done":true}"#,
        ]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedProtocol.self]
        let client = AIClient(config: AIConfig(provider: .ollama, ollamaModel: "qwen3"), session: URLSession(configuration: configuration))
        let tool = AITool(spec) { args in "Auto craft: Off on Alpha Top (\(args["addon"] ?? ""))" }
        let heard = Heard()
        let answer = try await client.answer(system: "S", prompt: "Who has Auto craft off?", tools: [tool]) { await heard.add($0.name) }
        #expect(answer == "Alpha Top has Auto craft off.")
        #expect(await heard.names == ["addon_settings", "nope"])
        let second = try #require(ScriptedProtocol.sent.last?["messages"] as? [[String: Any]])
        let results = second.filter { $0["role"] as? String == "tool" }.map { $0["content"] as? String ?? "" }
        #expect(results.first == "Auto craft: Off on Alpha Top (WritWorthy)")
        #expect(results.last?.hasPrefix("No tool is named nope") == true, "an unknown tool is answered, not thrown")
    }

    @Test func aModelWithoutToolsSaysWhichToChoose() async throws {
        ScriptedProtocol.status = 400
        ScriptedProtocol.replies = [#"{"error":"registry.ollama.ai/library/phi4:latest does not support tools"}"#]
        defer { ScriptedProtocol.status = 200 }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedProtocol.self]
        let client = AIClient(config: AIConfig(provider: .ollama, ollamaModel: "phi4:latest"), session: URLSession(configuration: configuration))
        do {
            _ = try await client.answer(system: "S", prompt: "P", tools: [AITool(spec) { _ in "" }])
            Issue.record("expected an error")
        } catch {
            #expect(error.localizedDescription.hasPrefix("phi4:latest can't look things up."), "\(error.localizedDescription)")
        }
    }
}
