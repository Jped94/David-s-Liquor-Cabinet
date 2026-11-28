import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A minimal HTTP response.
public struct HTTPResponse: Sendable {
    public var statusCode: Int
    /// Header names are lowercased.
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data) {
        self.statusCode = statusCode
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        self.body = body
    }

    public var contentType: String? { headers["content-type"] }
}

/// Sends HTTP requests to the cabinet server. Abstracted so tests can
/// substitute a fake.
public protocol HTTPSender: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// `URLSession`-backed sender that never follows redirects, so requests
/// carrying a session token or a CellarTracker login only ever go to the
/// host we chose.
public final class URLSessionTransport: NSObject, HTTPSender, URLSessionTaskDelegate, @unchecked Sendable {
    // `URLSession` is thread-safe; the delegate keeps no mutable state.
    private var session: URLSession!

    public override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
