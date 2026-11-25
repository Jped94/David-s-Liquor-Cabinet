import Foundation

/// A downloaded copy of the collection.
public struct CollectionSnapshot: Codable, Sendable, Equatable {
    public var fetchedAt: Date
    public var bottles: [BottleRecord]

    public init(fetchedAt: Date, bottles: [BottleRecord]) {
        self.fetchedAt = fetchedAt
        self.bottles = bottles
    }
}

/// Keeps the last good snapshot on disk so the menu opens instantly and
/// works offline.
public struct SnapshotStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `Application Support/collection.json` in the app's container.
    public static func defaultStore() throws -> SnapshotStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return SnapshotStore(fileURL: directory.appendingPathComponent("collection.json"))
    }

    /// The saved snapshot, or `nil` if none has been saved yet.
    public func load() throws -> CollectionSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode(CollectionSnapshot.self, from: data)
    }

    public func save(_ snapshot: CollectionSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(snapshot)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }

    public func delete() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Decides when to download and keeps the cache up to date.
public struct CollectionSync: Sendable {
    public var client: CellarTrackerClient
    public var store: SnapshotStore
    /// How old the cache may get before `sync(force: false)` downloads again.
    public var maxAge: TimeInterval
    public var now: @Sendable () -> Date

    public init(
        client: CellarTrackerClient = CellarTrackerClient(),
        store: SnapshotStore,
        maxAge: TimeInterval = 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.store = store
        self.maxAge = maxAge
        self.now = now
    }

    /// The cached snapshot, ignoring a missing or unreadable cache.
    public func cachedSnapshot() -> CollectionSnapshot? {
        try? store.load()
    }

    public func isStale(_ snapshot: CollectionSnapshot?) -> Bool {
        guard let snapshot else { return true }
        return now().timeIntervalSince(snapshot.fetchedAt) > maxAge
    }

    /// Returns a fresh snapshot.
    ///
    /// Without `force`, a cache younger than `maxAge` is returned without
    /// downloading. A successful download replaces the cache. On failure this
    /// throws and the cache is left untouched, so callers can keep showing it.
    public func sync(credentials: CellarTrackerCredentials, force: Bool = false) async throws -> CollectionSnapshot {
        if !force, let cached = cachedSnapshot(), !isStale(cached) {
            return cached
        }
        let bottles = try await client.fetchBottles(credentials)
        let snapshot = CollectionSnapshot(fetchedAt: now(), bottles: bottles)
        try store.save(snapshot)
        return snapshot
    }
}
