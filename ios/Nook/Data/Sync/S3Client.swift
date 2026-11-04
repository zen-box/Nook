import Foundation
import CryptoKit
import NookCore

struct S3Configuration: Hashable, Codable, Sendable {
    var endpoint = ""
    var bucket = ""
    var region = "us-east-1"
    var prefix = "nook"
    var pathStyle = true
}
struct S3Credentials: Codable, Sendable {
    var accessKey: String
    var secretKey: String
    var sessionToken: String = ""
}
enum S3Error: LocalizedError {
    case configuration, http(Int), invalidList, tooLarge
    var errorDescription: String? {
        switch self {
        case .configuration: String(localized: "Check the HTTPS S3 endpoint, bucket, region and credentials.")
        case .http(let status): String(localized: "S3 request failed (HTTP \(status)). Check endpoint, region and bucket permissions.")
        case .invalidList: String(localized: "The S3 endpoint returned an invalid or incomplete object list.")
        case .tooLarge: String(localized: "The remote object exceeds this version's safe import size.")
        }
    }
}

struct S3Client: Sendable {
    let configuration: S3Configuration
    let credentials: S3Credentials
    private let session: URLSession
    init(configuration: S3Configuration, credentials: S3Credentials, session: URLSession? = nil) {
        self.configuration = configuration; self.credentials = credentials
        self.session = session ?? URLSession(configuration: .ephemeral, delegate: S3RedirectGuard(), delegateQueue: nil)
    }

    func signedRequest(method: String, key: String = "", query: [String: String] = [:], data: Data = Data(),
                       createOnly: Bool = false, now: Date = Date()) throws -> URLRequest {
        let c = configuration
        guard var url = URLComponents(string: c.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https",
              let host = url.host, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              !c.bucket.isEmpty, !c.bucket.contains("/"), !c.region.isEmpty,
              !credentials.accessKey.isEmpty, !credentials.secretKey.isEmpty else { throw S3Error.configuration }
        let bucketPath = c.pathStyle ? "/" + c.bucket : ""
        if !c.pathStyle { url.host = c.bucket + "." + host }
        let base = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let rawPath = (base.isEmpty ? "" : "/" + base) + bucketPath + (key.isEmpty ? "" : "/" + key)
        let canonicalPath = rawPath.isEmpty ? "/" : rawPath.split(separator: "/", omittingEmptySubsequences: false).map(Self.escape).joined(separator: "/")
        url.percentEncodedPath = canonicalPath
        let canonicalQuery = query.map { (Self.escape($0.key), Self.escape($0.value)) }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }
            .map { $0 + "=" + $1 }.joined(separator: "&")
        url.percentEncodedQuery = canonicalQuery.isEmpty ? nil : canonicalQuery
        guard let endpoint = url.url else { throw S3Error.configuration }
        let timestamp = Self.timestamp(now), date = String(timestamp.prefix(8))
        let digest = Self.hex(SHA256.hash(data: data))
        var headers: [String: String] = ["host": endpoint.host! + (endpoint.port.map { ":\($0)" } ?? ""),
                                       "x-amz-content-sha256": digest, "x-amz-date": timestamp]
        if !credentials.sessionToken.isEmpty { headers["x-amz-security-token"] = credentials.sessionToken }
        if createOnly { headers["if-none-match"] = "*" }
        let names = headers.keys.sorted()
        let canonicalHeaders = names.map { "\($0):\(headers[$0]!.trimmingCharacters(in: .whitespacesAndNewlines))\n" }.joined()
        let signed = names.joined(separator: ";")
        let canonical = [method, canonicalPath, canonicalQuery, canonicalHeaders, signed, digest].joined(separator: "\n")
        let scope = "\(date)/\(c.region)/s3/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(timestamp)\n\(scope)\n\(Self.hex(SHA256.hash(data: Data(canonical.utf8))))"
        func hmac(_ key: Data, _ value: String) -> Data { Data(HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: key))) }
        let kDate = hmac(Data(("AWS4" + credentials.secretKey).utf8), date)
        let kRegion = hmac(kDate, c.region), kService = hmac(kRegion, "s3"), kSigning = hmac(kService, "aws4_request")
        let signature = Self.hex(hmac(kSigning, stringToSign))
        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = method
        if method == "PUT" { request.httpBody = data }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue("AWS4-HMAC-SHA256 Credential=\(credentials.accessKey)/\(scope), SignedHeaders=\(signed), Signature=\(signature)", forHTTPHeaderField: "Authorization")
        if method == "PUT" { request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type") }
        return request
    }
    func get(_ key: String) async throws -> Data? {
        let (data, response) = try await session.data(for: signedRequest(method: "GET", key: key))
        guard let response = response as? HTTPURLResponse else { throw S3Error.invalidList }
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else { throw S3Error.http(response.statusCode) }
        guard data.count <= 100 * 1024 * 1024 else { throw S3Error.tooLarge }
        return data
    }
    func put(_ data: Data, key: String, createOnly: Bool = false) async throws {
        let (_, response) = try await session.data(for: signedRequest(method: "PUT", key: key, data: data, createOnly: createOnly))
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw S3Error.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
    func list(prefix: String) async throws -> [String] {
        var keys: [String] = [], token: String?, seen = Set<String>()
        repeat {
            var query = ["list-type": "2", "prefix": prefix, "max-keys": "1000", "encoding-type": "url"]
            if let token { query["continuation-token"] = token }
            let (data, response) = try await session.data(for: signedRequest(method: "GET", query: query))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw S3Error.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
            let reader = S3ListReader(); let parser = XMLParser(data: data); parser.delegate = reader
            guard parser.parse(), reader.isList, !reader.truncated || reader.nextToken != nil else { throw S3Error.invalidList }
            keys += reader.keys.map { $0.removingPercentEncoding ?? $0 }
            token = reader.truncated ? reader.nextToken : nil
            if let token, !seen.insert(token).inserted { throw S3Error.invalidList }
            guard keys.count <= 100_000 else { throw S3Error.invalidList }
        } while token != nil
        return keys.sorted()
    }
    func path(_ suffix: String) -> String {
        let prefix = configuration.prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return prefix.isEmpty ? suffix : prefix + "/" + suffix
    }
    static func escape<S: StringProtocol>(_ text: S) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))!
    }
    static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 { bytes.map { String(format: "%02x", $0) }.joined() }
    static func timestamp(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"; return f.string(from: date)
    }
}

private final class S3ListReader: NSObject, XMLParserDelegate {
    var keys: [String] = [], nextToken: String?, truncated = false, isList = false
    private var text = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""; if elementName == "ListBucketResult" { isList = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "Key": keys.append(text)
        case "NextContinuationToken": nextToken = text
        case "IsTruncated": truncated = text == "true"
        default: break
        }
    }
}
private final class S3RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
