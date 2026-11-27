import Foundation

/// Fields derived from a bottle's CellarTracker data by deterministic rules.
///
/// This is the bottom enrichment layer. It always runs, instantly and offline.
/// Claude enrichment and owner overrides sit on top of it (see PLAN.md).
public struct RuleEnrichment: Sendable, Hashable, Codable {
    public var category: SpiritCategory
    public var scotchRegion: ScotchRegion?
    public var scotchStyle: ScotchStyle?
    /// Alcohol by volume, as a percentage (e.g. 46.0).
    public var abv: Double?
    public var ageYears: Double?
    /// Style text from CT's Vineyard field with ABV and bottle counts removed,
    /// e.g. "Kentucky Straight Bourbon Whiskey".
    public var style: String?
    public var isCaskStrength: Bool
    public var isSingleCask: Bool

    public init(
        category: SpiritCategory,
        scotchRegion: ScotchRegion? = nil,
        scotchStyle: ScotchStyle? = nil,
        abv: Double? = nil,
        ageYears: Double? = nil,
        style: String? = nil,
        isCaskStrength: Bool = false,
        isSingleCask: Bool = false
    ) {
        self.category = category
        self.scotchRegion = scotchRegion
        self.scotchStyle = scotchStyle
        self.abv = abv
        self.ageYears = ageYears
        self.style = style
        self.isCaskStrength = isCaskStrength
        self.isSingleCask = isSingleCask
    }
}

/// Deterministic parsing and classification of CellarTracker spirits data.
public enum RuleEnricher {
    public static func enrich(_ bottle: BottleRecord) -> RuleEnrichment {
        let category = Self.category(for: bottle)
        let haystack = [bottle.name, bottle.designation, bottle.vineyard]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return RuleEnrichment(
            category: category,
            scotchRegion: category == .scotch ? scotchRegion(for: bottle) : nil,
            scotchStyle: category == .scotch ? scotchStyle(for: bottle) : nil,
            abv: abv(for: bottle),
            ageYears: ageYears(for: bottle),
            style: style(fromVineyard: bottle.vineyard),
            isCaskStrength: ["cask strength", "barrel proof", "barrel strength", "cask straight", "full proof"]
                .contains(where: { haystack.contains($0) }),
            isSingleCask: ["single cask", "single barrel"].contains(where: { haystack.contains($0) })
        )
    }

    // MARK: - Category

    static let whiskyGrains: Set<String> = ["malt", "grain", "rye", "wheat", "corn"]
    static let brandyVarietals: Set<String> = [
        "ugni blanc", "trebbiano", "apple", "pear", "grape blend", "pinot noir", "folle blanche", "colombard",
    ]

