import Foundation
import Testing
import NookCore
@testable import Nook

struct AIConnectionTests {
    @Test(arguments: AIProtocol.allCases)
    func connectionTestActuallyUsesTheSelectedProtocol(type: AIProtocol) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConnectionProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let config = AIConfiguration(apiType: type, baseURL: "https://nook-test.invalid/v1", model: "chosen-model")
        let response = try await AIClient(configuration: config, apiKey: "test-key", session: session).testConnection()
        #expect(response.text == "OK" && response.calls.isEmpty)
    }
    @Test func connectionFailureIsNotReportedAsSuccess() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ConnectionProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await AIClient(configuration: .init(baseURL: "https://nook-test.invalid/v1", model: "chosen-model"), apiKey: "failure-key", session: session).testConnection()
            Issue.record("An unauthorized request was accepted")
        } catch AIError.http(let status) { #expect(status == 401) }
    }
}
private final class ConnectionProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "nook-test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let status = request.value(forHTTPHeaderField: "Authorization") == "Bearer failure-key" ? 401 : 200
        let raw: String
        if path.hasSuffix("chat/completions") { raw = #"{"choices":[{"message":{"content":"OK"}}]}"# }
        else if path.hasSuffix("responses") { raw = #"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"# }
        else if path.hasSuffix("messages") { raw = #"{"content":[{"type":"text","text":"OK"}]}"# }
        else { raw = #"{"candidates":[{"content":{"parts":[{"text":"OK"}]}}]}"# }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(raw.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
