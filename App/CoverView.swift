import CellarKit
import SwiftUI

/// The menu's front page: masthead, tonight's open bottles, and the list
/// of spirits.
struct CoverView: View {
    @Environment(CollectionModel.self) private var model
    @State private var width: CGFloat = Layout.twoColumnMinWidth
    private var isWide: Bool { width >= Layout.twoColumnMinWidth }
    @State private var selected: MenuItem?

    /// How many open bottles the cover lists.
    private let poursShown = 6

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                topBar
                masthead
                if !isWide {
                    VStack(spacing: 40) {
                        poursColumn
                        listColumn
                    }
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        poursColumn
                            .padding(.trailing, 36)
                        Rectangle().fill(Theme.rule).frame(width: 1)
                        listColumn
                            .padding(.leading, 36)
                    }
                }
                CoverSyncStatus()
                    .padding(.top, 8)
            }
            .padding(.horizontal, !isWide ? 24 : 72)
            .padding(.vertical, 28)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper.ignoresSafeArea())
        .readWidth($width)
        .refreshable { await model.sync() }
        .navigationTitle("Contents")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selected) { item in
            TastingCardView(item: item)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            HouseMenu()
            Spacer()
            NavigationLink(value: Route.search) { SearchIcon() }
                .accessibilityLabel("Search")
            SettingsButton()
        }
    }

    // MARK: Masthead

    private var masthead: some View {
        VStack(spacing: 10) {
            DoubleRule()
            Text("David's Cabinet")
                .font(Theme.display(!isWide ? 44 : 68))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Text("\(model.items.count) bottlings · \(model.openedItems.count) open tonight")
                .font(Theme.italic(20))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 8)
            DoubleRule()
        }
    }

    // MARK: Columns

    private var poursColumn: some View {
        VStack(spacing: 16) {
            columnHeading("Tonight's Pours", caption: "Open & ready")
            if model.featuredPours(poursShown).isEmpty {
                Text("Nothing is open at the moment.")
                    .font(Theme.italic(18))
                    .foregroundStyle(Theme.muted)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(model.featuredPours(poursShown)) { item in
                        MenuEntryView(item: item, showsCategory: true) { selected = item }
                    }
                }
                if model.openedItems.count > poursShown {
                    NavigationLink(value: Route.openBottles) {
                        CapsLabel("All \(model.openedItems.count) open bottles →", size: 14)
                            .frame(minHeight: 44)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var listColumn: some View {
        VStack(spacing: 16) {
            columnHeading("The List", caption: "By spirit")
            VStack(spacing: 4) {
                ForEach(model.categoryCounts, id: \.category) { entry in
                    NavigationLink(value: Route.category(entry.category)) {
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            Text(entry.category == .scotch ? "Scotch Whisky" : entry.category.displayName)
                                .font(Theme.body(23))
                                .foregroundStyle(Theme.ink)
                            DottedLeader()
                            Text("\(entry.count)")
                                .font(Theme.body(17))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func columnHeading(_ title: String, caption: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(Theme.display(27, bold: false))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            CapsLabel(caption)
        }
        .padding(.bottom, 6)
    }
}

/// Small italic sync line at the foot of the cover.
struct CoverSyncStatus: View {
    @Environment(CollectionModel.self) private var model

    var body: some View {
        VStack(spacing: 4) {
            if model.isSyncing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Updating from CellarTracker…")
                }
            } else if model.isSampleData {
                Text(model.isServerConfigured
                    ? "Showing sample data until the collection is synced."
                    : "Showing sample data. This build isn't connected to the cabinet server.")
            }
            if let error = model.syncError {
                Text(error).foregroundStyle(Theme.accent)
            }
        }
        .font(Theme.italic(15))
        .foregroundStyle(Theme.muted)
        .multilineTextAlignment(.center)
    }
}
