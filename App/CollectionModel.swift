import CellarKit
import Foundation
import Observation

/// App-wide collection state.
///
/// The menu comes from the shared cabinet server, so every iPad and the web
/// page show the same collection and edits. The last menu is cached on the
/// iPad, so the app opens instantly and works offline. Before the first
/// download it shows the bundled sample data.
///
/// Admin mode is unlocked with the admin passcode and lasts until the app
/// is closed or locked again. It allows syncing from CellarTracker, editing
/// bottles and seeing hidden ones.
@Observable
@MainActor
final class CollectionModel {
    enum Source { case sample, server }

    private(set) var bottles: [BottleRecord] = [] {
        // Parse names once per download, so house and location changes are instant.
        didSet { catalog = ItemBasics.catalog(for: bottles) }
    }
    @ObservationIgnored private var catalog: [String: ItemBasics] = [:]
    private(set) var items: [MenuItem] = []
    private(set) var source: Source = .sample
    /// When the collection was last synced from CellarTracker (by any device).
    private(set) var lastSynced: Date?
    private(set) var isRefreshing = false
    private(set) var isSyncing = false
    /// The last refresh or sync problem, shown on the cover and in Settings.
    private(set) var syncError: String?
    /// Whether a CellarTracker login is saved on this iPad.
    private(set) var hasCredentials = false

    var mapping = HouseMapping.default { didSet { rebuild() } }
    /// Which house this iPad shows. Remembered across launches.
    var house: HouseFilter = .house(.bedford) {
        didSet {
            UserDefaults.standard.set(Self.storageValue(for: house), forKey: Self.houseKey)
            rebuild()
        }
    }
    private static let houseKey = "house"
    /// Saved as the house name, or "*" for both houses.
    private static func storageValue(for filter: HouseFilter) -> String {
        switch filter {
        case .all: "*"
        case .house(let house): house.name
        }
    }

    /// The admin session, kept in memory only: closing the app locks it.
    private var adminToken: String? { didSet { rebuild() } }
    var isAdmin: Bool { adminToken != nil }

    /// What the last sync changed, waiting to be shown. Cleared when dismissed.
    var syncReport: SyncReport?
    /// Set while the Settings sheet is open, so the report shows there
    /// instead of underneath it.
    var isSettingsOpen = false

    /// The owner's edits, keyed by iWine (from the server).
    private(set) var overrides: [String: ItemOverride] = [:]
    /// Locations left off the menu (normalized names), remembered on this iPad.
    private(set) var hiddenLocations: Set<String> = []
    /// Edits made on this iPad before the shared server existed, waiting to
    /// be uploaded.
    private(set) var localEdits: [String: ItemOverride] = [:]

    private let client: ServerClient?
    private var cache: MenuCache?
    private let cacheURL = try? MenuCache.defaultURL()
    private let legacyEditStore = try? OverrideStore.defaultStore()
    private static let hiddenLocationsKey = "hiddenLocations"

