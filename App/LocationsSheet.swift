import CellarKit
import SwiftUI

/// Lets the owner choose which of a house's CellarTracker locations the menu
/// shows. The choice is remembered on this iPad.
struct LocationsSheet: View {
    let house: House
    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let locations = model.locations(for: house)
        NavigationStack {
            List {
                Section {
                    ForEach(locations, id: \.self) { location in
                        Toggle(isOn: Binding(
                            get: { model.isLocationShown(location) },
                            set: { model.setLocation(location, shown: $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(location)
                                Text(bottleCountText(location))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(Theme.accent)
                    }
                } footer: {
                    Text("Open bottles usually have their own location (like “Open in Owl's perch”). Keep those on to see them under Tonight's Pours.")
                }

                Section {
                    Button("Show all locations") {
                        for location in locations { model.setLocation(location, shown: true) }
                    }
                    .disabled(locations.allSatisfy(model.isLocationShown))
                }
            }
            .navigationTitle("\(house.name) Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func bottleCountText(_ location: String) -> String {
        let key = HouseMapping.normalize(location)
        let count = model.bottles
            .filter { !$0.isPending && $0.location.map(HouseMapping.normalize) == key }
            .reduce(0) { $0 + $1.quantity }
        return count == 1 ? "1 bottle" : "\(count) bottles"
    }
}