    public static func category(for bottle: BottleRecord) -> SpiritCategory {
        let name = bottle.name.lowercased()
        let words = Set(name.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let varietal = bottle.varietal?.lowercased() ?? ""
        let master = bottle.masterVarietal?.lowercased() ?? ""
        let country = bottle.country?.lowercased() ?? ""
        let region = bottle.region?.lowercased() ?? ""

        func whiskyCategory() -> SpiritCategory {
            if name.contains("scotch") || (country == "united kingdom" && region == "scotland") { return .scotch }
            if name.contains("bourbon") { return .bourbon }
            if words.contains("rye") || varietal == "rye" { return .rye }
            if country == "ireland" { return .irish }
            if country == "japan" { return .japanese }
            if country == "usa" { return .americanWhiskey }
            return .worldWhisky
        }
        func nameHas(_ keywords: [String]) -> Bool {
            keywords.contains(where: { words.contains($0) })
        }

        // 1. The name says whisky.
        if name.contains("whisk") || name.contains("bourbon") || name.contains("scotch") {
            return whiskyCategory()
        }

        // 2. The name names another spirit. This wins over the varietal,
        //    which CT sometimes gets wrong (e.g. a "Ron" marked as Grain).
        if nameHas(["tequila", "mezcal", "raicilla", "sotol", "bacanora"]) { return .agave }
        if nameHas(["rum", "rhum", "ron", "cachaça", "cachaca", "agricole", "clairin"]) { return .rum }
        if nameHas(["cognac", "armagnac", "brandy", "calvados", "marc", "grappa", "pisco"]) { return .brandy }
        if nameHas(["gin", "genever"]) { return .gin }
        if nameHas(["vodka"]) { return .vodka }
        if nameHas(["liqueur", "amaro", "vermouth", "aperitivo", "bitters", "cordial"]) { return .liqueur }

        // 3. Fall back to the base ingredient.
        if varietal == "agave" { return .agave }
        if varietal == "molasses" || varietal == "sugar cane" { return .rum }
        if brandyVarietals.contains(varietal) || brandyVarietals.contains(master) { return .brandy }
        if whiskyGrains.contains(varietal) { return whiskyCategory() }
        return .other
    }

    // MARK: - Scotch region

    static let regionKeywords: [(ScotchRegion, [String])] = [
        (.islay, ["islay"]),
        (.campbeltown, ["campbeltown"]),
        (.lowlands, ["lowland"]),
        (.islands, ["orkney", "skye", "mull", "jura", "arran", "lewis", "islands"]),
        (.speyside, ["speyside", "craigellachie", "dufftown", "easter elchies", "rothes", "elgin", "keith", "aberlour"]),
        (.highlands, ["highland"]),
    ]

    /// Looks at SubRegion, then Appellation, then the name. Distillery towns
    /// such as Craigellachie and Dufftown map to their region.
    public static func scotchRegion(for bottle: BottleRecord) -> ScotchRegion? {
        for field in [bottle.subRegion, bottle.appellation, bottle.name] {
            guard let text = field?.lowercased() else { continue }
            for (region, keywords) in regionKeywords where keywords.contains(where: { text.contains($0) }) {
                return region
            }
        }
        return nil
    }

    // MARK: - ABV

    /// ABV from the name (or the Vineyard field), e.g. "…, 54%" → 54.0.
    /// Also understands US proof, e.g. "125.9 Proof" → 62.95.
    // MARK: - Scotch style

    /// Blends sold under a brand name rather than a style on the label.
    static let blendedBrands = [
        "johnnie walker", "chivas regal", "dewar's", "famous grouse", "ballantine's", "cutty sark",
        "j&b", "teacher's", "grant's", "whyte & mackay", "royal salute", "buchanan's", "haig",
    ]
    static let blendedMaltBrands = ["monkey shoulder", "big peat", "scallywag", "timorous beastie", "rock oyster", "sheep dip"]

    /// Reads the style from the name and CT's Vineyard field ("Single Malt
    /// Scotch Whisky", "Blended Malt Scotch Whisky", ...). Anything that
    /// doesn't say otherwise is taken to be a single malt.
    public static func scotchStyle(for bottle: BottleRecord) -> ScotchStyle {
        let text = [bottle.name, bottle.producer, bottle.vineyard]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        if text.contains("single grain") { return .singleGrain }
        if ["blended malt", "vatted malt", "pure malt"].contains(where: { text.contains($0) })
            || blendedMaltBrands.contains(where: { text.contains($0) }) {
            return .blendedMalt
        }
        if text.contains("single malt") { return .singleMalt }
        if text.contains("blend") || blendedBrands.contains(where: { text.contains($0) }) { return .blended }
        return .singleMalt
    }

    public static func abv(for bottle: BottleRecord) -> Double? {
        for field in [bottle.name, bottle.vineyard] {
            guard let text = field else { continue }
            if let value = lastPercentage(in: text) { return value }
        }
        for field in [bottle.name, bottle.vineyard] {
            guard let text = field else { continue }
            if let proof = lastProof(in: text) { return proof / 2 }
        }
        return nil
    }

    // Each pattern starts with `(?:^|[^\d.])` so it can't begin matching in
    // the middle of a longer number (e.g. "13" inside "2013").

    static func lastPercentage(in text: String) -> Double? {
        let pattern = #/(?:^|[^\d.])(\d{1,2}(?:\.\d{1,2})?)\s?%/#
        let values = text.matches(of: pattern).compactMap { Double($0.output.1) }
        return values.last(where: { (15.0...80.0).contains($0) })
    }

    static func lastProof(in text: String) -> Double? {
        let pattern = #/(?:^|[^\d.])(\d{2,3}(?:\.\d{1,2})?)\s?proof/#.ignoresCase()
        let values = text.matches(of: pattern).compactMap { Double($0.output.1) }
        return values.last(where: { (30.0...160.0).contains($0) })
    }

    // MARK: - Age

    /// Age statement from the designation (or the name), e.g. "25 Year Old"
    /// → 25, "7.5 Year Old" → 7.5.
    public static func ageYears(for bottle: BottleRecord) -> Double? {
        let pattern = #/(?:^|[^\d.])(\d{1,2}(?:\.\d{1,2})?)[\s-]*(?:years?|yrs?|yo)\b/#.ignoresCase()
        for field in [bottle.designation, bottle.name] {
            guard let text = field, let match = text.firstMatch(of: pattern),
                  let years = Double(match.output.1), (1...80).contains(years)
            else { continue }
            return years
        }
        return nil
    }

    // MARK: - Style

    /// Strips ABV and bottle-count details from CT's Vineyard field:
    /// "Single Malt Scotch Whisky, 59.7%, 585 bottles" → "Single Malt Scotch Whisky".
    public static func style(fromVineyard vineyard: String?) -> String? {
        guard var text = vineyard else { return nil }
        if let percent = text.firstMatch(of: #/,?\s*\d{1,2}(?:\.\d{1,2})?\s?%/#) {
            text = String(text[..<percent.range.lowerBound])
        }
        text = text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",")))
        return text.contains(where: \.isLetter) ? text : nil
    }

    // MARK: - Location

    /// True when the bottle's location marks it as opened
    /// (e.g. "Open in Owl's perch", "194 Opened", "Estancia Open").
    public static func isOpened(_ bottle: BottleRecord) -> Bool {
        bottle.location?.lowercased().contains("open") ?? false
    }
}
