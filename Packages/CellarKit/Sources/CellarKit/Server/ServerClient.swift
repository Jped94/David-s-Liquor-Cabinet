import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Failures talking to the shared server. Messages are safe to show.
public enum ServerError: Error, Equatable, Sendable, LocalizedError {
    /// No valid session: the passcode or key is wrong or has expired (401).
    case unauthorized(String)
    /// The session isn't allowed to do this (403), e.g. not admin.
    case forbidden(String)
    /// Any other error the server reported, with its message.
    case server(status: Int, message: String)
    /// No connection, timeout, DNS failure and so on.
    case network(String)
    /// The response couldn't be read.
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .unauthorized(let message), .forbidden(let message): message
        case .server(_, let message): message
        case .network(let reason): "Couldn't reach the cabinet server: \(reason)"
        case .badResponse: "The cabinet server sent a response the app couldn't read."
        }
    }
}

/// Talks to the shared Cloudflare server (see `server/`).
public struct ServerClient: Sendable {
    public enum Role: String, Codable, Sendable { case guest, admin }

    public var baseURL: URL
    public var sender: any HTTPSender

    public init(baseURL: URL, sender: any HTTPSender = URLSessionTransport()) {
        self.baseURL = baseURL
        self.sender = sender
    }

    /// `https://<host>` from a bare host name, as stored in the build settings.
    public static func baseURL(host: String) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { return nil }
        return URL(string: "https://\(trimmed)")
    }

    // MARK: Endpoints

    /// Exchanges a passcode (or the app's built-in key) for a session token.
    public func createSession(passcode: String) async throws -> (token: String, role: Role) {
        struct Body: Encodable { var passcode: String }
        struct Reply: Decodable { var token: String; var role: Role }
        let response = try await send("POST", "/api/session", body: Body(passcode: passcode))
        let reply = try decode(Reply.self, from: response)
        return (reply.token, reply.role)
    }

    public enum MenuResult: Sendable {
        case notModified
        case menu(ServerMenu, etag: String?)
    }

    /// The menu, or `.notModified` if it still matches `etag`.
    public func menu(token: String?, etag: String?) async throws -> MenuResult {
        var headers: [String: String] = [:]
        if let etag { headers["If-None-Match"] = etag }
        let response = try await send("GET", "/api/menu", token: token, headers: headers, accept: [200, 304])
        if response.statusCode == 304 { return .notModified }
        return .menu(try decode(ServerMenu.self, from: response), etag: response.headers["etag"])
    }

    /// Has the server fetch the CellarTracker export with this login and
    /// return it unchanged. The login is used once and not stored there.
    public func downloadExport(token: String, credentials: CellarTrackerCredentials) async throws -> HTTPResponse {
        try await send("POST", "/api/sync/download", token: token, body: credentials, timeout: 180)
    }

    /// Uploads the menu built from a download.
    public func commit(token: String, upload: SyncUpload) async throws {
        _ = try await send("POST", "/api/sync/commit", token: token, body: upload, timeout: 120)
    }

    /// Saves an owner's edit, or removes it when `override` is `nil` or empty.
    public func saveOverride(token: String, id: String, override: ItemOverride?) async throws {
        let path = "/api/items/\(id)/override"
        if let override, !override.isEmpty {
            _ = try await send("PUT", path, token: token, body: override)
        } else {
            _ = try await send("DELETE", path, token: token)
        }
    }

    // MARK: Plumbing

    private struct Empty: Encodable {}

    private func send(
        _ method: String,
        _ path: String,
        token: String? = nil,
        headers: [String: String] = [:],
        accept: Set<Int> = [200],
        timeout: TimeInterval = 30
    ) async throws -> HTTPResponse {
        try await send(method, path, token: token, headers: headers, body: Optional<Empty>.none, accept: accept, timeout: timeout)
    }

    private func send<Body: Encodable>(
        _ method: String,
        _ path: String,
        token: String? = nil,
        headers: [String: String] = [:],
        body: Body?,
        accept: Set<Int> = [200],
        timeout: TimeInterval = 30
    ) async throws -> HTTPResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let response: HTTPResponse
        do {
            response = try await sender.send(request)
        } catch let error as URLError {
            throw ServerError.network(CellarTrackerClient.describe(error))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ServerError.network("connection failed")
        }

        if accept.contains(response.statusCode) { return response }
        let message = (try? JSONDecoder().decode([String: String].self, from: response.body))?["error"]
            ?? "The cabinet server returned an error (HTTP \(response.statusCode))."
        switch response.statusCode {
        case 401: throw ServerError.unauthorized(message)
        case 403: throw ServerError.forbidden(message)
        default: throw ServerError.server(status: response.statusCode, message: message)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw ServerError.badResponse
        }
    }
}

/// The last menu downloaded from the server, kept on disk so the app opens
/// instantly and works offline.
public struct MenuCache: Codable, Sendable, Equatable {
    public var menu: ServerMenu
    public var etag: String?

    public init(menu: ServerMenu, etag: String?) {
        self.menu = menu
        self.etag = etag
    }

    public static func defaultURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("menu.json")
    }

    public static func load(from url: URL) -> MenuCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MenuCache.self, from: data)
    }

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
