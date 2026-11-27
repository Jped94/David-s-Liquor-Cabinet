import Foundation

// The shared server's menu format (see server/src/rules/payload.ts). The
// server stores what a syncing device uploads and serves it back to every
// iPad and the web page.

/// A product as stored on the server: CellarTracker's fields plus the menu
/// fields derived from them.
public struct ServerProduct: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var producer: String?
    public var designation: String?
    public var vineyard: String?
    public var varietal: String?
    public var masterVarietal: String?
    public var vintage: Int?
    public var country: String?
    public var region: String?
    public var subRegion: String?
    public var appellation: String?

    public var category: SpiritCategory
    public var scotchRegion: ScotchRegion?
    public var scotchStyle: ScotchStyle?
    public var agaveKind: String?
    public var abv: Double?
    public var ageYears: Double?
    public var style: String?
    public var isCaskStrength: Bool
    public var isSingleCask: Bool
    public var title: String
    public var subtitle: String?
}

/// A bottle as stored on the server. Pending bottles are never uploaded,
/// and prices and stores are never stored.
public struct ServerBottle: Codable, Sendable, Hashable {
    public var inventoryID: String
    public var wineID: String
    public var location: String?
    public var bin: String?
    public var quantity: Int
    public var size: String?
    public var note: String?
    public var communityScore: Double?
}

/// `GET /api/menu`.
public struct ServerMenu: Codable, Sendable, Equatable {
    /// Changes on every sync or edit.
    public var version: String
    /// When the collection was last synced from CellarTracker (ISO 8601).
    public var syncedAt: String?
    public var products: [ServerProduct]
    public var bottles: [ServerBottle]
    public var overrides: [String: ItemOverride]

    public init(
        version: String, syncedAt: String?, products: [ServerProduct], bottles: [ServerBottle],
        overrides: [String: ItemOverride]
    ) {
        self.version = version
        self.syncedAt = syncedAt
        self.products = products
        self.bottles = bottles
        self.overrides = overrides
    }

    public var syncedDate: Date? {
        syncedAt.flatMap { text in
            (try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
                ?? (try? Date(text, strategy: .iso8601))
        }
    }

    /// The bottles as `BottleRecord`s, with each product's fields filled in,
    /// so the rest of the app works exactly as with a direct CellarTracker
    /// download.
    public func bottleRecords() -> [BottleRecord] {
        let products = Dictionary(self.products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return bottles.compactMap { bottle in
            guard let product = products[bottle.wineID] else { return nil }
            return BottleRecord(
                inventoryID: bottle.inventoryID,
                wineID: bottle.wineID,
                name: product.name,
                producer: product.producer,
                designation: product.designation,
                vineyard: product.vineyard,
                varietal: product.varietal,
                masterVarietal: product.masterVarietal,
                country: product.country,
                region: product.region,
                subRegion: product.subRegion,
                appellation: product.appellation,
                vintage: product.vintage,
                size: bottle.size,
                location: bottle.location,
                bin: bottle.bin,
                note: bottle.note,
                quantity: bottle.quantity,
                communityScore: bottle.communityScore
            )
        }
    }
}

// MARK: Sync upload

/// `POST /api/sync/commit`: the menu worked out on this device from a fresh
/// CellarTracker download, plus the report of what changed.
public struct SyncUpload: Encodable, Sendable {
    public var products: [ServerProduct]
    public var bottles: [ServerBottle]
    public var report: ReportPayload

    /// The report in the server's format (same fields as `SyncReport`).
    public struct ReportPayload: Encodable, Sendable {
        public struct Change: Encodable, Sendable {
            var id: String
            var title: String
            var subtitle: String?
            var category: SpiritCategory
            var before: Int
            var after: Int
        }
        var date: String
        var isInitial: Bool
        var productCount: Int
        var bottleCount: Int
        var added: [Change]
        var increased: [Change]
        var decreased: [Change]
        var removed: [Change]

        init(_ report: SyncReport) {
            func changes(_ list: [SyncReport.Change]) -> [Change] {
                list.map {
                    Change(id: $0.id, title: $0.title, subtitle: $0.subtitle, category: $0.category, before: $0.before, after: $0.after)
                }
            }
            date = report.date.formatted(.iso8601)
            isInitial = report.isInitial
            productCount = report.productCount
            bottleCount = report.bottleCount
            added = changes(report.added)
            increased = changes(report.increased)
            decreased = changes(report.decreased)
            removed = changes(report.removed)
        }
    }

    public let syncReport: SyncReport

    enum CodingKeys: String, CodingKey { case products, bottles, report }

    /// Builds the upload from a CellarTracker download. Pending ("on order")
    /// bottles are left out.
    ///
    /// - Parameter previous: The bottles before this sync, or `nil` if there
    ///   has never been a sync (the report is then the first one).
    public init(
        downloaded: [BottleRecord],
        previous: [BottleRecord]?,
        overrides: [String: ItemOverride],
        date: Date = Date()
    ) {
        let delivered = downloaded.filter { !$0.isPending }
        var seen = Set<String>()
        var products: [ServerProduct] = []
        for bottle in delivered where seen.insert(bottle.wineID).inserted {
            products.append(ServerProduct(bottle))
        }
        self.products = products
        bottles = delivered.map(ServerBottle.init)
        syncReport = SyncReport.compare(old: previous, new: delivered, overrides: overrides, date: date)
        report = ReportPayload(syncReport)
    }
}

extension ServerProduct {
    init(_ bottle: BottleRecord) {
        let basics = ItemBasics(bottle)
        let rules = basics.rules
        let agaveKind: String? = rules.category == .agave
            ? MenuSections.agaveKind(MenuItem(id: bottle.wineID, bottles: [bottle], basics: basics))
            : nil
        self.init(
            id: bottle.wineID, name: bottle.name, producer: bottle.producer, designation: bottle.designation,
            vineyard: bottle.vineyard, varietal: bottle.varietal, masterVarietal: bottle.masterVarietal, vintage: bottle.vintage, country: bottle.country,
            region: bottle.region, subRegion: bottle.subRegion, appellation: bottle.appellation,
            category: rules.category, scotchRegion: rules.scotchRegion, scotchStyle: rules.scotchStyle,
            agaveKind: agaveKind, abv: rules.abv, ageYears: rules.ageYears, style: rules.style,
            isCaskStrength: rules.isCaskStrength, isSingleCask: rules.isSingleCask,
            title: basics.wording.title, subtitle: basics.wording.subtitle
        )
    }
}

extension ServerBottle {
    init(_ bottle: BottleRecord) {
        self.init(
            inventoryID: bottle.inventoryID, wineID: bottle.wineID, location: bottle.location, bin: bottle.bin,
            quantity: bottle.quantity, size: bottle.size, note: bottle.note, communityScore: bottle.communityScore
        )
    }
}
