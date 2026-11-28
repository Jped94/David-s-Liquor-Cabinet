import Foundation
import Testing
@testable import CellarKit

@Suite struct OverrideAndFilterTests {
    let bottles: [BottleRecord]

    init() throws {
        bottles = try FixtureTests.loadBottles()
    }

    func item(_ id: String, overrides: [String: ItemOverride] = [:], includeHidden: Bool = false) -> MenuItem? {
        MenuBuilder.items(from: bottles, overrides: overrides, includeHidden: includeHidden)
            .first { $0.id == id }
    }

    // MARK: Overrides

    @Test func overridesReplaceDisplayedValues() throws {
        let edit = ItemOverride(
            title: "Aberfeldy 25",
            subtitle: "",
            category: .worldWhisky,
            abv: 45.5,
            ageYears: 26,
            style: "Highland Single Malt",
            description: "  Honeyed and soft.  "
        )
        let edited = try #require(item("4833686", overrides: ["4833686": edit]))
        #expect(edited.menuTitle == "Aberfeldy 25")
        #expect(edited.menuSubtitle == nil) // empty string clears it
        #expect(edited.category == .worldWhisky)
        #expect(edited.scotchRegion == nil) // no longer Scotch
        #expect(edited.abv == 45.5)
        #expect(edited.ageYears == 26)
        #expect(edited.style == "Highland Single Malt")
        #expect(edited.itemDescription == "Honeyed and soft.")

        // The rule values are untouched underneath.
        #expect(edited.rules.category == .scotch)
        #expect(edited.rules.abv == 46)
    }

    @Test func blankOverridesFallBackToRules() throws {
        let edited = try #require(item("4833686", overrides: ["4833686": ItemOverride(title: "   ", scotchRegion: .speyside)]))
        #expect(edited.menuTitle == "Aberfeldy 25 Year Old")
        #expect(edited.scotchRegion == .speyside)
        #expect(edited.style == "Single Malt Scotch Whisky")
    }

    @Test func hiddenItemsOnlyAppearInAdminMode() {
        let overrides = ["4833686": ItemOverride(isHidden: true)]
        #expect(item("4833686", overrides: overrides) == nil)
        #expect(item("4833686", overrides: overrides, includeHidden: true)?.isHidden == true)
    }

    @Test func overrideStoreRoundTripsAndDropsEmptyEdits() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CellarKitTests-\(UUID().uuidString)/overrides.json")
        let store = OverrideStore(fileURL: url)
        #expect(try store.load().isEmpty)

        let edits = ["1": ItemOverride(title: "X", isHidden: true), "2": ItemOverride()]
        try store.save(edits)
        #expect(try store.load() == ["1": ItemOverride(title: "X", isHidden: true)])
    }

    // MARK: Locations

    @Test func listsAHousesLocationsByBottleCount() {
        let mapping = HouseMapping.default
        #expect(mapping.locations(for: .bedford, in: bottles) ==
            ["Owl's Perch", "Cellar", "Open in Owl's perch", "194 Opened", "Basement"])
        #expect(mapping.locations(for: .estancia, in: bottles) == ["Estancia", "Estancia Open"])
    }

    @Test func hidesChosenLocations() {
        let everything = MenuBuilder.items(from: bottles, filter: .house(.bedford))
        let noCellar = MenuBuilder.items(from: bottles, filter: .house(.bedford), hiddenLocations: ["cellar ", "BASEMENT"])
        let bottlesShown = noCellar.reduce(0) { $0 + $1.bottleCount }
        #expect(bottlesShown == 1589 - 418 - 16)
        #expect(noCellar.count < everything.count)
        #expect(noCellar.allSatisfy { item in
            item.bottles.allSatisfy { $0.location != "Cellar" && $0.location != "Basement" }
        })
    }

    @Test func linksToCellarTracker() {
        let bottle = BottleRecord(inventoryID: "1", wineID: "4833686", name: "Aberfeldy 25")
        let item = MenuItem(id: "4833686", bottles: [bottle], rules: RuleEnricher.enrich(bottle))
        #expect(item.cellarTrackerURL?.absoluteString == "https://www.cellartracker.com/wine.asp?iWine=4833686")
        let odd = MenuItem(id: "abc", bottles: [bottle], rules: RuleEnricher.enrich(bottle))
        #expect(odd.cellarTrackerURL == nil)
    }

    @Test func placementsGroupByLocationAndBin() {
        let a = BottleRecord(inventoryID: "1", wineID: "9", name: "X", location: "Owl's Perch", bin: "Cabinet 1")
        let b = BottleRecord(inventoryID: "2", wineID: "9", name: "X", location: "Owl's Perch", bin: "Cabinet 1")
        let c = BottleRecord(inventoryID: "3", wineID: "9", name: "X", location: "Estancia")
        let d = BottleRecord(inventoryID: "4", wineID: "9", name: "X", location: "Estancia Open")
        let item = MenuItem(id: "9", bottles: [c, a, b, d], rules: RuleEnricher.enrich(a))
        let placements = item.placements(mapping: .default)
        // The house name isn't repeated in the location.
        #expect(placements.map(\.description) == ["Bedford · Owl's Perch · Cabinet 1", "Estancia", "Estancia · Open"])
        #expect(placements.map(\.count) == [2, 1, 1])
        #expect(item.openedCount == 1)
        #expect(item.sealedCount == 3)
    }

    // MARK: Ordering

    @Test func alphabeticalOrderingUsesLetters() {
        let scotch = MenuBuilder.items(from: bottles, includePending: true).filter { $0.category == .scotch }
        let byLetter = MenuSections.sections(for: .scotch, items: scotch, ordering: .alphabetical)
        #expect(byLetter.allSatisfy { $0.title.count == 1 })
        #expect(byLetter.first?.title == "A")
        #expect(byLetter.reduce(0) { $0 + $1.items.count } == 314)
        #expect(MenuSections.groupedLabel(for: .scotch) == "By region")
        #expect(MenuSections.groupedLabel(for: .rum) == "By country")
        #expect(MenuSections.groupedLabel(for: .bourbon) == nil)
    }
}
