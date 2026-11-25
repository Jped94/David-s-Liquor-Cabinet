import Foundation

// How menu items are worded and grouped on the printed-menu pages.

extension MenuItem {
    /// The bold first line of a menu entry: producer plus age statement,
    /// e.g. "Ardbeg 22 Year Old", or producer plus a short expression name,
    /// e.g. "WhistlePig The Boss Hog XI".
    public var menuTitle: String {
        override?.title?.nonBlank ?? MenuWording.split(self).title
    }

    /// The second line: the rest of the expression name and the vintage,
    /// e.g. "Manager's Choice Cask #2391 Sherry · Vintage 1976".
    public var menuSubtitle: String? {
        if let subtitle = override?.subtitle { return subtitle.nonBlank }
        return MenuWording.split(self).subtitle
    }
}

enum MenuWording {
    /// Expression names up to this length are folded into the title.
    static let shortRestLimit = 28

    static func split(_ item: MenuItem) -> (title: String, subtitle: String?) {
        let producer = item.producer
        let vintageText = item.vintage.map { "Vintage \($0)" }

        guard let producer else {
            return (item.name, vintageText)
        }

        var rest = item.designation ?? ""
        var ageText: String?
        if let (age, range) = ageStatement(in: rest) {
            ageText = age
            rest.removeSubrange(range)
        }
        rest = tidy(rest)

        var title = producer
        if let ageText {
            title += " " + ageText
        } else if !rest.isEmpty, rest.count <= shortRestLimit {
            title += " " + rest
            rest = ""
        }

        // Don't repeat a year the expression name already mentions.
        let vintage = item.vintage.flatMap { rest.contains(String($0)) ? nil : vintageText }
        let parts = [rest.isEmpty ? nil : rest, vintage].compactMap { $0 }
        return (title, parts.isEmpty ? nil : parts.joined(separator: " · "))
    }

    /// Finds an age statement ("22 Year Old", "18yrs", "10 YO") and returns
    /// it normalized as "N Year Old" with its range in `text`.
    static func ageStatement(in text: String) -> (String, Range<String.Index>)? {
        // The leading group stops a match starting mid-number ("2013 Year").
        let pattern = #/(?:^|[^\d.])((\d{1,2}(?:\.\d)?)[\s-]*(?:years?[\s-]+old|years?|yrs?|yo)\b)/#.ignoresCase()
        guard let match = text.firstMatch(of: pattern) else { return nil }
        let statement = match.output.1
        return ("\(match.output.2) Year Old", statement.startIndex..<statement.endIndex)
    }

    /// Collapses spaces and trims stray separators left after removing the age.
    static func tidy(_ text: String) -> String {
        var text = text
        // Drop an ABV that CT sometimes leaves in the expression name.
        if let abv = text.firstMatch(of: #/,?\s*\d{1,2}(?:\.\d{1,2})?\s?%/#) {
            text.removeSubrange(abv.range)
        }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " ,-–—·:"))
    }
}

/// One headed section of a category page.
public struct MenuSection: Identifiable, Sendable, Hashable {
    public var id: String { title }
    public var title: String
    public var items: [MenuItem]

    public init(title: String, items: [MenuItem]) {
        self.title = title
        self.items = items
    }
}

/// How a category page is arranged.
public enum MenuOrdering: String, Sendable, CaseIterable {
    /// Scotch by region, rum by country, agave by spirit.
    case grouped
    /// A–Z by name.
    case alphabetical
}

public enum MenuSections {
    /// Categories whose grouped layout differs from A–Z, with the label for
    /// the grouped option, e.g. "By region".
    public static func groupedLabel(for category: SpiritCategory) -> String? {
        switch category {
        case .scotch: "By region"
        case .rum: "By country"
        default: nil
        }
    }

    /// Categories this small are shown as one list without section headings.
    public static let singleSectionLimit = 20

    /// Groups a category's items the way a printed menu would:
    /// Scotch by region, agave by spirit, rum by country, everything else
    /// alphabetically. Items within a section are sorted by `menuTitle`.
    public static func sections(
        for category: SpiritCategory,
        items: [MenuItem],
        ordering: MenuOrdering = .grouped
    ) -> [MenuSection] {
        let sorted = items.sorted {
            $0.menuTitle.localizedStandardCompare($1.menuTitle) == .orderedAscending
        }
        if sorted.count < singleSectionLimit {
            return sorted.isEmpty ? [] : [MenuSection(title: category.displayName, items: sorted)]
        }

        if ordering == .alphabetical {
            return grouped(sorted, order: nil) { initial(of: $0.menuTitle) }
        }

        switch category {
        case .scotch:
            let order = ScotchRegion.allCases.map(\.displayName) + ["Scotland"]
            return grouped(sorted, order: order) { $0.scotchRegion?.displayName ?? "Scotland" }
        case .agave:
            return grouped(sorted, order: ["Tequila", "Mezcal", "Other Agave"]) { agaveKind($0) }
        case .rum:
            return grouped(sorted, order: nil) { $0.country ?? "Other" }
        default:
            return grouped(sorted, order: nil) { initial(of: $0.menuTitle) }
        }
    }

    static func agaveKind(_ item: MenuItem) -> String {
        let name = item.name.lowercased()
        let words = Set(name.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let region = item.region?.lowercased() ?? ""
        let subRegion = item.representative.subRegion?.lowercased() ?? ""
        if name.contains("mezcal") || region == "oaxaca" { return "Mezcal" }
        if name.contains("tequila") || region == "jalisco" || subRegion == "tequila"
            || !words.isDisjoint(with: ["blanco", "reposado", "añejo", "anejo", "joven", "plata"]) {
            return "Tequila"
        }
        return "Other Agave"
    }

    /// "The Macallan" files under M, digits under "#".
    static func initial(of title: String) -> String {
        var text = title
        if text.lowercased().hasPrefix("the ") { text = String(text.dropFirst(4)) }
        guard let first = text.first else { return "#" }
        if first.isLetter {
            return String(first).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).uppercased()
        }
        return "#"
    }

    /// Groups preserving item order. With `order`, sections follow it (and
    /// unknown keys go last); without it, sections are alphabetical.
    static func grouped(_ items: [MenuItem], order: [String]?, key: (MenuItem) -> String) -> [MenuSection] {
        var groups: [String: [MenuItem]] = [:]
        for item in items { groups[key(item), default: []].append(item) }
        let keys = groups.keys.sorted { a, b in
            if let order {
                let ia = order.firstIndex(of: a) ?? order.count
                let ib = order.firstIndex(of: b) ?? order.count
                if ia != ib { return ia < ib }
            }
            if a == "#" { return false }
            if b == "#" { return true }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        return keys.map { MenuSection(title: $0, items: groups[$0] ?? []) }
    }
}
