import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AIProtocol: String, Codable, CaseIterable, Sendable, Identifiable {
    case chatCompletions, responses, generateContent, messages
    public var id: Self { self }
    public var label: String {
        switch self {
        case .chatCompletions: "OpenAI · Chat Completions"
        case .responses: "OpenAI · Responses API"
        case .generateContent: "Gemini · GenerateContent"
        case .messages: "Claude · Messages"
        }
    }
    public var defaultBase: String {
        switch self {
        case .chatCompletions, .responses: "https://api.openai.com/v1"
        case .generateContent: "https://generativelanguage.googleapis.com/v1beta"
        case .messages: "https://api.anthropic.com/v1"
        }
    }
}

public struct AIConfiguration: Hashable, Codable, Sendable {
    public var apiType: AIProtocol
    public var baseURL: String
    public var model: String
    public init(apiType: AIProtocol = .chatCompletions, baseURL: String = "https://api.openai.com/v1", model: String = "") {
        self.apiType = apiType; self.baseURL = baseURL; self.model = model
    }
}
public struct AIImage: Hashable, Sendable {
    public var data: Data
    public var mimeType: String
    public init(data: Data, mimeType: String = "image/jpeg") { self.data = data; self.mimeType = mimeType }
}
public struct AIToolCall: Hashable, Sendable {
    public var id: String
    public var name: String
    public var arguments: JSONValue
    public var providerPart: JSONValue?
    public init(id: String = UUID().uuidString, name: String, arguments: JSONValue, providerPart: JSONValue? = nil) {
        self.id = id; self.name = name; self.arguments = arguments
        self.providerPart = providerPart
    }
}
public struct AIMessage: Hashable, Sendable {
    public var role: String
    public var text: String
    public var images: [AIImage]
    public var calls: [AIToolCall]
    public var toolCallID: String?
    public var toolName: String?
    public var providerItems: [JSONValue]
    public init(role: String, text: String = "", images: [AIImage] = [], calls: [AIToolCall] = [], toolCallID: String? = nil, toolName: String? = nil, providerItems: [JSONValue] = []) {
        self.role = role; self.text = text; self.images = images; self.calls = calls
        self.toolCallID = toolCallID; self.toolName = toolName
        self.providerItems = providerItems
    }
}
public struct AIResponse: Sendable { public var text: String; public var calls: [AIToolCall]; public var providerItems: [JSONValue] = [] }
public struct AIModel: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public init(id: String, name: String? = nil) { self.id = id; self.name = name ?? id }
}
public enum AIError: LocalizedError {
    case invalidBase, noModel, invalidResponse, http(Int), tooManyPages
    public var errorDescription: String? {
        switch self {
        case .invalidBase: "API Base must be an HTTPS URL without credentials, query parameters or fragments."
        case .noModel: "Choose a model or enter its full ID."
        case .invalidResponse: "The service returned an unsupported response. Check the API type and model capabilities."
        case .http(let status): "AI request failed (HTTP \(status)). Check the API type, address, key and model."
        case .tooManyPages: "The model list is too large. Search the loaded list or enter the model ID manually."
        }
    }
}

/// Native wire adapters; no vendor SDK, proxy server, database or vault access.
public struct AIClient: Sendable {
    public var configuration: AIConfiguration
    private let apiKey: String
    private let session: URLSession
    public init(configuration: AIConfiguration, apiKey: String, session: URLSession? = nil) {
        self.configuration = configuration; self.apiKey = apiKey
        self.session = session ?? URLSession(configuration: .ephemeral, delegate: AIRedirectGuard(), delegateQueue: nil)
    }

