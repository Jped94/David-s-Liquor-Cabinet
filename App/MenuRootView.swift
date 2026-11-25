import CellarKit
import SwiftUI

enum MenuSection: Hashable {
    case nowPouring
    case category(SpiritCategory)
}

/// Phase 1 browser: sidebar of sections, a bottle list, and a detail pane.
/// The real guest menu design comes in phases 3 and 5.
struct MenuRootView: View {
    @Environment(CollectionModel.self) private var model
    @State private var section: MenuSection? = .nowPouring
    @State private var selectedItemID: MenuItem.ID?
    @State private var searchText = ""
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            ItemListView(items: visibleItems, selection: $selectedItemID)
                .navigationTitle(listTitle)
                .searchable(text: $searchText, prompt: "Search bottles")
                .refreshable { await model.syncNow() }
        } detail: {
            if let item = model.items.first(where: { $0.id == selectedItemID }) {
                ItemDetailView(item: item)
            } else {
                ContentUnavailableView("Choose a bottle", systemImage: "wineglass")
            }
        }
        .onChange(of: section) { selectedItemID = nil }
        .task { await model.syncIfNeeded() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await model.syncIfNeeded() } }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(selection: $section) {
            Section {
                Label("Now Pouring", systemImage: "wineglass")
                    .badge(model.openedItems.count)
                    .tag(MenuSection.nowPouring)
            }
            Section("Spirits") {
                ForEach(model.categoryCounts, id: \.category) { entry in
                    Text(entry.category.displayName)
                        .badge(entry.count)
                        .tag(MenuSection.category(entry.category))
                }
            }
            Section {
                SyncStatusView()
            }
        }
        .navigationTitle("Liquor Cabinet")
        .toolbar {
            ToolbarItem {
                Picker("House", selection: $model.house) {
                    Text("Bedford").tag(HouseFilter.house(.bedford))
                    Text("Estancia").tag(HouseFilter.house(.estancia))
                    Text("All").tag(HouseFilter.all)
                }
                .pickerStyle(.menu)
            }
            ToolbarItem {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }

    private var visibleItems: [MenuItem] {
        if !searchText.isEmpty { return model.search(searchText) }
        switch section {
        case .nowPouring: return model.openedItems
        case .category(let category): return model.items(in: category)
        case nil: return []
        }
    }

    private var listTitle: String {
        if !searchText.isEmpty { return "Search" }
        switch section {
        case .nowPouring: return "Now Pouring"
        case .category(let category): return category.displayName
        case nil: return ""
        }
    }
}

/// One-line sync status for the bottom of the sidebar.
struct SyncStatusView: View {
    @Environment(CollectionModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.isSyncing {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("Syncing with CellarTracker…")
                }
            } else if model.isSampleData {
                Text("Showing sample data. Open Settings to connect CellarTracker.")
            } else if let lastSynced = model.lastSynced {
                Text("Synced \(lastSynced.formatted(.relative(presentation: .named)))")
            }
            if let error = model.syncError {
                Text(error).foregroundStyle(.red)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

struct ItemListView: View {
    let items: [MenuItem]
    @Binding var selection: MenuItem.ID?

    var body: some View {
        List(items, selection: $selection) { item in
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let origin = item.originLine { Text(origin) }
                    if let age = item.rules.ageYears { Text(Format.age(age)) }
                    if let abv = item.rules.abv { Text(Format.abv(abv)) }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if item.isOpened { Badge(text: "Open", tint: .green) }
                    if item.isLastBottle { Badge(text: "Last bottle", tint: .orange) }
                    if item.rules.isCaskStrength { Badge(text: "Cask strength", tint: .purple) }
                }
            }
            .padding(.vertical, 2)
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: "magnifyingglass")
            }
        }
    }
}

struct ItemDetailView: View {
    let item: MenuItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.category.displayName.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.name)
                        .font(.largeTitle.weight(.semibold))
                    if let producer = item.producer {
                        Text(producer).font(.title3).foregroundStyle(.secondary)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    fact("Origin", item.originLine)
                    fact("Style", item.rules.style)
                    fact("Age", item.rules.ageYears.map(Format.age))
                    fact("ABV", item.rules.abv.map(Format.abv))
                    fact("Vintage", item.vintage.map { String($0) })
                    fact("Size", item.sizes.isEmpty ? nil : item.sizes.joined(separator: ", "))
                    fact("Bottles", "\(item.bottleCount)" + (item.openedCount > 0 ? " (\(item.openedCount) open)" : ""))
                    fact("Community", item.communityScore.map { Format.number($0) + " pts" })
                }

                if !item.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(.headline)
                        ForEach(item.notes, id: \.self) { Text($0) }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func fact(_ label: String, _ value: String?) -> some View {
        if let value {
            GridRow {
                Text(label).foregroundStyle(.secondary)
                Text(value)
            }
        }
    }
}

struct Badge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}

enum Format {
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func abv(_ value: Double) -> String { number(value) + "%" }

    static func age(_ years: Double) -> String { number(years) + " yr" }
}
