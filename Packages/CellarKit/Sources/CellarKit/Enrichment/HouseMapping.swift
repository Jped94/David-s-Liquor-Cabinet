import Foundation

/// A house the collection is spread across (e.g. "Bedford", "Estancia").
public struct House: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    public var name: String
    public init(_ name: String) { self.name = name }
    public var id: String { name }
    public var description: String { name }

    public static let bedford = House("Bedford")
    public static let estancia = House("Estancia")
}

/// Maps CellarTracker `Location` values to houses.
///
/// Matching ignores case and surrounding whitespace. The owner can edit the
/// mapping in admin mode. Any location that isn't mapped shows up in
/// `unmappedLocations(in:)` so it can be assigned.
public struct HouseMapping: Hashable, Codable, Sendable {
    /// Normalized location name → house.
    public private(set) var assignments: [String: House]

    public init(_ assignments: [String: House] = [:]) {
        self.assignments = [:]
        for (location, house) in assignments { assign(location, to: house) }
    }

    /// Lowercased and trimmed, the form locations are compared in.
    public static func normalize(_ location: String) -> String {
        location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public mutating func assign(_ location: String, to house: House?) {
        assignments[Self.normalize(location)] = house
    }

    public func house(forLocation location: String?) -> House? {
        guard let location else { return nil }
        return assignments[Self.normalize(location)]
    }

    public var houses: [House] {
        Array(Set(assignments.values)).sorted { $0.name < $1.name }
    }

    /// Distinct locations in `bottles` that aren't assigned to a house.
    public func unmappedLocations(in bottles: [BottleRecord]) -> [String] {
        let unmapped = bottles.compactMap(\.location).filter { house(forLocation: $0) == nil }
        return Array(Set(unmapped)).sorted()
    }

    /// The distinct locations in `bottles` that belong to `house`, most
    /// bottles first. Pending bottles are ignored.
    public func locations(for house: House, in bottles: [BottleRecord]) -> [String] {
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        for bottle in bottles where !bottle.isPending {
            guard let location = bottle.location, self.house(forLocation: location) == house else { continue }
            let key = Self.normalize(location)
            counts[key, default: 0] += bottle.quantity
            if names[key] == nil { names[key] = location }
        }
        return counts.keys
            .sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
            .compactMap { names[$0] }
    }

    /// The default mapping for David's collection.
    public static let `default` = HouseMapping([
        "Estancia": .estancia,
        "Estancia Open": .estancia,
        "Owl's Perch": .bedford,
        "Open in Owl's perch": .bedford,
        "Cellar": .bedford,
        "Basement": .bedford,
        "194 Opened": .bedford,
    ])
}
