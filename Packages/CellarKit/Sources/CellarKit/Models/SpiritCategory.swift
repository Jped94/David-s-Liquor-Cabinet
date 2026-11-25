/// The menu's top-level spirit categories.
///
/// CellarTracker labels every spirit `Spirits / Other / Distilled`, so the
/// category is derived (see `RuleEnricher`) and can be overridden by the owner.
public enum SpiritCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case scotch
    case bourbon
    case rye
    case americanWhiskey
    case irish
    case japanese
    case worldWhisky
    case rum
    case agave
    case brandy
    case gin
    case vodka
    case liqueur
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .scotch: "Scotch"
        case .bourbon: "Bourbon"
        case .rye: "Rye"
        case .americanWhiskey: "American Whiskey"
        case .irish: "Irish Whiskey"
        case .japanese: "Japanese Whisky"
        case .worldWhisky: "World Whisky"
        case .rum: "Rum & Cane"
        case .agave: "Tequila & Mezcal"
        case .brandy: "Brandy & Cognac"
        case .gin: "Gin"
        case .vodka: "Vodka"
        case .liqueur: "Liqueurs"
        case .other: "Other"
        }
    }

    public var isWhisky: Bool {
        switch self {
        case .scotch, .bourbon, .rye, .americanWhiskey, .irish, .japanese, .worldWhisky: true
        default: false
        }
    }
}

/// Scotch whisky regions, used as the Scotch sub-category.
public enum ScotchRegion: String, CaseIterable, Codable, Sendable, Identifiable {
    case islay
    case speyside
    case highlands
    case lowlands
    case campbeltown
    case islands

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .islay: "Islay"
        case .speyside: "Speyside"
        case .highlands: "Highlands"
        case .lowlands: "Lowlands"
        case .campbeltown: "Campbeltown"
        case .islands: "Islands"
        }
    }
}
