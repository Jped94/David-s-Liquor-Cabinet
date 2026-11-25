import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A CellarTracker login.
public struct CellarTrackerCredentials: Sendable, Hashable, Codable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// Failures fetching the collection. Messages never include the password
/// or the request URL (which contains the password).
public enum CellarTrackerError: Error, Equatable, Sendable, LocalizedError {
    /// Wrong username or password.
    case notLoggedIn
    /// CellarTracker returned an error page or a server error.
    case serviceUnavailable
    /// An HTTP status we don't expect (e.g. a redirect or 404).
    case unexpectedStatus(Int)
    /// No connection, timeout, DNS failure and so on.
    case network(String)
    /// The response wasn't a usable export.
    case badExport(ExportError)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            "CellarTracker didn't accept the username or password."
        case .serviceUnavailable:
            "CellarTracker isn't responding properly right now. Try again later."
        case .unexpectedStatus(let code):
            "CellarTracker returned an unexpected response (HTTP \(code))."
        case .network(let reason):
            "Couldn't reach CellarTracker: \(reason)"
        case .badExport(let error):
            "CellarTracker's export couldn't be read (\(error))."
        }
    }
}

/// Downloads the collection from CellarTracker's self-serve export
/// (`xlquery.asp`). CellarTracker has no official API; this is the same
/// endpoint the "export to CSV" feature uses.
public struct CellarTrackerClient: Sendable {
    public static let endpoint = URL(string: "https://www.cellartracker.com/xlquery.asp")!

    public var transport: any HTTPTransport
    /// Total attempts per fetch (first try + retries).
    public var maxAttempts: Int
    public var timeout: TimeInterval
    /// Delay before retry `n` (1-based). Injectable so tests don't wait.
    public var retryDelay: @Sendable (Int) async throws -> Void

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        maxAttempts: Int = 3,
        timeout: TimeInterval = 50,
        retryDelay: @escaping @Sendable (Int) async throws -> Void = CellarTrackerClient.defaultRetryDelay
    ) {
        self.transport = transport
        self.maxAttempts = max(1, maxAttempts)
        self.timeout = timeout
        self.retryDelay = retryDelay
    }

    /// Roughly 1 s, then 3 s, with a little jitter.
    public static let defaultRetryDelay: @Sendable (Int) async throws -> Void = { attempt in
        let base = attempt == 1 ? 1.0 : 3.0
        let seconds = base + Double.random(in: 0...0.5)
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Fetches every bottle currently in the cellar.
    public func fetchBottles(_ credentials: CellarTrackerCredentials) async throws -> [BottleRecord] {
        let url = Self.exportURL(credentials: credentials)
        var attempt = 1
        while true {
            do {
                return try await fetchOnce(url)
            } catch let error as CellarTrackerError where Self.isRetryable(error) && attempt < maxAttempts {
                try await retryDelay(attempt)
                attempt += 1
            }
        }
    }

    private func fetchOnce(_ url: URL) async throws -> [BottleRecord] {
        let response: HTTPResponse
        do {
            response = try await transport.get(url, timeout: timeout)
        } catch let error as URLError {
            throw CellarTrackerError.network(Self.describe(error))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CellarTrackerError.network("connection failed")
        }

        switch response.statusCode {
        case 200: break
        case 401, 403: throw CellarTrackerError.notLoggedIn
        case 500...599: throw CellarTrackerError.serviceUnavailable
        default: throw CellarTrackerError.unexpectedStatus(response.statusCode)
        }

        do {
            return try ExportDecoder.decodeBottles(response.body, contentType: response.contentType)
        } catch ExportError.notLoggedIn {
            throw CellarTrackerError.notLoggedIn
        } catch ExportError.unexpectedHTML {
            throw CellarTrackerError.serviceUnavailable
        } catch let error as ExportError {
            throw CellarTrackerError.badExport(error)
        }
    }

    static func isRetryable(_ error: CellarTrackerError) -> Bool {
        switch error {
        case .network, .serviceUnavailable: true
        case .notLoggedIn, .unexpectedStatus, .badExport: false
        }
    }

    /// A short reason for a transport error, without the URL.
    static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost: "no internet connection"
        case .timedOut: "the request timed out"
        case .cannotFindHost, .dnsLookupFailed: "couldn't find the server"
        case .cannotConnectToHost: "couldn't connect to the server"
        case .secureConnectionFailed, .serverCertificateUntrusted: "secure connection failed"
        default: "network error \(error.code.rawValue)"
        }
    }

    /// The export URL for the per-bottle inventory list.
    ///
    /// Every value is percent-encoded strictly (only `A–Z a–z 0–9 - . _ ~`
    /// pass through). `URLComponents` would leave `+` and `&`-safe characters
    /// alone, and CellarTracker's ASP backend decodes a literal `+` as a
    /// space, which would break passwords containing `+`.
    public static func exportURL(credentials: CellarTrackerCredentials, table: String = "List") -> URL {
        var items: [(String, String)] = [
            ("User", credentials.username),
            ("Password", credentials.password),
            ("Format", "csv"),
            ("Table", table),
        ]
        if table == "List" { items.append(("Location", "1")) }

        let query = items
            .map { "\(strictEncode($0.0))=\(strictEncode($0.1))" }
            .joined(separator: "&")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = query
        return components.url!
    }

    static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func strictEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
