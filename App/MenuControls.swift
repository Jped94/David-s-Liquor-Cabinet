import CellarKit
import SwiftUI

// The controls shared by the cover and every menu page: house selector,
// search and settings.

/// "BEDFORD ⌄ 3 of 5 locations". Changing the house here changes it for the
/// whole app (and is remembered on this iPad).
struct HouseMenu: View {
    @Environment(CollectionModel.self) private var model
    @State private var choosingLocationsFor: House?

    var body: some View {
        @Bindable var model = model
        // The visible label is an ordinary view with the menu laid over it.
        // A Menu's own label shows new text in its old frame before resizing,
        // which clipped "Both houses" for a moment.
        label
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
            .sheet(item: $choosingLocationsFor) { house in
                LocationsSheet(house: house)
            }
    }

    private var label: some View {
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
        .fixedSize()
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
}

/// The gear that opens Settings.
struct SettingsButton: View {
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18))
                .foregroundStyle(Theme.muted.opacity(0.7))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Settings")
        .sheet(isPresented: $showing) {
            SettingsView()
        }
    }
}

/// The magnifying glass, as a label for a button or link.
struct SearchIcon: View {
    var isActive = false

    var body: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 19, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? Theme.accent : Theme.muted)
            .frame(width: 44, height: 44)
    }
}

/// A search field ruled like a line on the menu, with a close button.
struct InlineSearchField: View {
    @Binding var text: String
    var prompt: String
    var onClose: (() -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)
            TextField(prompt, text: $text)
                .font(Theme.body(22))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
            if let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.muted.opacity(0.7))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close search")
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 1) }
        .onAppear { focused = true }
    }
}
