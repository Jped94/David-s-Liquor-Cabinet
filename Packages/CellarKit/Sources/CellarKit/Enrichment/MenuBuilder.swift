import Foundation

/// Which bottles a menu shows.
public enum HouseFilter: Hashable, Sendable {
    /// Every bottle, including ones at unmapped locations.
    case all
    /// Only bottles at locations mapped to this house.
    case house(House)
}

/// Turns raw bottle records into menu items.
public enum MenuBuilder {
    /// Groups bottles by `iWine`, applies rule enrichment, and filters by house.
    ///
    /// - Parameters:
    ///   - hiddenLocations: CT locations to leave out (matched like the
    ///     house mapping: case and surrounding spaces don't matter).
    ///   - overrides: The owner's edits, keyed by `iWine`.
    ///   - includePending: Pending ("on order") bottles are left out unless
    ///     this is true. Guests never see them.
    ///   - includeHidden: Items the owner hid are left out unless this is
    ///     true (admin mode).
    ///   - catalog: Precomputed `ItemBasics.catalog(for:)` of these bottles,
    ///     so rebuilding (e.g. on a house change) skips the text parsing.
    /// - Returns: Menu items sorted by name.
    public static func items(
        from bottles: [BottleRecord],
        filter: HouseFilter = .all,
        mapping: HouseMapping = .default,
        hiddenLocations: Set<String> = [],
        overrides: [String: ItemOverride] = [:],
        includePending: Bool = false,
        includeHidden: Bool = false,
        catalog: [String: ItemBasics]? = nil
    ) -> [MenuItem] {
        let hidden = Set(hiddenLocations.map(HouseMapping.normalize))
        let visible = bottles.filter { bottle in
            if bottle.isPending && !includePending { return false }
            if let location = bottle.location, hidden.contains(HouseMapping.normalize(location)) { return false }
            switch filter {
            case .all: return true
            case .house(let house): return mapping.house(forLocation: bottle.location) == house
            }
        }

        var order: [String] = []
        var groups: [String: [BottleRecord]] = [:]
        for bottle in visible {
            if groups[bottle.wineID] == nil { order.append(bottle.wineID) }
            groups[bottle.wineID, default: []].append(bottle)
        }

        return order
            .compactMap { id -> MenuItem? in
                guard let group = groups[id], let first = group.first else { return nil }
                let basics = catalog?[id] ?? ItemBasics(first)
                let item = MenuItem(id: id, bottles: group, basics: basics, override: overrides[id])
                return item.isHidden && !includeHidden ? nil : item
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Counts items per category, in `SpiritCategory` order, leaving
    /// out empty categories.
    public static func categoryCounts(_ items: [MenuItem]) -> [(category: SpiritCategory, count: Int)] {
        var counts: [SpiritCategory: Int] = [:]
        for item in items { counts[item.category.menuCategory, default: 0] += 1 }
        return SpiritCategory.menuCategories.compactMap { category in
            counts[category].map { (category: category, count: $0) }
        }
    }
}
