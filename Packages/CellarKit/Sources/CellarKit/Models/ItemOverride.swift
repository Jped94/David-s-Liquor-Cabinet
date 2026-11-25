import Foundation

/// The owner's edits to one menu item, keyed by CellarTracker `iWine`.
///
/// Edits live only on the iPad and never change CellarTracker. They sit on
/// top of the rule-based values and survive every sync. For the text fields,
/// `nil` means "use the CellarTracker / rule value"; for `subtitle` and
/// `style`, an empty string means "show nothing".
public struct ItemOverride: Codable, Sendable, Hashable {
    public var title: String?
    public var subtitle: String?
    public var category: SpiritCategory?
    public var scotchRegion: ScotchRegion?
    public var abv: Double?
    public var ageYears: Double?
    public var style: String?
    /// Tasting notes or a description shown on the tasting card.
    public var description: String?
    /// Left off the guest menu (still visible in admin mode).
    public var isHidden: Bool

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        category: SpiritCategory? = nil,
        scotchRegion: ScotchRegion? = nil,
        abv: Double? = nil,
        ageYears: Double? = nil,
        style: String? = nil,
        description: String? = nil,
        isHidden: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.scotchRegion = scotchRegion
        self.abv = abv
        self.ageYears = ageYears
        self.style = style
        self.description = description
        self.isHidden = isHidden
    }

    /// True when nothing is overridden, so the edit can be discarded.
    public var isEmpty: Bool { self == ItemOverride() }
}

extension String {
    /// The string trimmed, or `nil` if that leaves nothing.
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Saves the owner's edits as `overrides.json` next to the collection cache.
public struct OverrideStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultStore() throws -> OverrideStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return OverrideStore(fileURL: directory.appendingPathComponent("overrides.json"))
    }

    public func load() throws -> [String: ItemOverride] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        return try JSONDecoder().decode([String: ItemOverride].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ overrides: [String: ItemOverride]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(overrides.filter { !$0.value.isEmpty })
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }
}
