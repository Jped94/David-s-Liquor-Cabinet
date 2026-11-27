import Foundation
import Testing
@testable import CellarKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Records requests and plays back canned responses.
final class FakeSender: HTTPSender, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [HTTPResponse]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [HTTPResponse]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        try lock.withLock {
            requests.append(request)
            guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
            return responses.removeFirst()
        }
    }
}

func json(_ status: Int, _ body: String, headers: [String: String] = [:]) -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: headers.merging(["Content-Type": "application/json"]) { a, _ in a }, body: Data(body.utf8))
}

@Suite struct ServerTests {
    let base = URL(string: "https://cabinet.example")!

    @Test func buildsTheUploadFromAnExport() throws {
        let bottles = try FixtureTests.loadBottles()
        let upload = SyncUpload(downloaded: bottles, previous: nil, overrides: [:])
        #expect(upload.products.count == 784)
        #expect(upload.bottles.reduce(0) { $0 + $1.quantity } == 1639)
        #expect(upload.syncReport.isInitial)

        // No prices or stores leave the device.
        let text = String(decoding: try JSONEncoder().encode(upload), as: UTF8.self)
        for key in ["\"price\"", "\"value\"", "\"storeName\"", "\"purchaseDate\""] { #expect(!text.contains(key)) }
    }

    @Test func uploadMatchesTheGoldenFile() throws {
        // The web page builds the same upload in TypeScript; both must agree
        // with the golden file.
        let golden = try GoldenTests.makeGolden()
        let byID = Dictionary(uniqueKeysWithValues: golden.products.map { ($0.id, $0) })
        let upload = SyncUpload(downloaded: try FixtureTests.loadBottles(), previous: nil, overrides: [:])
        for product in upload.products {
            let expected = try #require(byID[product.id])
            #expect(product.title == expected.title)
            #expect(product.subtitle == expected.subtitle)
            #expect(product.category.rawValue == expected.category)
            #expect(product.scotchStyle?.rawValue == expected.scotchStyle)
            #expect(product.agaveKind == expected.agaveKind)
            #expect(product.abv == expected.abv)
        }
    }

    @Test func serverMenuRoundTripsToTheSameMenu() throws {
        let bottles = try FixtureTests.loadBottles()
        let upload = SyncUpload(downloaded: bottles, previous: nil, overrides: [:])
        let menu = ServerMenu(version: "v1", syncedAt: "2026-11-27T20:00:00.000Z", products: upload.products, bottles: upload.bottles, overrides: [:])
        let decoded = try JSONDecoder().decode(ServerMenu.self, from: JSONEncoder().encode(menu))
        #expect(decoded == menu)
        #expect(decoded.syncedDate != nil)

        let fromServer = MenuBuilder.items(from: decoded.bottleRecords())
        let direct = MenuBuilder.items(from: bottles)
        #expect(fromServer.map(\.id) == direct.map(\.id))
        #expect(fromServer.map(\.menuTitle) == direct.map(\.menuTitle))
        #expect(fromServer.map(\.category) == direct.map(\.category))
        #expect(fromServer.map(\.bottleCount) == direct.map(\.bottleCount))
    }

    @Test func sessionAndMenuRequests() async throws {
        let sender = FakeSender([
            json(200, #"{"token":"tok","role":"guest"}"#),
            json(304, "", headers: ["ETag": "\"v1\""]),
            json(200, #"{"version":"v2","syncedAt":null,"products":[],"bottles":[],"overrides":{"9":{"title":"X","isHidden":false}}}"#, headers: ["ETag": "\"v2\""]),
        ])
        let client = ServerClient(baseURL: base, sender: sender)

        let session = try await client.createSession(passcode: "key")
        #expect(session.token == "tok" && session.role == .guest)

        guard case .notModified = try await client.menu(token: "tok", etag: "\"v1\"") else {
            Issue.record("expected not modified"); return
        }
        guard case .menu(let menu, let etag) = try await client.menu(token: "tok", etag: "\"v1\"") else {
            Issue.record("expected a menu"); return
        }
        #expect(etag == "\"v2\"")
        #expect(menu.overrides["9"]?.title == "X")

        #expect(sender.requests[0].httpMethod == "POST")
        #expect(sender.requests[0].url?.absoluteString == "https://cabinet.example/api/session")
        #expect(sender.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(sender.requests[1].value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
    }

    @Test func reportsTheServersErrorMessage() async {
        let client = ServerClient(baseURL: base, sender: FakeSender([
            json(401, #"{"error":"That passcode isn't right."}"#),
            json(403, #"{"error":"That needs the admin passcode."}"#),
        ]))
        await #expect(throws: ServerError.unauthorized("That passcode isn't right.")) {
            _ = try await client.createSession(passcode: "nope")
        }
        await #expect(throws: ServerError.forbidden("That needs the admin passcode.")) {
            try await client.saveOverride(token: "t", id: "1", override: ItemOverride(title: "X"))
        }
        await #expect(throws: ServerError.network("no internet connection")) {
            _ = try await client.menu(token: nil, etag: nil)
        }
    }

    @Test func emptyEditsAreDeleted() async throws {
        let sender = FakeSender([json(200, #"{"ok":true}"#), json(200, #"{"ok":true}"#)])
        let client = ServerClient(baseURL: base, sender: sender)
        try await client.saveOverride(token: "t", id: "42", override: ItemOverride())
        try await client.saveOverride(token: "t", id: "42", override: ItemOverride(scotchStyle: .blended))
        #expect(sender.requests.map(\.httpMethod) == ["DELETE", "PUT"])
        let body = try #require(sender.requests[1].httpBody)
        #expect(String(decoding: body, as: UTF8.self).contains("\"scotchStyle\":\"blended\""))
    }

    @Test func baseURLFromHost() {
        #expect(ServerClient.baseURL(host: "owls-perch-lc.josh-090.workers.dev")?.absoluteString == "https://owls-perch-lc.josh-090.workers.dev")
        #expect(ServerClient.baseURL(host: "") == nil)
        #expect(ServerClient.baseURL(host: "https://x") == nil)
    }
}