    init() {
        client = AppConfig.serverURL.map { ServerClient(baseURL: $0) }
        hiddenLocations = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenLocationsKey) ?? [])
        if let saved = UserDefaults.standard.string(forKey: Self.houseKey) {
            house = saved == "*" ? .all : .house(House(saved))
        }
        hasCredentials = CredentialStore.load() != nil
        localEdits = (try? legacyEditStore?.load()) ?? [:]
        // The one-off cleanup of the pre-server cache.
        try? SnapshotStore.defaultStore().delete()

        if let url = cacheURL, let cached = MenuCache.load(from: url), !cached.menu.products.isEmpty {
            cache = cached
            apply(cached.menu)
        } else {
            loadSample()
        }
    }

    // MARK: Derived data

    var isSampleData: Bool { source == .sample }
    var isServerConfigured: Bool { client != nil && AppConfig.appKey != nil }
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
        SpiritCategory.menuCategories.compactMap { category in
            let items = openedItems
                .filter { $0.category.menuCategory == category }
                .sorted { $0.menuTitle.localizedStandardCompare($1.menuTitle) == .orderedAscending }
            guard !items.isEmpty else { return nil }
            return MenuSection(title: category == .scotch ? "Scotch Whisky" : category.displayName, items: items)
        }
    }

    /// The items on a cover entry's page (American Whiskey includes bourbon
    /// and rye), optionally only one style of Scotch.
    func items(in category: SpiritCategory, style: ScotchStyle? = nil) -> [MenuItem] {
        items.filter { item in
            item.category.menuCategory == category && (style == nil || item.scotchStyle == style)
        }
    }

    /// The Scotch styles in the collection, for the Scotch page's filter.
    var scotchStyles: [ScotchStyle] {
        let present = Set(items.compactMap(\.scotchStyle))
        return ScotchStyle.allCases.filter(present.contains)
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

    // MARK: Reading the menu

    /// Fetches the menu if it changed. Cheap when it hasn't (the server
    /// answers "not modified"), so it runs on launch and whenever the app
    /// comes to the front.
    func refresh() async {
        guard let client, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result: ServerClient.MenuResult
            do {
                result = try await client.menu(token: try await readToken(), etag: cache?.etag)
            } catch ServerError.unauthorized(_) where adminToken == nil {
                // The saved guest session expired or the key changed: start again.
                GuestSessionStore.delete()
                result = try await client.menu(token: try await readToken(), etag: cache?.etag)
            }
            if case .menu(let menu, let etag) = result {
                let updated = MenuCache(menu: menu, etag: etag)
                cache = updated
                if let cacheURL { try? updated.save(to: cacheURL) }
                apply(menu)
            }
            if !isSyncing { syncError = nil }
        } catch ServerError.unauthorized(let message) where adminToken != nil {
            adminToken = nil
            syncError = message
        } catch {
            syncError = Self.message(for: error)
        }
    }

    /// The admin session if unlocked, otherwise the guest session (created
    /// with the app's built-in key the first time).
    private func readToken() async throws -> String? {
        if let adminToken { return adminToken }
        if let saved = GuestSessionStore.load() { return saved }
        guard let client, let key = AppConfig.appKey else { return nil }
        let session = try await client.createSession(passcode: key)
        GuestSessionStore.save(session.token)
        return session.token
    }

    // MARK: Admin

    /// Unlocks admin mode with the admin passcode. Returns an error message,
    /// or `nil` on success.
    func unlockAdmin(passcode: String) async -> String? {
        guard let client else { return "This build isn't connected to the cabinet server." }
        do {
            let session = try await client.createSession(passcode: passcode)
            guard session.role == .admin else { return "That's not the admin passcode." }
            adminToken = session.token
            await refresh()
            return nil
        } catch {
            return Self.message(for: error)
        }
    }

    func lockAdmin() {
        adminToken = nil
    }

    // MARK: Edits

    /// The current version of an item (e.g. after an edit or a sync).
    func item(id: MenuItem.ID) -> MenuItem? {
        items.first { $0.id == id }
    }

    /// Saves the owner's edit to the server. `nil` or an empty edit removes it.
    func saveOverride(_ override: ItemOverride?, for id: MenuItem.ID) async throws {
        guard let client, let adminToken else { throw ServerError.forbidden("Unlock admin mode to edit.") }
        let edit = override.flatMap { $0.isEmpty ? nil : $0 }
        try await client.saveOverride(token: adminToken, id: id, override: edit)
        overrides[id] = edit
        rebuild()
        await refresh()
    }

    /// Uploads edits saved on this iPad before the shared server, then
    /// removes the local copy. Returns how many were uploaded.
    func uploadLocalEdits() async throws -> Int {
        guard let client, let adminToken else { throw ServerError.forbidden("Unlock admin mode first.") }
        let count = localEdits.count
        var remaining = localEdits
        for (id, edit) in localEdits.sorted(by: { $0.key < $1.key }) {
            try await client.saveOverride(token: adminToken, id: id, override: edit)
            remaining[id] = nil
            localEdits = remaining
            try? legacyEditStore?.save(remaining)
        }
        await refresh()
        return count
    }

    // MARK: Sync from CellarTracker

    /// Syncs with the saved CellarTracker login.
    func syncNow() async {
        guard let credentials = CredentialStore.load() else {
            syncError = "Add the CellarTracker login first."
            return
        }
        _ = await sync(credentials)
    }

    /// Checks a CellarTracker login by syncing with it, and saves it on this
    /// iPad only if that works. Returns whether it worked.
    func signIn(_ credentials: CellarTrackerCredentials) async -> Bool {
        guard await sync(credentials) else { return false }
        try? CredentialStore.save(credentials)
        hasCredentials = true
        return true
    }

    /// Forgets the CellarTracker login on this iPad. The menu stays.
    func signOut() {
        CredentialStore.delete()
        hasCredentials = false
    }

    /// The server downloads the export (browsers and the free plan's limits
    /// mean it only passes the file through), this iPad works out the menu,
    /// and uploads it for every device.
    private func sync(_ credentials: CellarTrackerCredentials) async -> Bool {
        guard let client, let adminToken else {
            syncError = "Unlock admin mode to sync."
            return false
        }
        guard !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let download = try await client.downloadExport(token: adminToken, credentials: credentials)
            let downloaded = try ExportDecoder.decodeBottles(download.body, contentType: download.contentType)
            let hadMenu = source == .server && !bottles.isEmpty
            let upload = SyncUpload(downloaded: downloaded, previous: hadMenu ? bottles : nil, overrides: overrides)
            try await client.commit(token: adminToken, upload: upload)
            syncError = nil
            syncReport = upload.syncReport
            await refresh()
            return true
        } catch {
            syncError = Self.message(for: error)
            return false
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: Loading

    private func apply(_ menu: ServerMenu) {
        guard !menu.products.isEmpty || source == .server else {
            // The server has no collection yet: keep showing the sample.
            overrides = menu.overrides
            return
        }
        bottles = menu.bottleRecords()
        overrides = menu.overrides
        lastSynced = menu.syncedDate
        source = .server
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
            overrides: source == .server ? overrides : [:],
            includeHidden: isAdmin,
            catalog: catalog
        )
    }
}
