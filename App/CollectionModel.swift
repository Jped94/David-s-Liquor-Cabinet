import CellarKit
import Foundation
import Observation

/// App-wide collection state.
///
/// Phase 1 loads the bundled sample export. Phase 2 replaces this with the
/// CellarTracker sync and a SwiftData cache.
@Observable
@MainActor
final class CollectionModel {
    private(set) var bottles: [BottleRecord] = []
    private(set) var items: [MenuItem] = []
    private(set) var loadError: String?
    let isSampleData = true

    var mapping = HouseMapping.default { didSet { rebuild() } }
    var house: HouseFilter = .house(.bedford) { didSet { rebuild() } }

    init() {
        loadSample()
    }

    var openedItems: [MenuItem] { items.filter(\.isOpened) }

    var categoryCounts: [(category: SpiritCategory, count: Int)] {
        MenuBuilder.categoryCounts(items)
    }

    func items(in category: SpiritCategory) -> [MenuItem] {
        items.filter { $0.category == category }
    }

    func search(_ query: String) -> [MenuItem] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            [item.name, item.producer, item.originLine, item.rules.style]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private func loadSample() {
        guard let url = Bundle.main.url(forResource: "sample_export", withExtension: "csv") else {
            loadError = "The bundled sample data is missing."
            return
        }
        do {
            bottles = try ExportDecoder.decodeBottles(Data(contentsOf: url))
            rebuild()
        } catch {
            loadError = "Couldn't read the sample data: \(error)"
        }
    }

    private func rebuild() {
        items = MenuBuilder.items(from: bottles, filter: house, mapping: mapping)
    }
}
