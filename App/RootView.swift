import CellarKit
import SwiftUI

/// Pages reachable from the cover.
enum Route: Hashable {
    case category(SpiritCategory)
    case openBottles
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
                            styles: { model in category == .scotch ? model.scotchStyles : [] },
                            sections: { model, ordering, style in
                                MenuSections.sections(
                                    for: category,
                                    items: model.items(in: category, style: style),
                                    ordering: ordering
                                )
                            }
                        )
                    case .openBottles:
                        // Everything here is open, so no "open only" switch.
                        CategoryPageView(title: "Tonight's Pours", showsOpenToggle: false, sections: { model, _, _ in
                            model.openSections
                        })
                    case .search:
                        SearchPage()
                    }
                }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.light)
        .sheet(item: Binding(
            get: { model.isSettingsOpen ? nil : model.syncReport },
            set: { model.syncReport = $0 }
        )) { report in
            SyncReportView(report: report)
        }
        .task { await model.syncIfNeeded() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await model.syncIfNeeded() } }
        }
    }
}
