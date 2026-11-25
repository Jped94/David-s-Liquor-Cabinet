import CellarKit
import SwiftUI

/// One entry on a menu page:
///
///     Ardbeg 22 Year Old ·························· 56%
///     Manager's Choice Cask #2391 Sherry · Vintage 1976
///     ● OPEN   LAST BOTTLE
struct MenuEntryView: View {
    let item: MenuItem
    /// Adds the category and origin to the second line (used on the cover,
    /// where entries from every category are mixed).
    var showsCategory = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(item.menuTitle)
                        .font(Theme.body(21, .medium))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .layoutPriority(1)
                    DottedLeader()
                    if let abv = item.abv {
                        Text(Format.abv(abv))
                            .font(Theme.body(16))
                            .foregroundStyle(Theme.ink)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.italic(16))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                }
                if item.isOpened || item.bottleCount > 1 || item.isHidden {
                    HStack(spacing: 14) {
                        if item.isOpened { CapsLabel("● Open", size: 12) }
                        if item.bottleCount > 1 { CapsLabel("\(item.bottleCount) bottles", color: Theme.muted, size: 12) }
                        if item.isHidden { CapsLabel("Hidden from menu", color: Theme.muted, size: 12) }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the tasting card")
    }

    private var subtitle: String? {
        guard showsCategory else { return item.menuSubtitle }
        let place = [item.category.displayName, item.scotchRegion?.displayName ?? item.region]
            .compactMap { $0 }
            .joined(separator: ", ")
        return [item.menuSubtitle, place].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Lays entries out in two columns that read top to bottom, like a printed
/// menu, or one column when space is tight.
struct MenuColumns: View {
    let items: [MenuItem]
    let twoColumns: Bool
    let onSelect: (MenuItem) -> Void

    var body: some View {
        if twoColumns {
            let half = (items.count + 1) / 2
            HStack(alignment: .top, spacing: 64) {
                column(Array(items.prefix(half)))
                column(Array(items.dropFirst(half)))
            }
        } else {
            column(items)
        }
    }

    private func column(_ items: [MenuItem]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(items) { item in
                MenuEntryView(item: item) { onSelect(item) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
