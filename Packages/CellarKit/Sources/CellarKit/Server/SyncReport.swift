import Foundation

/// What changed between two downloads of the collection.
public struct SyncReport: Identifiable, Sendable, Equatable {
    /// One product whose bottle count changed.
    public struct Change: Identifiable, Sendable, Equatable {
        /// CellarTracker `iWine`.
        public var id: String
        public var title: String
        public var subtitle: String?
        public var category: SpiritCategory
        public var before: Int
        public var after: Int
    }

    public let id = UUID()
    public var date: Date
    /// No earlier CellarTracker download to compare with (first sign-in).
    public var isInitial: Bool
    public var productCount: Int
    public var bottleCount: Int

    /// Products that weren't in the collection before.
    public var added: [Change]
    /// Products with more bottles than before.
    public var increased: [Change]
    /// Products with fewer bottles than before (but some left).
    public var decreased: [Change]
    /// Products no longer in the collection.
    public var removed: [Change]

    public var hasChanges: Bool {
        !(added.isEmpty && increased.isEmpty && decreased.isEmpty && removed.isEmpty)
    }

    public static func == (a: SyncReport, b: SyncReport) -> Bool {
        a.date == b.date && a.isInitial == b.isInitial && a.productCount == b.productCount
            && a.bottleCount == b.bottleCount && a.added == b.added && a.increased == b.increased
            && a.decreased == b.decreased && a.removed == b.removed
    }

    /// Compares two downloads. Pending ("on order") bottles don't count, so a
    /// bottle that arrives shows up as added once it's marked delivered.
    ///
    /// - Parameter old: The previous download, or `nil` for the first one.
    public static func compare(
        old: [BottleRecord]?,
        new: [BottleRecord],
        overrides: [String: ItemOverride] = [:],
        date: Date = Date()
    ) -> SyncReport {
        let newItems = MenuBuilder.items(from: new, overrides: overrides, includeHidden: true)
        let newCounts = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })
        let totalBottles = newItems.reduce(0) { $0 + $1.bottleCount }

        guard let old else {
            return SyncReport(
                date: date, isInitial: true, productCount: newItems.count, bottleCount: totalBottles,
                added: [], increased: [], decreased: [], removed: []
            )
        }

        let oldItems = MenuBuilder.items(from: old, overrides: overrides, includeHidden: true)
        let oldCounts = Dictionary(uniqueKeysWithValues: oldItems.map { ($0.id, $0) })

        func change(_ item: MenuItem, before: Int, after: Int) -> Change {
            Change(
                id: item.id, title: item.menuTitle, subtitle: item.menuSubtitle,
                category: item.category, before: before, after: after
            )
        }

        var added: [Change] = []
        var increased: [Change] = []
        var decreased: [Change] = []
        for item in newItems {
            let before = oldCounts[item.id]?.bottleCount ?? 0
            let after = item.bottleCount
            if before == 0 {
                added.append(change(item, before: 0, after: after))
            } else if after > before {
                increased.append(change(item, before: before, after: after))
            } else if after < before {
                decreased.append(change(item, before: before, after: after))
            }
        }
        let removed = oldItems
            .filter { newCounts[$0.id] == nil }
            .map { change($0, before: $0.bottleCount, after: 0) }

        func sorted(_ changes: [Change]) -> [Change] {
            changes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        return SyncReport(
            date: date, isInitial: false, productCount: newItems.count, bottleCount: totalBottles,
            added: sorted(added), increased: sorted(increased),
            decreased: sorted(decreased), removed: sorted(removed)
        )
    }
}
