import Foundation
import Testing
@testable import CellarKit

/// The derived fields for every bottle and product in the sample export,
/// written to `Fixtures/golden.json`.
///
/// The server's TypeScript port of these rules must reproduce the file
/// exactly, so the iPads, the web page and this package never disagree.
/// After an intended rule change, regenerate it with:
///
///     WRITE_GOLDEN=1 swift test --filter GoldenTests
@Suite struct GoldenTests {
    struct Golden: Codable, Equatable {
        var bottles: [Bottle]
        var products: [Product]
    }

    struct Bottle: Codable, Equatable {
        var inventoryID: String
        var wineID: String
        var name: String
        var location: String?
        var bin: String?
        var quantity: Int
        var isPending: Bool
        var vintage: Int?
        var size: String?
        var note: String?
        var communityScore: Double?
    }

    struct Product: Codable, Equatable {
        var id: String
        var name: String
        var category: String
        var scotchRegion: String?
        var scotchStyle: String?
        var agaveKind: String?
        var abv: Double?
        var ageYears: Double?
        var style: String?
        var isCaskStrength: Bool
        var isSingleCask: Bool
        var title: String
        var subtitle: String?
    }

    static func makeGolden() throws -> Golden {
        let records = try FixtureTests.loadBottles()
        let bottles = records.map { b in
            Bottle(
                inventoryID: b.inventoryID, wineID: b.wineID, name: b.name, location: b.location, bin: b.bin,
                quantity: b.quantity, isPending: b.isPending, vintage: b.vintage, size: b.size, note: b.note,
                communityScore: b.communityScore
            )
        }
        let items = MenuBuilder.items(from: records, includePending: true)
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        let products = items.map { item in
            Product(
                id: item.id,
                name: item.name,
                category: item.rules.category.rawValue,
                scotchRegion: item.rules.scotchRegion?.rawValue,
                scotchStyle: item.rules.scotchStyle?.rawValue,
                agaveKind: item.category == .agave ? MenuSections.agaveKind(item) : nil,
                abv: item.rules.abv,
                ageYears: item.rules.ageYears,
                style: item.rules.style,
                isCaskStrength: item.rules.isCaskStrength,
                isSingleCask: item.rules.isSingleCask,
                title: item.wording.title,
                subtitle: item.wording.subtitle
            )
        }
        return Golden(bottles: bottles, products: products)
    }

    static func encode(_ golden: Golden) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(golden) + Data("\n".utf8)
    }

    @Test func matchesGoldenFile() throws {
        let golden = try Self.makeGolden()
        if ProcessInfo.processInfo.environment["WRITE_GOLDEN"] == "1" {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/golden.json")
            try Self.encode(golden).write(to: url)
            return
        }
        let url = try #require(Bundle.module.url(forResource: "golden", withExtension: "json", subdirectory: "Fixtures"))
        let saved = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
        #expect(saved.bottles == golden.bottles)
        #expect(saved.products == golden.products, "Rules changed: regenerate with WRITE_GOLDEN=1 if intended")
    }
}
