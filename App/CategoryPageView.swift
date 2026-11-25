import CellarKit
import SwiftUI

/// A menu page: one category (or tonight's open bottles), in headed sections
/// laid out in two columns.
struct CategoryPageView: View {
    let title: String
    /// Label for the grouped ordering ("By region"), when the page offers a
    /// choice between that and A–Z.
    var groupedLabel: String? = nil
    /// Computes the sections from the model, so the page updates after a sync
    /// or a house change.
    let sections: @MainActor (CollectionModel, MenuOrdering) -> [MenuSection]

    @Environment(CollectionModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var openOnly = false
    @State private var selected: MenuItem?
    @State private var activeSection: String?
    @State private var ordering: MenuOrdering = .grouped

    /// Section buttons are shown only when there are a manageable number.
    private let maxSectionButtons = 24

    var body: some View {
        let all = sections(model, ordering)
        let visible = filtered(all)
        let total = all.reduce(0) { $0 + $1.items.count }

        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    header(total: total)
                    controls(all: all, proxy: proxy)
                    if visible.isEmpty {
                        Text(openOnly ? "Nothing open in this section." : "Nothing here yet.")
                            .font(Theme.italic(19))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 40)
                    }
                    ForEach(visible) { section in
                        VStack(alignment: .leading, spacing: 16) {
                            if visible.count > 1 || section.title != title {
                                SectionHeading(title: section.title)
                            }
                            MenuColumns(items: section.items, twoColumns: sizeClass != .compact) { item in
                                selected = item
                            }
                        }
                        .id(section.title)
                    }
                }
                .padding(.horizontal, sizeClass == .compact ? 24 : 64)
                .padding(.vertical, 24)
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.paper, for: .navigationBar)
        .sheet(item: $selected) { item in
            TastingCardView(item: item)
        }
    }

    private func filtered(_ sections: [MenuSection]) -> [MenuSection] {
        guard openOnly else { return sections }
        return sections.compactMap { section in
            let items = section.items.filter(\.isOpened)
            return items.isEmpty ? nil : MenuSection(title: section.title, items: items)
        }
    }

    private func header(total: Int) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(Theme.display(sizeClass == .compact ? 38 : 50))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(total == 1 ? "1 bottling" : "\(total) bottlings")
                .font(Theme.italic(19))
                .foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private func controls(all: [MenuSection], proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 10) {
            if all.count > 1 && all.count <= maxSectionButtons {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(all) { section in
                            sectionButton(section, proxy: proxy)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.vertical, 6)
                .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
            }
            HStack {
                if let groupedLabel {
                    Picker("Order", selection: $ordering) {
                        Text(groupedLabel).tag(MenuOrdering.grouped)
                        Text("A–Z").tag(MenuOrdering.alphabetical)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .onChange(of: ordering) { activeSection = nil }
                }
                Spacer()
                Toggle(isOn: $openOnly) {
                    CapsLabel("Open bottles only", color: Theme.muted, size: 13)
                }
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .fixedSize()
            }
        }
    }

    private func sectionButton(_ section: MenuSection, proxy: ScrollViewProxy) -> some View {
        let isActive = activeSection == section.title
        return Button {
            activeSection = section.title
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(section.title, anchor: .top)
            }
        } label: {
            HStack(spacing: 6) {
                Text(section.title.uppercased())
                    .font(Theme.body(14, .semibold))
                    .tracking(2.4)
                Text("\(section.items.count)")
                    .font(Theme.body(14))
                    .foregroundStyle(isActive ? Theme.paper.opacity(0.85) : Theme.muted)
            }
            .foregroundStyle(isActive ? Theme.paper : Theme.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background(isActive ? Theme.accent : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(section.title), \(section.items.count) bottlings")
    }
}
