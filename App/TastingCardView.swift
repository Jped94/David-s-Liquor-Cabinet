import CellarKit
import SwiftUI

/// The card shown when a guest taps a bottle.
struct TastingCardView: View {
    let item: MenuItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 10) {
                    CapsLabel(kicker, size: 13)
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
                }

                stats

                VStack(spacing: 14) {
                    if let style = item.rules.style {
                        detailRow("Style", style)
                    }
                    if let origin = origin {
                        detailRow("Origin", origin)
                    }
                    if !item.sizes.isEmpty {
                        detailRow("Bottle", item.sizes.joined(separator: ", "))
                    }
                    if let score = item.communityScore {
                        detailRow("Community score", Format.number(score) + " points")
                    }
                    ForEach(item.notes, id: \.self) { note in
                        Text(note)
                            .font(Theme.italic(18))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
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
    }

    /// "SCOTCH · CAMPBELTOWN"
    private var kicker: String {
        let place = item.rules.scotchRegion?.displayName ?? item.region ?? item.country
        return [item.category.displayName, place].compactMap { $0 }.joined(separator: " · ")
    }

    private var origin: String? {
        let parts = [item.region, item.country].compactMap { $0 }
        var unique: [String] = []
        for part in parts where !unique.contains(part) { unique.append(part) }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }

    private var stats: some View {
        let candidates: [(String, String)?] = [
            item.rules.ageYears.map { ("Age", Format.age($0)) },
            item.rules.abv.map { ("Strength", Format.abv($0)) },
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
