import CellarKit
import SwiftUI

/// The menu's front page: masthead, tonight's open bottles, and the list
/// of spirits.
struct CoverView: View {
    @Environment(CollectionModel.self) private var model
    @State private var width: CGFloat = Layout.twoColumnMinWidth
    private var isWide: Bool { width >= Layout.twoColumnMinWidth }
    @State private var selected: MenuItem?
    @State private var showingSettings = false
    @State private var choosingLocationsFor: House?

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
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(item: $choosingLocationsFor) { house in
            LocationsSheet(house: house)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        @Bindable var model = model
        return HStack {
            // The visible label is an ordinary view with the menu laid over
            // it. A Menu's own label shows new text in its old frame before
            // resizing, which clipped "Both houses" for a moment.
            houseLabel
                .accessibilityHidden(true)
                .overlay {
                    Menu {
                        Picker("House", selection: $model.house) {
                            Text("Bedford").tag(HouseFilter.house(.bedford))
                            Text("Estancia").tag(HouseFilter.house(.estancia))
                            Text("Both houses").tag(HouseFilter.all)
                        }
                        if case .house(let house) = model.house {
                            Button {
                                choosingLocationsFor = house
                            } label: {
                                Label("Choose \(house.name) locations…", systemImage: "checklist")
                            }
                        }
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .accessibilityLabel("House: \(houseName)")
                }

            Spacer()

            NavigationLink(value: Route.search) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Search")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.muted.opacity(0.7))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
        }
    }

    private var houseLabel: some View {
        HStack(spacing: 6) {
            CapsLabel(houseName, size: 15)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
            if let locationSummary {
                Text(locationSummary)
                    .font(Theme.italic(16))
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 4)
            }
        }
        .frame(minHeight: 44)
    }

    /// "3 of 5 locations" when some of the house's locations are hidden.
    private var locationSummary: String? {
        guard case .house(let house) = model.house else { return nil }
        let all = model.locations(for: house)
        let shown = all.filter(model.isLocationShown).count
        return shown == all.count ? nil : "\(shown) of \(all.count) locations"
    }

    private var houseName: String {
        switch model.house {
        case .all: "Both houses"
        case .house(let house): house.name
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
