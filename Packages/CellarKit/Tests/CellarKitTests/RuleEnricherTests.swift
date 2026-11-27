import Testing
@testable import CellarKit

@Suite struct RuleEnricherTests {
    func bottle(
        _ name: String,
        designation: String? = nil,
        vineyard: String? = nil,
        varietal: String? = nil,
        country: String? = nil,
        region: String? = nil,
        subRegion: String? = nil,
        appellation: String? = nil,
        location: String? = nil
    ) -> BottleRecord {
        BottleRecord(
            inventoryID: "1", wineID: "1", name: name, designation: designation, vineyard: vineyard,
            varietal: varietal, country: country, region: region, subRegion: subRegion,
            appellation: appellation, location: location
        )
    }

    // MARK: Category

    @Test(arguments: [
        ("Lagavulin 16 Year Old Single Malt Scotch Whisky, 43%", SpiritCategory.scotch),
        ("Blanton's Single Barrel Kentucky Straight Bourbon Whiskey, 46.5%", .bourbon),
        ("Sazerac Straight Rye Whiskey, 45%", .rye),
        ("Fortaleza Blanco Tequila, 40%", .agave),
        ("Appleton Estate 21 Year Old Rum, 43%", .rum),
        ("Leblon Cachaça", .rum),
        ("ABK6 Cognac Grande Champagne XXO", .brandy),
        ("Monkey 47 Schwarzwald Dry Gin, 47%", .gin),
        ("The Original Recipe Spirit", .other), // "original" must not read as "gin"
    ])
    func categorisesByName(name: String, expected: SpiritCategory) {
        #expect(RuleEnricher.category(for: bottle(name)) == expected)
    }

    @Test func nameBeatsWrongVarietal() {
        // CT marks this rum's varietal as "Grain".
        let ron = bottle("Equipo Navazos Ron Navazos Palazzi", varietal: "Grain", country: "Spain")
        #expect(RuleEnricher.category(for: ron) == .rum)
    }

    @Test func usesCountryForWhiskies() {
        #expect(RuleEnricher.category(for: bottle("Redbreast 12 Single Pot Still Whiskey", country: "Ireland")) == .irish)
        #expect(RuleEnricher.category(for: bottle("Yamazaki 12 Single Malt Whisky", country: "Japan")) == .japanese)
        #expect(RuleEnricher.category(for: bottle("Kavalan Solist Single Malt Whisky", country: "Taiwan (ROC)")) == .worldWhisky)
        #expect(RuleEnricher.category(for: bottle("Jack Daniel's Tennessee Whiskey, 40%", country: "USA")) == .americanWhiskey)
    }

    @Test func fallsBackToVarietal() {
        #expect(RuleEnricher.category(for: bottle("Del Maguey Vida", varietal: "Agave")) == .agave)
        #expect(RuleEnricher.category(for: bottle("Breckenridge Dark Arts", varietal: "Malt", country: "USA")) == .americanWhiskey)
    }

    // MARK: Scotch region

    @Test func mapsScotchRegions() {
        #expect(RuleEnricher.scotchRegion(for: bottle("X", subRegion: "Islay")) == .islay)
        #expect(RuleEnricher.scotchRegion(for: bottle("X", subRegion: "Craigellachie")) == .speyside)
        #expect(RuleEnricher.scotchRegion(for: bottle("X", appellation: "Northern Highlands")) == .highlands)
        #expect(RuleEnricher.scotchRegion(for: bottle("X", subRegion: "Orkney Islands")) == .islands)
        #expect(RuleEnricher.scotchRegion(for: bottle("Compass Box Peat Monster")) == nil)
    }

    // MARK: ABV & age

    @Test func parsesABV() {
        #expect(RuleEnricher.abv(for: bottle("Aberfeldy 25, 46%")) == 46)
        #expect(RuleEnricher.abv(for: bottle("Glenfarclas 105, 59.7%, 585 bottles")) == 59.7)
        #expect(RuleEnricher.abv(for: bottle("No ABV here", vineyard: "Single Malt Scotch Whisky, 43%")) == 43)
        #expect(RuleEnricher.abv(for: bottle("Some Spirit 100% Agave")) == nil) // out of range
        let proof = RuleEnricher.abv(for: bottle("Booker's Bourbon 125.9 Proof"))
        #expect(abs((proof ?? 0) - 62.95) < 0.001)
        #expect(RuleEnricher.abv(for: bottle("Bacardi Carta Blanca")) == nil)
    }

    @Test func parsesAgeStatements() {
        #expect(RuleEnricher.ageYears(for: bottle("X", designation: "25 Year Old 125th Anniversary Edition")) == 25)
        #expect(RuleEnricher.ageYears(for: bottle("Dark Arts 7.5 Year Old Straight Rye Whiskey")) == 7.5)
        #expect(RuleEnricher.ageYears(for: bottle("Ardbeg 10yo")) == 10)
        #expect(RuleEnricher.ageYears(for: bottle("Release of 2013 Years Gone")) == nil) // not "13"
        #expect(RuleEnricher.ageYears(for: bottle("Ardbeg Uigeadail")) == nil)
    }

    // MARK: Style & flags

    @Test func cleansStyleFromVineyard() {
        #expect(RuleEnricher.style(fromVineyard: "Single Malt Scotch Whisky, 59.7%, 585 bottles") == "Single Malt Scotch Whisky")
        #expect(RuleEnricher.style(fromVineyard: "Kentucky Straight Bourbon Whiskey 66.85%") == "Kentucky Straight Bourbon Whiskey")
        #expect(RuleEnricher.style(fromVineyard: "40%") == nil)
        #expect(RuleEnricher.style(fromVineyard: nil) == nil)
    }

    @Test func detectsCaskStrengthAndSingleCask() {
        let rules = RuleEnricher.enrich(bottle("Aberlour A'bunadh Cask Strength Single Malt Scotch Whisky, 58.07%"))
        #expect(rules.isCaskStrength)
        #expect(!rules.isSingleCask)
        #expect(RuleEnricher.enrich(bottle("Blanton's Single Barrel Bourbon")).isSingleCask)
    }

    @Test func detectsOpenedBottles() {
        #expect(RuleEnricher.isOpened(bottle("X", location: "Open in Owl's perch")))
        #expect(RuleEnricher.isOpened(bottle("X", location: "194 Opened")))
        #expect(!RuleEnricher.isOpened(bottle("X", location: "Cellar")))
        #expect(!RuleEnricher.isOpened(bottle("X")))
    }

    @Test func readsScotchStyle() {
        func style(_ name: String, vineyard: String? = nil) -> ScotchStyle {
            RuleEnricher.scotchStyle(for: BottleRecord(inventoryID: "1", wineID: "1", name: name, vineyard: vineyard))
        }
        #expect(style("Lagavulin 16 Year Old", vineyard: "Single Malt Scotch Whisky, 43%") == .singleMalt)
        #expect(style("Compass Box The Peat Monster", vineyard: "Blended Malt Scotch Whisky, 46%") == .blendedMalt)
        #expect(style("Compass Box Monster", vineyard: "Vatted Malt Scotch Whisky 54.9%") == .blendedMalt)
        #expect(style("Monkey Shoulder") == .blendedMalt)
        #expect(style("Johnnie Walker Blue Label") == .blended)
        #expect(style("Compass Box Hedonism", vineyard: "Blended Grain Scotch Whisky") == .blended)
        #expect(style("Invergordon 33 Year Old", vineyard: "Single Grain Scotch Whisky, 46.2%") == .singleGrain)
        #expect(style("Springbank 10 Year Old") == .singleMalt)
    }
}
