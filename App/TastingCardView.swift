import CellarKit
import SwiftUI

/// The card shown when someone taps a bottle.
struct TastingCardView: View {
    /// The item as it was when tapped. The card shows the model's current
    /// version of it, so edits appear immediately.
    let item: MenuItem
    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    private var current: MenuItem { model.item(id: item.id) ?? item }

    var body: some View {
        let item = current
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 10) {
                    CapsLabel(kicker(item), size: 13)
                    Text(item.menuTitle)
                        .font(Theme.display(42))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    if let subtitle = item.menuSubtitle {
                        Text(subtitle)
                            .font(Theme.italic(21))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    if item.isHidden {
                        CapsLabel("Hidden from the guest menu", color: Theme.muted, size: 12)
                    }
                }

                stats(item)

                if let description = item.itemDescription {
                    Text(description)
                        .font(Theme.italic(21))
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                VStack(spacing: 14) {
                    if let style = item.style {
                        detailRow("Style", style)
                    }
                    if let origin = origin(item) {
                        detailRow("Origin", origin)
                    }
                    if !item.sizes.isEmpty {
                        detailRow("Bottle", item.sizes.joined(separator: ", "))
                    }
                    if let score = item.communityScore {
                        detailRow("Community score", Format.number(score) + " points")
                    }
                }

                whereSection(item)

                if !item.notes.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(item.notes, id: \.self) { note in
                            Text(note)
                                .font(Theme.italic(18))
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center)
                        }
                    }
                }

                if model.isAdmin {
                    Button {
                        editing = true
                    } label: {
                        CapsLabel("Edit", color: Theme.paper, size: 14)
                            .padding(.horizontal, 28)
                            .frame(minHeight: 44)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 52)
            .padding(.bottom, 44)
        }
        .background(Theme.card.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            .padding(10)
        }
        .presentationBackground(Theme.card)
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $editing) {
            EditItemView(item: item)
        }
    }

    /// "SCOTCH · CAMPBELTOWN"
    private func kicker(_ item: MenuItem) -> String {
        let place = item.scotchRegion?.displayName ?? item.region ?? item.country
        return [item.category.displayName, place].compactMap { $0 }.joined(separator: " · ")
    }

    private func origin(_ item: MenuItem) -> String? {
        let parts = [item.region, item.country].compactMap { $0 }
        var unique: [String] = []
        for part in parts where !unique.contains(part) { unique.append(part) }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }

    @ViewBuilder
    private func whereSection(_ item: MenuItem) -> some View {
        let placements = item.placements(mapping: model.mapping)
        if !placements.isEmpty {
            VStack(spacing: 10) {
                CapsLabel("Where", color: Theme.muted, size: 12)
                ForEach(placements, id: \.self) { placement in
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(placement.description.isEmpty ? "No location set" : placement.description)
                            .font(Theme.body(18, .medium))
                            .foregroundStyle(Theme.ink)
                        DottedLeader()
                        Text(placement.count == 1 ? "1 bottle" : "\(placement.count) bottles")
                            .font(Theme.body(17))
                            .foregroundStyle(Theme.muted)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 4)
        }
    }

    private func stats(_ item: MenuItem) -> some View {
        let candidates: [(String, String)?] = [
            item.ageYears.map { ("Age", Format.age($0)) },
            item.abv.map { ("Strength", Format.abv($0)) },
            ("Bottles", "\(item.bottleCount)"),
            ("Status", item.isOpened ? "Open" : "Sealed"),
        ]
        let cells = candidates.compactMap { $0 }

        return HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                VStack(spacing: 4) {
                    CapsLabel(cell.0, color: Theme.muted, size: 12)
                    Text(cell.1)
                        .font(Theme.display(24, bold: false))
                        .foregroundStyle(cell.0 == "Status" && item.isOpened ? Theme.accent : Theme.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .overlay(alignment: .leading) {
                    if index > 0 { Rectangle().fill(Theme.rule.opacity(0.7)).frame(width: 1) }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(label)
                .font(Theme.body(18))
                .foregroundStyle(Theme.muted)
            DottedLeader()
            Text(value)
                .font(Theme.body(18, .medium))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
