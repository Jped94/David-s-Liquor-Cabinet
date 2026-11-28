import CellarKit
import SwiftUI

/// Search across the current house's menu.
struct SearchPage: View {
    @Environment(CollectionModel.self) private var model
    @State private var width: CGFloat = Layout.twoColumnMinWidth
    private var isWide: Bool { width >= Layout.twoColumnMinWidth }
    @State private var query = ""
    @State private var selected: MenuItem?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let results = query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : model.search(query)

        ScrollView {
            VStack(spacing: 24) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.muted)
                    TextField("Search by name, distillery, region or style", text: $query)
                        .font(Theme.body(24))
                        .foregroundStyle(Theme.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($fieldFocused)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 1) }

                if query.isEmpty {
                    Text("Try “Islay”, “sherry”, “Van Winkle” or “cask strength”.")
                        .font(Theme.italic(18))
                        .foregroundStyle(Theme.muted)
                } else if results.isEmpty {
                    Text("Nothing matches “\(query)”.")
                        .font(Theme.italic(18))
                        .foregroundStyle(Theme.muted)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        CapsLabel(results.count == 1 ? "1 result" : "\(results.count) results", color: Theme.muted)
                        MenuColumns(items: results, twoColumns: isWide) { selected = $0 }
                    }
                }
            }
            .padding(.horizontal, !isWide ? 24 : 64)
            .padding(.vertical, 24)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper.ignoresSafeArea())
        .readWidth($width)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.paper, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                HouseMenu()
                SettingsButton()
            }
        }
        .onAppear { fieldFocused = true }
        .sheet(item: $selected) { item in
            TastingCardView(item: item)
        }
    }
}
