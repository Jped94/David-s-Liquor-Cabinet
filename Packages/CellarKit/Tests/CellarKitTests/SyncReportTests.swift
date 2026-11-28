import Foundation
import Testing
@testable import CellarKit

@Suite struct SyncReportTests {
    func bottle(_ inventory: String, _ wine: String, _ name: String, pending: Bool = false) -> BottleRecord {
        BottleRecord(inventoryID: inventory, wineID: wine, name: name, isPending: pending)
    }

    @Test func firstSyncIsASummary() {
        let report = SyncReport.compare(old: nil, new: [bottle("1", "A", "Alpha"), bottle("2", "B", "Beta")])
        #expect(report.isInitial)
        #expect(!report.hasChanges)
        #expect(report.productCount == 2)
        #expect(report.bottleCount == 2)
    }

    @Test func reportsAddedIncreasedDecreasedAndRemoved() {
        let old = [
            bottle("1", "A", "Alpha"),
            bottle("2", "B", "Beta"), bottle("3", "B", "Beta"),
            bottle("4", "C", "Gamma"),
            bottle("5", "E", "Epsilon", pending: true),
        ]
        let new = [
            bottle("1", "A", "Alpha"), bottle("6", "A", "Alpha"),   // A: 1 → 2
            bottle("2", "B", "Beta"),                               // B: 2 → 1
            bottle("7", "D", "Delta"),                              // D: new
            bottle("5", "E", "Epsilon"),                            // E: delivered → new
        ]                                                           // C: gone
        let report = SyncReport.compare(old: old, new: new)
        #expect(!report.isInitial)
        #expect(report.hasChanges)
        #expect(report.added.map(\.title) == ["Delta", "Epsilon"])
        #expect(report.increased.map { "\($0.title) \($0.before)→\($0.after)" } == ["Alpha 1→2"])
        #expect(report.decreased.map { "\($0.title) \($0.before)→\($0.after)" } == ["Beta 2→1"])
        #expect(report.removed.map(\.title) == ["Gamma"])
    }

    @Test func identicalDownloadsHaveNoChanges() throws {
        let bottles = try FixtureTests.loadBottles()
        let report = SyncReport.compare(old: bottles, new: bottles)
        #expect(!report.hasChanges)
        #expect(report.productCount == 784)
    }

    @Test func usesEditedTitles() {
        let report = SyncReport.compare(
            old: [], new: [bottle("1", "A", "Alpha")],
            overrides: ["A": ItemOverride(title: "Edited Alpha")]
        )
        #expect(report.added.map(\.title) == ["Edited Alpha"])
    }
}
