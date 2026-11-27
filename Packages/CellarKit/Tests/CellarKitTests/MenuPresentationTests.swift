import Foundation
import Testing
@testable import CellarKit

@Suite struct MenuPresentationTests {
    func item(producer: String?, designation: String?, vintage: Int? = nil, name: String = "Full CT Name, 46%") -> MenuItem {
        let bottle = BottleRecord(
            inventoryID: "1", wineID: "1", name: name, producer: producer,
            designation: designation, vintage: vintage
        )
        return MenuItem(id: "1", bottles: [bottle], rules: RuleEnricher.enrich(bottle))
    }

    @Test func putsAgeStatementInTitle() {
        let ardbeg = item(producer: "Ardbeg", designation: "22 Year Old Manager's Choice Cask #2391 Sherry", vintage: 1976)
        #expect(ardbeg.menuTitle == "Ardbeg 22 Year Old")
        #expect(ardbeg.menuSubtitle == "Manager's Choice Cask #2391 Sherry · Vintage 1976")
    }

    @Test func findsAgeStatementAnywhere() {
        let pappy = item(producer: "Old Rip Van Winkle Distillery", designation: "Van Winkle Family Reserve 18 Year Old")
        #expect(pappy.menuTitle == "Old Rip Van Winkle Distillery 18 Year Old")
        #expect(pappy.menuSubtitle == "Van Winkle Family Reserve")

        let flor = item(producer: "Flor de Cana", designation: "Centenario Gold 18yrs")
        #expect(flor.menuTitle == "Flor de Cana 18 Year Old")
        #expect(flor.menuSubtitle == "Centenario Gold")
    }

    @Test func foldsShortExpressionIntoTitle() {
        let owl = item(producer: "Kentucky Owl", designation: "Takumi Edition")
        #expect(owl.menuTitle == "Kentucky Owl Takumi Edition")
        #expect(owl.menuSubtitle == nil)
    }

    @Test func keepsLongExpressionAsSubtitle() {
        let hog = item(producer: "WhistlePig", designation: "The Boss Hog XI The Juggernaut")
        #expect(hog.menuTitle == "WhistlePig")
        #expect(hog.menuSubtitle == "The Boss Hog XI The Juggernaut")
    }

    @Test func ignoresYearsThatAreNotAges() {
        let release = item(producer: "Maker's Mark", designation: "Release of 2013 Years Gone By Edition", vintage: 2014)
        #expect(release.menuTitle == "Maker's Mark")
        #expect(release.menuSubtitle == "Release of 2013 Years Gone By Edition · Vintage 2014")
    }

    @Test func dropsABVAndRepeatedVintage() {
        let skorpios = item(producer: "Skorpios", designation: "1618 Tequila Joven, 40%")
        #expect(skorpios.menuTitle == "Skorpios 1618 Tequila Joven")
        let park = item(producer: "Highland Park", designation: "28 Year Old Vintage 1973 Cask #11167", vintage: 1973)
        #expect(park.menuSubtitle == "Vintage 1973 Cask #11167")
    }

    @Test func fallsBackToFullName() {
        let unknown = item(producer: nil, designation: nil, name: "Leblon Cachaça")
        #expect(unknown.menuTitle == "Leblon Cachaça")
        #expect(unknown.menuSubtitle == nil)
        #expect(item(producer: "Redemption", designation: nil).menuTitle == "Redemption")
    }

    @Test func smallPagesStillGroupBySpirit() {
        func agave(_ name: String) -> MenuItem {
            let bottle = BottleRecord(inventoryID: name, wineID: name, name: name, varietal: "Agave", country: "Mexico")
            return MenuItem(id: name, bottles: [bottle], rules: RuleEnricher.enrich(bottle))
        }
        let items = [agave("Fortaleza Blanco Tequila"), agave("Del Maguey Vida Mezcal")]
        #expect(MenuSections.sections(for: .agave, items: items).map(\.title) == ["Tequila", "Mezcal"])
        #expect(MenuSections.sections(for: .agave, items: items, ordering: .alphabetical).map(\.title) == ["Tequila & Mezcal"])
    }

    @Test func alphabetSectionsIgnoreTheAndAccents() {
        #expect(MenuSections.initial(of: "The Macallan 18 Year Old") == "M")
        #expect(MenuSections.initial(of: "Élevage") == "E")
        #expect(MenuSections.initial(of: "1792 Full Proof") == "#")
    }

    @Test func groupsFixtureCategoriesLikeAMenu() throws {
        let items = MenuBuilder.items(from: try FixtureTests.loadBottles(), includePending: true)
        func sections(_ category: SpiritCategory) -> [MenuSection] {
            MenuSections.sections(for: category, items: items.filter { $0.category.menuCategory == category })
        }

        let scotch = sections(.scotch)
        #expect(scotch.map(\.title) == ["Islay", "Speyside", "Highlands", "Lowlands", "Campbeltown", "Islands", "Scotland"])
        #expect(scotch.map(\.items.count) == [73, 117, 65, 5, 19, 27, 8])

        // Small categories are a single list.
        #expect(sections(.japanese).map(\.title) == ["Japanese Whisky"])

        let agave = sections(.agave)
        #expect(agave.map(\.title) == ["Tequila", "Mezcal", "Other Agave"])
        #expect(agave.map(\.items.count) == [44, 4, 1])

        let american = sections(.americanWhiskey)
        #expect(american.map(\.title) == ["Bourbon", "Rye", "Other"])
        #expect(american.map(\.items.count) == [192, 53, 31])

        let americanAZ = MenuSections.sections(
            for: .americanWhiskey,
            items: items.filter { $0.category.menuCategory == .americanWhiskey },
            ordering: .alphabetical
        )
        #expect(americanAZ.allSatisfy { $0.title.count == 1 })
        #expect(americanAZ.reduce(0) { $0 + $1.items.count } == 276)
    }
}
