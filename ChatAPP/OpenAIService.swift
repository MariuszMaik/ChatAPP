import Foundation

// MARK: - Errors

enum OpenAIError: LocalizedError {
    case invalidURL
    case httpError(Int, String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Invalid API endpoint URL."
        case .httpError(let c, _): return "HTTP \(c) — check your endpoint and API key."
        case .apiError(let msg):   return msg
        }
    }
}

// MARK: - Decodable types

private struct ModelsResponse: Decodable {
    struct ModelObject: Decodable { let id: String }
    let data: [ModelObject]
}

private struct ErrorEnvelope: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
}

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta
    }
    let choices: [Choice]
}

// MARK: - Chat completion (non-streaming, for tool-call loop)

struct ChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String?
            let tool_calls: [APIToolCall]?
        }
        let message: Message
        let finish_reason: String?
    }
    let choices: [Choice]

    var firstChoice: Choice? { choices.first }
    var finishReason: String? { firstChoice?.finish_reason }
    var content: String? { firstChoice?.message.content }
    var apiToolCalls: [APIToolCall]? { firstChoice?.message.tool_calls }
}

struct APIToolCall: Decodable {
    let id: String
    let type: String
    struct FunctionData: Decodable {
        let name: String
        let arguments: String
    }
    let function: FunctionData
}

// MARK: - Service

actor OpenAIService {
    static let shared = OpenAIService()

    // MARK: Fetch models

    func fetchModels(endpoint: String, apiKey: String) async throws -> [String] {
        let url = try resolve(endpoint, path: "/models")
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        try assertOK(response, data: data)
        return try JSONDecoder().decode(ModelsResponse.self, from: data)
            .data.map(\.id).sorted()
    }

    // MARK: Streaming chat (no tools)

    func streamChat(
        messages: [Message],
        settings: AppSettings,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        let url = try resolve(settings.apiEndpoint, path: "/chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try buildBody(messages: messages, model: settings.selectedModel, stream: true)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var raw = Data()
            for try await byte in bytes { raw.append(byte) }
            let msg = (try? JSONDecoder().decode(ErrorEnvelope.self, from: raw))?.error.message ?? "Unknown"
            throw OpenAIError.httpError(http.statusCode, msg)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            guard json != "[DONE]",
                  let data  = json.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                  let text  = chunk.choices.first?.delta.content
            else { continue }
            onToken(text)
        }
    }

    // MARK: Non-streaming chat (used in tool-calling loop)

    func sendChatCompletion(
        apiMessages: [[String: Any]],
        settings: AppSettings,
        tools: [[String: Any]]
    ) async throws -> ChatCompletion {
        let url = try resolve(settings.apiEndpoint, path: "/chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model":    settings.selectedModel,
            "messages": apiMessages
        ]
        if !tools.isEmpty { body["tools"] = tools }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try assertOK(response, data: data)
        return try JSONDecoder().decode(ChatCompletion.self, from: data)
    }

    // MARK: Build message array for API (shared)

    func buildAPIMessages(from messages: [Message]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for msg in messages where !msg.isStreaming {
            var dict: [String: Any] = ["role": msg.role.rawValue]

            switch msg.role {
            case .tool:
                dict["content"]       = msg.content
                dict["tool_call_id"]  = msg.toolCallId ?? ""

            case .assistant where msg.toolCalls != nil:
                dict["content"] = NSNull()
                dict["tool_calls"] = (msg.toolCalls ?? []).map { tc -> [String: Any] in
                    ["id": tc.id, "type": "function",
                     "function": ["name": tc.name, "arguments": tc.arguments]]
                }

            default:
                let imageAtts = msg.attachments.filter { $0.type == .image }
                let textAtts  = msg.attachments.filter { $0.type != .image }

                if imageAtts.isEmpty && textAtts.isEmpty {
                    dict["content"] = msg.content
                } else {
                    var parts: [[String: Any]] = []
                    var fullText = msg.content
                    for att in textAtts {
                        fullText += "\n\n[\(att.name)]:\n\(att.text ?? "")"
                    }
                    if !fullText.isEmpty {
                        parts.append(["type": "text", "text": fullText])
                    }
                    for att in imageAtts {
                        if let d = att.data {
                            let b64 = d.base64EncodedString()
                            parts.append(["type": "image_url",
                                          "image_url": ["url": "data:image/png;base64,\(b64)"]])
                        }
                    }
                    dict["content"] = parts
                }
            }
            result.append(dict)
        }
        return result
    }

    // MARK: Helpers

    private func resolve(_ endpoint: String, path: String) throws -> URL {
        var base = endpoint
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        guard let url = URL(string: base + path) else { throw OpenAIError.invalidURL }
        return url
    }

    private func assertOK(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
                ?? "HTTP \(http.statusCode)"
            throw OpenAIError.httpError(http.statusCode, msg)
        }
    }

    private func buildBody(messages: [Message], model: String, stream: Bool) throws -> Data {
        let apiMessages = buildAPIMessages(from: messages)
        let body: [String: Any] = ["model": model, "messages": apiMessages, "stream": stream]
        return try JSONSerialization.data(withJSONObject: body)
    }
}
