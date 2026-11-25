import Foundation

/// One physical bottle: a single row of the CellarTracker export.
///
/// Fields are read by column name, so the column order doesn't matter and
/// missing columns just come through empty. CellarTracker's "Unknown"
/// placeholder is turned into `nil`.
public struct BottleRecord: Sendable, Hashable, Identifiable, Codable {
    /// CellarTracker's per-bottle ID (`iInventory`).
    public var inventoryID: String
    /// CellarTracker's per-expression ID (`iWine`), shared by every bottle
    /// of the same product.
    public var wineID: String

    /// Full display name, usually including the style and ABV
    /// (e.g. "Aberfeldy 25 Year Old … Single Malt Scotch Whisky, 46%").
    public var name: String
    public var producer: String?
    /// Expression name (e.g. "25 Year Old 125th Anniversary Edition").
    public var designation: String?
    /// For spirits CellarTracker puts the style and ABV here
    /// (e.g. "Kentucky Straight Bourbon Whiskey, 54%").
    public var vineyard: String?
    public var varietal: String?
    public var masterVarietal: String?
    public var country: String?
    public var region: String?
    public var subRegion: String?
    public var appellation: String?
    /// Distillation or release year. `nil` for no vintage (CT uses 1001).
    public var vintage: Int?
    /// Bottle size as CT writes it, e.g. "750ml", "1.0L".
    public var size: String?

    public var location: String?
    public var bin: String?
    /// Free-text bottle note, e.g. "bottle 124 of 280".
    public var note: String?
    /// Logged as purchased but not yet marked delivered.
    public var isPending: Bool
    /// How many bottles this row stands for. CT's per-bottle export has one
    /// row per bottle (1); an aggregated export may carry a `Quantity` column.
    public var quantity: Int

    // Financials: admin only, never shown to guests.
    public var currency: String?
    public var value: Decimal?
    public var price: Decimal?
    public var storeName: String?
    public var purchaseDate: String?

    // Community data.
    public var communityScore: Double?
    public var communityNoteCount: Int?
    public var likePercent: Double?

    public var id: String { inventoryID }

    public init(
        inventoryID: String,
        wineID: String,
        name: String,
        producer: String? = nil,
        designation: String? = nil,
        vineyard: String? = nil,
        varietal: String? = nil,
        masterVarietal: String? = nil,
        country: String? = nil,
        region: String? = nil,
        subRegion: String? = nil,
        appellation: String? = nil,
        vintage: Int? = nil,
        size: String? = nil,
        location: String? = nil,
        bin: String? = nil,
        note: String? = nil,
        isPending: Bool = false,
        quantity: Int = 1,
        currency: String? = nil,
        value: Decimal? = nil,
        price: Decimal? = nil,
        storeName: String? = nil,
        purchaseDate: String? = nil,
        communityScore: Double? = nil,
        communityNoteCount: Int? = nil,
        likePercent: Double? = nil
    ) {
        self.inventoryID = inventoryID
        self.wineID = wineID
        self.name = name
        self.producer = producer
        self.designation = designation
        self.vineyard = vineyard
        self.varietal = varietal
        self.masterVarietal = masterVarietal
        self.country = country
        self.region = region
        self.subRegion = subRegion
        self.appellation = appellation
        self.vintage = vintage
        self.size = size
        self.location = location
        self.bin = bin
        self.note = note
        self.isPending = isPending
        self.quantity = quantity
        self.currency = currency
        self.value = value
        self.price = price
        self.storeName = storeName
        self.purchaseDate = purchaseDate
        self.communityScore = communityScore
        self.communityNoteCount = communityNoteCount
        self.likePercent = likePercent
    }

    /// CellarTracker's vintage value for "no vintage".
    static let nonVintage = 1001

    /// Builds a record from one CSV row keyed by header name. Returns `nil`
    /// for rows without an `iWine` or `Wine` value.
    public init?(row: [String: String]) {
        func text(_ key: String) -> String? {
            guard let raw = row[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  raw.caseInsensitiveCompare("Unknown") != .orderedSame
            else { return nil }
            return raw
        }
        func decimal(_ key: String) -> Decimal? {
            text(key).flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        }
        func double(_ key: String) -> Double? { text(key).flatMap(Double.init) }
        func int(_ key: String) -> Int? { text(key).flatMap { Int($0) } }

        guard let wineID = text("iWine"), let name = text("Wine") else { return nil }
        // The Bottles table also lists consumed bottles (BottleState 0).
        if text("BottleState") == "0" { return nil }
        let quantity = int("Quantity") ?? 1
        if quantity < 1 { return nil }

        let vintage = int("Vintage")
        let noteCount = int("CNotes")

        self.init(
            inventoryID: text("iInventory") ?? UUID().uuidString,
            wineID: wineID,
            name: name,
            producer: text("Producer"),
            designation: text("Designation"),
            vineyard: text("Vineyard"),
            varietal: text("Varietal"),
            masterVarietal: text("MasterVarietal"),
            country: text("Country"),
            region: text("Region"),
            subRegion: text("SubRegion"),
            appellation: text("Appellation"),
            vintage: vintage == Self.nonVintage ? nil : vintage,
            size: text("Size"),
            location: text("Location"),
            bin: text("Bin"),
            note: text("Note"),
            isPending: text("Pending") == "1",
            quantity: quantity,
            currency: text("Currency"),
            value: decimal("Value"),
            price: decimal("Price"),
            storeName: text("StoreName"),
            purchaseDate: text("PurchaseDate"),
            communityScore: double("CScore"),
            communityNoteCount: noteCount == 0 ? nil : noteCount,
            likePercent: double("LikePercent")
        )
    }
}
