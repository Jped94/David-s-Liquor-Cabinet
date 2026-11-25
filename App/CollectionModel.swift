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

    /// Admin mode: shows hidden items and the Edit button. Turned on in
    /// Settings; resets when the app is relaunched.
    var isAdmin = false { didSet { rebuild() } }

    /// What the last sync changed, waiting to be shown. Cleared when dismissed.
    var syncReport: SyncReport?
    /// Set while the Settings sheet is open, so the report shows there
    /// instead of underneath it.
    var isSettingsOpen = false

    /// The owner's edits, keyed by iWine.
    private(set) var overrides: [String: ItemOverride] = [:]
    /// Locations left off the menu (normalized names), remembered on this iPad.
    private(set) var hiddenLocations: Set<String> = []

    private let sync: CollectionSync?
    private let overrideStore: OverrideStore?
    private static let hiddenLocationsKey = "hiddenLocations"

    init() {
        sync = (try? SnapshotStore.defaultStore()).map { CollectionSync(store: $0) }
        overrideStore = try? OverrideStore.defaultStore()
        overrides = (try? overrideStore?.load()) ?? [:]
        hiddenLocations = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenLocationsKey) ?? [])
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
            [item.name, item.menuTitle, item.producer, item.originLine, item.style]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    // MARK: Locations

    /// The locations of a house that have bottles, most bottles first.
    func locations(for house: House) -> [String] {
        mapping.locations(for: house, in: bottles)
    }

    func isLocationShown(_ location: String) -> Bool {
        !hiddenLocations.contains(HouseMapping.normalize(location))
    }

    func setLocation(_ location: String, shown: Bool) {
        let key = HouseMapping.normalize(location)
        if shown { hiddenLocations.remove(key) } else { hiddenLocations.insert(key) }
        UserDefaults.standard.set(Array(hiddenLocations).sorted(), forKey: Self.hiddenLocationsKey)
        rebuild()
    }

    // MARK: Edits

    /// The current version of an item (e.g. after an edit or a sync).
    func item(id: MenuItem.ID) -> MenuItem? {
        items.first { $0.id == id }
    }

    /// Saves the owner's edit for an item. `nil` or an empty edit removes it.
    func saveOverride(_ override: ItemOverride?, for id: MenuItem.ID) throws {
        var updated = overrides
        if let override, !override.isEmpty {
            updated[id] = override
        } else {
            updated[id] = nil
        }
        try overrideStore?.save(updated)
        overrides = updated
        rebuild()
    }

    // MARK: Sync

    /// Downloads only if the cache is missing or more than a day old.
    func syncIfNeeded() async {
        await runSync(force: false, userInitiated: false)
    }

    /// Always downloads.
    func syncNow() async {
        await runSync(force: true, userInitiated: true)
    }

    /// Checks the login by downloading the collection, and saves it to the
    /// Keychain only if that works. Returns whether it worked.
    func signIn(_ credentials: CellarTrackerCredentials) async -> Bool {
        guard let sync, !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let previous = previousDownload
            let snapshot = try await sync.sync(credentials: credentials, force: true)
            try CredentialStore.save(credentials)
            hasCredentials = true
            syncError = nil
            syncReport = SyncReport.compare(old: previous, new: snapshot.bottles, overrides: overrides)
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

    /// The bottles from the last CellarTracker download (not sample data).
    private var previousDownload: [BottleRecord]? {
        source == .cellarTracker ? bottles : nil
    }

    private func runSync(force: Bool, userInitiated: Bool) async {
        guard let sync, !isSyncing, let credentials = CredentialStore.load() else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let previous = previousDownload
            let previousDate = lastSynced
            let snapshot = try await sync.sync(credentials: credentials, force: force)
            syncError = nil
            // A fresh cache is returned without downloading: nothing to report.
            if snapshot.fetchedAt != previousDate {
                let report = SyncReport.compare(old: previous, new: snapshot.bottles, overrides: overrides)
                if report.hasChanges || report.isInitial || userInitiated {
                    syncReport = report
                }
            }
            apply(snapshot)
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
        items = MenuBuilder.items(
            from: bottles,
            filter: house,
            mapping: mapping,
            hiddenLocations: hiddenLocations,
            overrides: overrides,
            includeHidden: isAdmin
        )
    }
}
