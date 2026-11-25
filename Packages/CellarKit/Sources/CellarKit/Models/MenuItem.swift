/// One product on the menu: every bottle that shares a CellarTracker `iWine`.
public struct MenuItem: Sendable, Hashable, Identifiable {
    /// CellarTracker `iWine`.
    public var id: String
    /// The bottles in this group (after any house filtering).
    public var bottles: [BottleRecord]
    public var rules: RuleEnrichment

    public init(id: String, bottles: [BottleRecord], rules: RuleEnrichment) {
        self.id = id
        self.bottles = bottles
        self.rules = rules
    }

    /// Bottle used for the shared, product-level fields.
    public var representative: BottleRecord { bottles[0] }

    public var name: String { representative.name }
    public var producer: String? { representative.producer }
    public var designation: String? { representative.designation }
    public var country: String? { representative.country }
    public var region: String? { representative.region }
    public var vintage: Int? { representative.vintage }
    public var category: SpiritCategory { rules.category }

    public var bottleCount: Int { bottles.count }
    public var openedCount: Int { bottles.filter(RuleEnricher.isOpened).count }
    public var isOpened: Bool { openedCount > 0 }
    public var isLastBottle: Bool { bottleCount == 1 }

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
            ? [rules.scotchRegion?.displayName, region]
            : [region, country]
        let joined = parts.compactMap { $0 }.reduce(into: [String]()) { result, part in
            if !result.contains(part) { result.append(part) }
        }
        return joined.isEmpty ? nil : joined.joined(separator: ", ")
    }
}
