import CellarKit
import Foundation
import Observation

/// App-wide collection state.
///
/// On launch it shows the cached CellarTracker snapshot if there is one,
/// otherwise the bundled sample data. With a saved login it syncs when the
/// cache is more than a day old, and on demand.
@Observable
@MainActor
final class CollectionModel {
    enum Source { case sample, cellarTracker }

    private(set) var bottles: [BottleRecord] = []
    private(set) var items: [MenuItem] = []
    private(set) var source: Source = .sample
    private(set) var lastSynced: Date?
    private(set) var isSyncing = false
    private(set) var syncError: String?
    private(set) var hasCredentials = false

    var mapping = HouseMapping.default { didSet { rebuild() } }
    var house: HouseFilter = .house(.bedford) { didSet { rebuild() } }

    private let sync: CollectionSync?

    init() {
        sync = (try? SnapshotStore.defaultStore()).map { CollectionSync(store: $0) }
        hasCredentials = CredentialStore.load() != nil
        if hasCredentials, let snapshot = sync?.cachedSnapshot() {
            apply(snapshot)
        } else {
            loadSample()
        }
    }

    // MARK: Derived data

    var isSampleData: Bool { source == .sample }
    var openedItems: [MenuItem] { items.filter(\.isOpened) }
    var totalBottles: Int { bottles.reduce(0) { $0 + $1.quantity } }
    var unmappedLocations: [String] { mapping.unmappedLocations(in: bottles.filter { !$0.isPending }) }

    var categoryCounts: [(category: SpiritCategory, count: Int)] {
        MenuBuilder.categoryCounts(items)
    }

    /// Open bottles for the cover, best community score first.
    func featuredPours(_ count: Int) -> [MenuItem] {
        let sorted = openedItems.sorted { a, b in
            let scoreA = a.communityScore ?? 0
            let scoreB = b.communityScore ?? 0
            if scoreA != scoreB { return scoreA > scoreB }
            return a.menuTitle.localizedStandardCompare(b.menuTitle) == .orderedAscending
        }
        return Array(sorted.prefix(count))
    }

    /// Every open bottle, grouped by spirit, for the "Tonight's Pours" page.
    var openSections: [MenuSection] {
        SpiritCategory.allCases.compactMap { category in
            let items = openedItems
                .filter { $0.category == category }
                .sorted { $0.menuTitle.localizedStandardCompare($1.menuTitle) == .orderedAscending }
            guard !items.isEmpty else { return nil }
            return MenuSection(title: category == .scotch ? "Scotch Whisky" : category.displayName, items: items)
        }
    }

    func items(in category: SpiritCategory) -> [MenuItem] {
        items.filter { $0.category == category }
    }

    func search(_ query: String) -> [MenuItem] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            [item.name, item.producer, item.originLine, item.rules.style]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    // MARK: Sync

    /// Downloads only if the cache is missing or more than a day old.
    func syncIfNeeded() async {
        await runSync(force: false)
    }

    /// Always downloads.
    func syncNow() async {
        await runSync(force: true)
    }

    /// Checks the login by downloading the collection, and saves it to the
    /// Keychain only if that works. Returns whether it worked.
    func signIn(_ credentials: CellarTrackerCredentials) async -> Bool {
        guard let sync, !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let snapshot = try await sync.sync(credentials: credentials, force: true)
            try CredentialStore.save(credentials)
            hasCredentials = true
            syncError = nil
            apply(snapshot)
            return true
        } catch {
            syncError = Self.message(for: error)
            return false
        }
    }

    /// Forgets the login and the cached collection, and goes back to sample data.
    func signOut() {
        CredentialStore.delete()
        try? sync?.store.delete()
        hasCredentials = false
        syncError = nil
        lastSynced = nil
        loadSample()
    }

    private func runSync(force: Bool) async {
        guard let sync, !isSyncing, let credentials = CredentialStore.load() else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            apply(try await sync.sync(credentials: credentials, force: force))
            syncError = nil
        } catch {
            syncError = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: Loading

    private func apply(_ snapshot: CollectionSnapshot) {
        bottles = snapshot.bottles
        lastSynced = snapshot.fetchedAt
        source = .cellarTracker
        rebuild()
    }

    private func loadSample() {
        source = .sample
        guard let url = Bundle.main.url(forResource: "sample_export", withExtension: "csv"),
              let data = try? Data(contentsOf: url),
              let sample = try? ExportDecoder.decodeBottles(data)
        else {
            bottles = []
            syncError = "The bundled sample data couldn't be loaded."
            rebuild()
            return
        }
        bottles = sample
        rebuild()
    }

    private func rebuild() {
        items = MenuBuilder.items(from: bottles, filter: house, mapping: mapping)
    }
}
