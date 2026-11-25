import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CellarKit

/// Replays a scripted sequence of responses and records requested URLs.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    enum Step {
        case respond(HTTPResponse)
        case fail(Error)
    }

    private let lock = NSLock()
    private var steps: [Step]
    private(set) var requests: [URL] = []

    init(_ steps: [Step]) { self.steps = steps }

    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPResponse {
        let step: Step = lock.withLock {
            requests.append(url)
            return steps.isEmpty ? .fail(URLError(.unknown)) : steps.removeFirst()
        }
        switch step {
        case .respond(let response): return response
        case .fail(let error): throw error
        }
    }

    var requestCount: Int { lock.withLock { requests.count } }
}

let sampleCSV = """
"iInventory","iWine","Wine","Location","Pending"
"1","100","Lagavulin 16 Year Old Single Malt Scotch Whisky, 43%","Cellar","0"
"2","100","Lagavulin 16 Year Old Single Malt Scotch Whisky, 43%","Open in Owl's perch","0"
"3","200","Fortaleza Blanco Tequila, 40%","Estancia","0"
"""

func ok(_ body: String, contentType: String = "text/csv; charset=windows-1252") -> FakeTransport.Step {
    .respond(HTTPResponse(statusCode: 200, headers: ["Content-Type": contentType], body: Data(body.utf8)))
}

func status(_ code: Int) -> FakeTransport.Step {
    .respond(HTTPResponse(statusCode: code, body: Data()))
}

let credentials = CellarTrackerCredentials(username: "david", password: "s3cret+&= pass")

func client(_ transport: FakeTransport, attempts: Int = 3) -> CellarTrackerClient {
    CellarTrackerClient(transport: transport, maxAttempts: attempts, retryDelay: { _ in })
}

@Suite struct CellarTrackerClientTests {
    @Test func buildsStrictlyEncodedExportURL() throws {
        let url = CellarTrackerClient.exportURL(credentials: credentials)
        #expect(url.host == "www.cellartracker.com")
        #expect(url.path == "/xlquery.asp")
        let query = try #require(url.query)
        // "+", "&", "=" and spaces must all be escaped so the server sees the real password.
        #expect(query == "User=david&Password=s3cret%2B%26%3D%20pass&Format=csv&Table=List&Location=1")
    }

    @Test func fetchesAndDecodesBottles() async throws {
        let transport = FakeTransport([ok(sampleCSV)])
        let bottles = try await client(transport).fetchBottles(credentials)
        #expect(bottles.count == 3)
        #expect(transport.requestCount == 1)
    }

    @Test func loginPageMeansWrongCredentials() async {
        let page = "<html>You are currently not logged into CellarTracker.</html>"
        let transport = FakeTransport([ok(page, contentType: "text/html")])
        await #expect(throws: CellarTrackerError.notLoggedIn) {
            try await client(transport).fetchBottles(credentials)
        }
        #expect(transport.requestCount == 1) // not retried
    }

    @Test func unauthorizedStatusMeansWrongCredentials() async {
        let transport = FakeTransport([status(401)])
        await #expect(throws: CellarTrackerError.notLoggedIn) {
            try await client(transport).fetchBottles(credentials)
        }
    }

    @Test func retriesServerErrorsThenSucceeds() async throws {
        let transport = FakeTransport([status(503), .fail(URLError(.timedOut)), ok(sampleCSV)])
        let bottles = try await client(transport).fetchBottles(credentials)
        #expect(bottles.count == 3)
        #expect(transport.requestCount == 3)
    }

    @Test func givesUpAfterMaxAttempts() async {
        let transport = FakeTransport([status(500), status(500), status(500), ok(sampleCSV)])
        await #expect(throws: CellarTrackerError.serviceUnavailable) {
            try await client(transport).fetchBottles(credentials)
        }
        #expect(transport.requestCount == 3)
    }

    @Test func doesNotFollowOrRetryRedirects() async {
        let transport = FakeTransport([status(302)])
        await #expect(throws: CellarTrackerError.unexpectedStatus(302)) {
            try await client(transport).fetchBottles(credentials)
        }
        #expect(transport.requestCount == 1)
    }

    @Test func errorMessagesNeverContainThePassword() async {
        let transport = FakeTransport([.fail(URLError(.notConnectedToInternet))])
        do {
            _ = try await client(transport, attempts: 1).fetchBottles(credentials)
            Issue.record("expected an error")
        } catch {
            let text = "\(error) \(error.localizedDescription)"
            #expect(!text.contains("s3cret"))
            #expect(!text.contains("xlquery"))
            #expect(error as? CellarTrackerError == .network("no internet connection"))
        }
    }

    @Test func skipsConsumedBottlesAndReadsQuantity() throws {
        let csv = """
        iWine,Wine,BottleState,Quantity
        1,Kept,1,
        2,Drunk,0,
        3,Three of these,,3
        4,None left,,0
        """
        let bottles = try ExportDecoder.parseBottles(csv)
        #expect(bottles.map(\.name) == ["Kept", "Three of these"])
        let items = MenuBuilder.items(from: bottles)
        #expect(items.first { $0.name == "Three of these" }?.bottleCount == 3)
    }
}

@Suite struct CollectionSyncTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CellarKitTests-\(UUID().uuidString)", isDirectory: true)
    }

    func makeSync(_ transport: FakeTransport, now: Date) -> CollectionSync {
        CollectionSync(
            client: client(transport),
            store: SnapshotStore(fileURL: directory.appendingPathComponent("collection.json")),
            now: { now }
        )
    }

    @Test func snapshotRoundTrips() throws {
        let store = SnapshotStore(fileURL: directory.appendingPathComponent("collection.json"))
        #expect(try store.load() == nil)
        let bottles = try ExportDecoder.parseBottles(sampleCSV)
        let snapshot = CollectionSnapshot(fetchedAt: Date(timeIntervalSince1970: 1_800_000_000), bottles: bottles)
        try store.save(snapshot)
        #expect(try store.load() == snapshot)
        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test func downloadsWhenNoCacheThenUsesFreshCache() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = FakeTransport([ok(sampleCSV)])

        let first = try await makeSync(transport, now: start).sync(credentials: credentials)
        #expect(first.bottles.count == 3)
        #expect(transport.requestCount == 1)

        // 1 hour later: cache is fresh, no download.
        let second = try await makeSync(transport, now: start.addingTimeInterval(3600)).sync(credentials: credentials)
        #expect(second == first)
        #expect(transport.requestCount == 1)
    }

    @Test func refreshesStaleCacheAndForcedSyncs() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = FakeTransport([ok(sampleCSV), ok(sampleCSV), ok(sampleCSV)])
        _ = try await makeSync(transport, now: start).sync(credentials: credentials)

        let dayLater = start.addingTimeInterval(25 * 3600)
        let refreshed = try await makeSync(transport, now: dayLater).sync(credentials: credentials)
        #expect(refreshed.fetchedAt == dayLater)
        #expect(transport.requestCount == 2)

        _ = try await makeSync(transport, now: dayLater).sync(credentials: credentials, force: true)
        #expect(transport.requestCount == 3)
    }

    @Test func failedSyncKeepsTheCache() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = FakeTransport([ok(sampleCSV), status(401)])
        let sync = makeSync(transport, now: start)
        let original = try await sync.sync(credentials: credentials)

        await #expect(throws: CellarTrackerError.notLoggedIn) {
            try await sync.sync(credentials: credentials, force: true)
        }
        #expect(sync.cachedSnapshot() == original)
    }
}
