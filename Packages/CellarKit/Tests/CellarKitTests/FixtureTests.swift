import Foundation
import Testing
@testable import CellarKit

/// End-to-end checks against a sanitized copy of David's real export
/// (prices, stores, dates, barcodes and bins removed). The file is
/// windows-1252 encoded, exactly as CellarTracker serves it.
@Suite struct FixtureTests {
    static func loadBottles() throws -> [BottleRecord] {
        let url = try #require(
            Bundle.module.url(forResource: "sample_export", withExtension: "csv", subdirectory: "Fixtures")
        )
        return try ExportDecoder.decodeBottles(Data(contentsOf: url))
    }

    let bottles: [BottleRecord]

    init() throws {
        bottles = try Self.loadBottles()
    }

    @Test func parsesEveryBottle() {
        #expect(bottles.count == 1648)
        #expect(Set(bottles.map(\.wineID)).count == 785)
        #expect(bottles.filter(\.isPending).count == 9)
    }

    @Test func decodesNonASCIINames() {
        #expect(bottles.contains { $0.name == "Leblon Cachaça" })
    }

    @Test func classifiesEveryExpression() {
        let items = MenuBuilder.items(from: bottles, includePending: true)
        #expect(items.count == 785)

        let counts = Dictionary(uniqueKeysWithValues: MenuBuilder.categoryCounts(items).map { ($0.category, $0.count) })
        #expect(counts == [
            .scotch: 314,
            .bourbon: 192,
            .rum: 57,
            .rye: 53,
            .agave: 49,
            .irish: 49,
            .americanWhiskey: 31,
            .japanese: 15,
            .worldWhisky: 14,
            .brandy: 11,
        ])
        #expect(counts[.other] == nil)
    }

    @Test func assignsScotchRegions() {
        let scotch = MenuBuilder.items(from: bottles, includePending: true).filter { $0.category == .scotch }
        let withRegion = scotch.filter { $0.rules.scotchRegion != nil }
        #expect(withRegion.count == 306) // 8 of 314 have no region data
    }

    @Test func filtersByHouseAndHidesPending() {
        let all = MenuBuilder.items(from: bottles)
        #expect(all.count == 784)
        #expect(all.reduce(0) { $0 + $1.bottleCount } == 1639)

        let bedford = MenuBuilder.items(from: bottles, filter: .house(.bedford))
        #expect(bedford.count == 759)
        #expect(bedford.reduce(0) { $0 + $1.bottleCount } == 1589)

        let estancia = MenuBuilder.items(from: bottles, filter: .house(.estancia))
        #expect(estancia.count == 37)
        #expect(estancia.reduce(0) { $0 + $1.bottleCount } == 50)
    }

    @Test func everyLocationIsMapped() {
        #expect(HouseMapping.default.unmappedLocations(in: bottles).isEmpty)
    }

    @Test func findsOpenedBottles() {
        let opened = MenuBuilder.items(from: bottles).filter(\.isOpened)
        #expect(opened.count == 86)
    }

    @Test func enrichesKnownBottles() throws {
        let items = MenuBuilder.items(from: bottles, includePending: true)
        func item(_ id: String) throws -> MenuItem { try #require(items.first { $0.id == id }) }

        let aberfeldy = try item("4833686")
        #expect(aberfeldy.category == .scotch)
        #expect(aberfeldy.rules.scotchRegion == .highlands)
        #expect(aberfeldy.rules.abv == 46)
        #expect(aberfeldy.rules.ageYears == 25)
        #expect(aberfeldy.vintage == nil)

        let twoXO = try item("5921806")
        #expect(twoXO.category == .bourbon)
        #expect(twoXO.rules.abv == 54)
        #expect(twoXO.rules.style == "Kentucky Straight Bourbon Whiskey")
        #expect(twoXO.vintage == 2023)

        #expect(try item("2021247").category == .rum) // "Ron" with a Grain varietal
        #expect(try item("5892974").rules.ageYears == 7.5)
    }

    @Test func sanitizedFixtureHasNoFinancials() {
        #expect(bottles.allSatisfy { $0.price == nil && $0.value == nil && $0.storeName == nil })
    }
}
