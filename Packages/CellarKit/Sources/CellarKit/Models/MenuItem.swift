import Foundation

/// One product on the menu: every bottle that shares a CellarTracker `iWine`.
public struct MenuItem: Sendable, Hashable, Identifiable {
    /// CellarTracker `iWine`.
    public var id: String
    /// The bottles in this group (after any house filtering).
    public var bottles: [BottleRecord]
    /// Values derived from CellarTracker data by `RuleEnricher`.
    public var rules: RuleEnrichment
    /// The owner's edits, if any. The effective values below prefer these.
    public var override: ItemOverride?
    /// The menu lines worded from CellarTracker data.
    public var wording: ItemWording

    public init(id: String, bottles: [BottleRecord], rules: RuleEnrichment, override: ItemOverride? = nil) {
        self.id = id
        self.bottles = bottles
        self.rules = rules
        self.override = override
        self.wording = MenuWording.split(bottles[0])
    }

    public init(id: String, bottles: [BottleRecord], basics: ItemBasics, override: ItemOverride? = nil) {
        self.id = id
        self.bottles = bottles
        self.rules = basics.rules
        self.override = override
        self.wording = basics.wording
    }

    /// Bottle used for the shared, product-level fields.
    public var representative: BottleRecord { bottles[0] }

    public var name: String { representative.name }
    public var producer: String? { representative.producer }
    public var designation: String? { representative.designation }
    public var country: String? { representative.country }
    public var region: String? { representative.region }
    public var vintage: Int? { representative.vintage }

    // MARK: Effective values (owner edits first, then rules)

    public var category: SpiritCategory { override?.category ?? rules.category }

    public var scotchRegion: ScotchRegion? {
        guard category == .scotch else { return nil }
        return override?.scotchRegion ?? rules.scotchRegion
    }

    public var scotchStyle: ScotchStyle? {
        guard category == .scotch else { return nil }
        return override?.scotchStyle ?? rules.scotchStyle ?? .singleMalt
    }

    public var abv: Double? { override?.abv ?? rules.abv }
    public var ageYears: Double? { override?.ageYears ?? rules.ageYears }

    public var style: String? {
        if let style = override?.style { return style.nonBlank }
        return rules.style
    }

    /// Tasting notes or description for the tasting card.
    public var itemDescription: String? { override?.description?.nonBlank }

    public var isHidden: Bool { override?.isHidden ?? false }

    public var bottleCount: Int { bottles.reduce(0) { $0 + $1.quantity } }
    public var openedCount: Int { bottles.filter(RuleEnricher.isOpened).reduce(0) { $0 + $1.quantity } }
    public var isOpened: Bool { openedCount > 0 }
    /// Bottles not yet opened.
    public var sealedCount: Int { bottleCount - openedCount }
    public var isLastBottle: Bool { bottleCount == 1 }

    /// Where the bottles are: one entry per location and bin, with counts,
    /// most bottles first.
    public func placements(mapping: HouseMapping) -> [ItemPlacement] {
        var counts: [ItemPlacement.Key: Int] = [:]
        var order: [ItemPlacement.Key] = []
        for bottle in bottles {
            let key = ItemPlacement.Key(location: bottle.location, bin: bottle.bin)
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += bottle.quantity
        }
        return order
            .map { key in
                ItemPlacement(
                    house: mapping.house(forLocation: key.location),
                    location: key.location,
                    bin: key.bin,
                    count: counts[key] ?? 0
                )
            }
            .sorted { $0.count > $1.count }
    }

    /// Distinct sizes, e.g. ["700ml", "50ml"].
    public var sizes: [String] {
        var seen = Set<String>()
        return bottles.compactMap(\.size).filter { seen.insert($0).inserted }
    }

    /// Distinct non-empty bottle notes, e.g. "bottle 124 of 280".
    public var notes: [String] {
        var seen = Set<String>()
        return bottles.compactMap(\.note).filter { seen.insert($0).inserted }
    }

    /// Community score (CT's CScore), if any bottle has one.
    public var communityScore: Double? { bottles.lazy.compactMap(\.communityScore).first }

    /// A readable location line, e.g. "Speyside, Scotland".
    public var originLine: String? {
        let parts: [String?] = category == .scotch
            ? [scotchRegion?.displayName, region]
            : [region, country]
        let joined = parts.compactMap { $0 }.reduce(into: [String]()) { result, part in
            if !result.contains(part) { result.append(part) }
        }
        return joined.isEmpty ? nil : joined.joined(separator: ", ")
    }
}

/// Where some of an item's bottles are kept.
public struct ItemPlacement: Sendable, Hashable {
    public var house: House?
    /// CellarTracker Location, e.g. "Owl's Perch".
    public var location: String?
    /// CellarTracker Bin, e.g. "Cabinet 1-Bottom".
    public var bin: String?
    public var count: Int

    struct Key: Hashable {
        var location: String?
        var bin: String?
    }

    /// "Bedford · Owl's Perch · Cabinet 1-Bottom"
    ///
    /// CellarTracker locations often repeat the house name ("Estancia",
    /// "Estancia Open"), so that part is dropped: "Estancia" and
    /// "Estancia · Open".
    public var description: String {
        [house?.name, shortLocation, bin].compactMap { $0 }.joined(separator: " · ")
    }

    /// The location without a leading house name, or `nil` if that's all it was.
    public var shortLocation: String? {
        guard let location = location?.trimmingCharacters(in: .whitespaces), !location.isEmpty else { return nil }
        guard let house else { return location }
        let lower = location.lowercased()
        let name = house.name.lowercased()
        if lower == name { return nil }
        if lower.hasPrefix(name + " ") {
            let rest = location.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
            return rest.prefix(1).uppercased() + rest.dropFirst()
        }
        return location
    }
}
