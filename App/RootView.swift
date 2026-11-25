import CellarKit
import SwiftUI

/// Pages reachable from the cover.
enum Route: Hashable {
    case category(SpiritCategory)
    case openBottles
    case newArrivals
    case search
}

/// Navigation root: the cover, with menu pages pushed on top.
struct RootView: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            CoverView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .category(let category):
                        CategoryPageView(
                            title: category == .scotch ? "Scotch Whisky" : category.displayName,
                            groupedLabel: MenuSections.groupedLabel(for: category),
                            sections: { model, ordering in
                                MenuSections.sections(for: category, items: model.items(in: category), ordering: ordering)
                            }
                        )
                    case .openBottles:
                        CategoryPageView(title: "Tonight's Pours", sections: { model, _ in
                            model.openSections
                        })
                    case .newArrivals:
                        CategoryPageView(title: "New Arrivals", sections: { model, _ in
                            let items = model.newArrivals
                            return items.isEmpty ? [] : [MenuSection(title: "New Arrivals", items: items)]
                        })
                    case .search:
                        SearchPage()
                    }
                }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.light)
        .task { await model.syncIfNeeded() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await model.syncIfNeeded() } }
        }
    }
}