    public func endpoint(_ suffix: String) throws -> URL {
        guard var parts = URLComponents(string: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { throw AIError.invalidBase }
        var path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let version = configuration.apiType == .generateContent ? "v1beta" : "v1"
        if path.isEmpty { path = version }
        else if !["v1", "v1beta", "v1alpha"].contains(path.split(separator: "/").last.map(String.init) ?? "") { path += "/" + version }
        parts.path = "/" + path + "/" + suffix
        guard let url = parts.url else { throw AIError.invalidBase }
        return url
    }
    private func request(url: URL, body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch configuration.apiType {
        case .chatCompletions, .responses: request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .generateContent: request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        case .messages:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return request
    }
    private func send(_ request: URLRequest) async throws -> JSONValue {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw AIError.http(response.statusCode) }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
    public func models() async throws -> [AIModel] {
        var result: [AIModel] = []; var cursor: String?; var seen = Set<String>()
        for _ in 0..<100 {
            let root = try endpoint("models")
            var parts = URLComponents(url: root, resolvingAgainstBaseURL: false)!
            if configuration.apiType == .generateContent {
                parts.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
                if let cursor { parts.queryItems?.append(URLQueryItem(name: "pageToken", value: cursor)) }
            } else if configuration.apiType == .messages {
                parts.queryItems = [URLQueryItem(name: "limit", value: "1000")]
                if let cursor { parts.queryItems?.append(URLQueryItem(name: "after_id", value: cursor)) }
            }
            let page = try await send(request(url: parts.url!))
            let entries = page["data"]?.array ?? page["models"]?.array ?? []
            for item in entries {
                guard let raw = item["id"]?.string ?? item["name"]?.string else { continue }
                let id = raw.hasPrefix("models/") ? String(raw.dropFirst(7)) : raw
                if seen.insert(id).inserted { result.append(AIModel(id: id, name: item["display_name"]?.string ?? item["displayName"]?.string)) }
            }
            let next = page["nextPageToken"]?.string ?? ((page["has_more"]?.bool == true) ? page["last_id"]?.string : nil)
            guard let next, !next.isEmpty else { return result.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending } }
            guard next != cursor else { throw AIError.invalidResponse }
            cursor = next
        }
        throw AIError.tooManyPages
    }
    public func response(system: String, messages: [AIMessage]) async throws -> AIResponse {
        let request = try makeRequest(system: system, messages: messages)
        return try parse(await send(request))
    }
    public func makeRequest(system: String, messages: [AIMessage]) throws -> URLRequest {
        guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.noModel }
        let schemas = AgentTools.definitions
        let type = configuration.apiType
        var body: [String: Any] = ["model": configuration.model]
        let suffix: String
        switch type {
        case .chatCompletions:
            suffix = "chat/completions"
            body["messages"] = [["role": "system", "content": system]] + messages.map { message -> [String: Any] in
                if message.role == "tool" { return ["role": "tool", "tool_call_id": message.toolCallID ?? "", "content": message.text] }
                var value: [String: Any] = ["role": message.role, "content": chatContent(message)]
                if !message.calls.isEmpty { value["tool_calls"] = message.calls.map { ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments.json]] as [String: Any] } }
                return value
            }
            body["tools"] = schemas.map { ["type": "function", "function": $0.foundation] as [String: Any] }
        case .responses:
            suffix = "responses"; body["instructions"] = system; body["store"] = false
            body["include"] = ["reasoning.encrypted_content"]
            body["input"] = messages.flatMap { message -> [[String: Any]] in
                if message.role == "assistant", !message.providerItems.isEmpty { return message.providerItems.compactMap { $0.foundation as? [String: Any] } }
                if message.role == "tool" { return [["type": "function_call_output", "call_id": message.toolCallID ?? "", "output": message.text]] }
                var values: [[String: Any]] = []
                if !message.text.isEmpty || !message.images.isEmpty {
                    var content: [[String: Any]] = message.text.isEmpty ? [] : [["type": message.role == "assistant" ? "output_text" : "input_text", "text": message.text]]
                    content += message.images.map { ["type": "input_image", "image_url": "data:\($0.mimeType);base64,\($0.data.base64EncodedString())"] }
                    values.append(["role": message.role, "content": content])
                }
                values += message.calls.map { ["type": "function_call", "call_id": $0.id, "name": $0.name, "arguments": $0.arguments.json] }
                return values
            }
            body["tools"] = schemas.map { schema -> [String: Any] in
                var value = schema.foundation as! [String: Any]; value["type"] = "function"; value["strict"] = false; return value
            }
        case .generateContent:
            let model = configuration.model.hasPrefix("models/") ? String(configuration.model.dropFirst(7)) : configuration.model
            guard !model.contains("/"), !model.contains(":"), !model.contains("?") else { throw AIError.noModel }
            suffix = "models/\(model):generateContent"; body.removeValue(forKey: "model")
            body["system_instruction"] = ["parts": [["text": system]]]
            body["contents"] = messages.map { message -> [String: Any] in
                var parts: [[String: Any]] = message.text.isEmpty ? [] : [["text": message.text]]
                if message.role == "tool" {
                    parts = [["functionResponse": ["name": message.toolName ?? "", "response": ["result": message.text]]]]
                } else {
                    parts += message.images.map { ["inline_data": ["mime_type": $0.mimeType, "data": $0.data.base64EncodedString()]] }
                    parts += message.calls.map { $0.providerPart?.foundation as? [String: Any] ?? ["functionCall": ["name": $0.name, "args": $0.arguments.foundation]] }
                }
                return ["role": message.role == "assistant" ? "model" : "user", "parts": parts]
            }
            body["tools"] = [["functionDeclarations": schemas.map {
                ["name": $0["name"]!.foundation, "description": $0["description"]!.foundation, "parametersJsonSchema": $0["parameters"]!.foundation]
            }]]
        case .messages:
            suffix = "messages"; body["system"] = system; body["max_tokens"] = 4096
            body["messages"] = messages.map { message -> [String: Any] in
                var content: [[String: Any]] = message.text.isEmpty ? [] : [["type": "text", "text": message.text]]
                if message.role == "tool" { content = [["type": "tool_result", "tool_use_id": message.toolCallID ?? "", "content": message.text]] }
                else {
                    content += message.images.map { ["type": "image", "source": ["type": "base64", "media_type": $0.mimeType, "data": $0.data.base64EncodedString()]] }
                    content += message.calls.map { ["type": "tool_use", "id": $0.id, "name": $0.name, "input": $0.arguments.foundation] }
                }
                return ["role": message.role == "assistant" ? "assistant" : "user", "content": content]
            }
            body["tools"] = schemas.map { ["name": $0["name"]!.foundation, "description": $0["description"]!.foundation, "input_schema": $0["parameters"]!.foundation] }
        }
        return try request(url: endpoint(suffix), body: body)
    }
    private func chatContent(_ message: AIMessage) -> Any {
        guard !message.images.isEmpty else { return message.text }
        return [["type": "text", "text": message.text]] + message.images.map { ["type": "image_url", "image_url": ["url": "data:\($0.mimeType);base64,\($0.data.base64EncodedString())"]] as [String: Any] }
    }
    public func parse(_ value: JSONValue) throws -> AIResponse {
        var text: [String] = []; var calls: [AIToolCall] = []
        func addCall(_ id: String?, _ name: String?, _ arguments: JSONValue?) throws {
            guard let name, let arguments else { throw AIError.invalidResponse }
            let args: JSONValue
            if let string = arguments.string {
                guard let data = string.data(using: .utf8) else { throw AIError.invalidResponse }
                args = try JSONDecoder().decode(JSONValue.self, from: data)
            } else { args = arguments }
            calls.append(AIToolCall(id: id ?? UUID().uuidString, name: name, arguments: args))
        }
        switch configuration.apiType {
        case .chatCompletions:
            guard let message = value["choices"]?.array?.first?["message"] else { throw AIError.invalidResponse }
            if let s = message["content"]?.string { text.append(s) }
            for call in message["tool_calls"]?.array ?? [] { try addCall(call["id"]?.string, call["function"]?["name"]?.string, call["function"]?["arguments"]) }
        case .responses:
            guard value["status"]?.string != "incomplete", value["error"] == nil || value["error"] == .null else { throw AIError.invalidResponse }
            for item in value["output"]?.array ?? [] {
                if item["type"]?.string == "function_call" { try addCall(item["call_id"]?.string, item["name"]?.string, item["arguments"]) }
                for content in item["content"]?.array ?? [] where content["type"]?.string == "output_text" { if let s = content["text"]?.string { text.append(s) } }
            }
        case .generateContent:
            for part in value["candidates"]?.array?.first?["content"]?["parts"]?.array ?? [] {
                if let s = part["text"]?.string, part["thought"]?.bool != true { text.append(s) }
                if let call = part["functionCall"] {
                    try addCall(nil, call["name"]?.string, call["args"])
                    calls[calls.count - 1].providerPart = part
                }
            }
        case .messages:
            for item in value["content"]?.array ?? [] {
                if item["type"]?.string == "text", let s = item["text"]?.string { text.append(s) }
                if item["type"]?.string == "tool_use" { try addCall(item["id"]?.string, item["name"]?.string, item["input"]) }
            }
        }
        guard !text.isEmpty || !calls.isEmpty else { throw AIError.invalidResponse }
        return AIResponse(text: text.joined(separator: "\n"), calls: calls, providerItems: configuration.apiType == .responses ? value["output"]?.array ?? [] : [])
    }
}

private final class AIRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // A custom gateway must never redirect a user's key to a different endpoint.
        completionHandler(nil)
    }
}
