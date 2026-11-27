import CellarKit
import SwiftUI

/// Admin form for editing how one bottle appears on the menu.
///
/// Fields start with what the menu currently shows. Anything left the same
/// as the CellarTracker-derived value isn't stored as an edit, so later
/// CellarTracker changes still come through for it.
struct EditItemView: View {
    let item: MenuItem
    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var subtitle: String
    @State private var category: SpiritCategory
    @State private var scotchRegion: ScotchRegion?
    @State private var scotchStyle: ScotchStyle
    @State private var abv: String
    @State private var age: String
    @State private var style: String
    @State private var description: String
    @State private var isHidden: Bool
    @State private var errorMessage: String?
    @State private var confirmingReset = false

    /// The item as CellarTracker and the rules alone would show it.
    private let base: MenuItem

    init(item: MenuItem) {
        self.item = item
        var base = item
        base.override = nil
        self.base = base

        _title = State(initialValue: item.menuTitle)
        _subtitle = State(initialValue: item.menuSubtitle ?? "")
        _category = State(initialValue: item.category)
        _scotchRegion = State(initialValue: item.override?.scotchRegion ?? item.rules.scotchRegion)
        _scotchStyle = State(initialValue: item.scotchStyle ?? .singleMalt)
        _abv = State(initialValue: item.abv.map(Format.number) ?? "")
        _age = State(initialValue: item.ageYears.map(Format.number) ?? "")
        _style = State(initialValue: item.style ?? "")
        _description = State(initialValue: item.itemDescription ?? "")
        _isHidden = State(initialValue: item.isHidden)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("CellarTracker name") {
                        Text(item.name).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                }

                Section("Menu text") {
                    TextField("Title", text: $title, prompt: Text(base.menuTitle))
                    TextField("Second line", text: $subtitle, prompt: Text("None"), axis: .vertical)
                }

                Section("Details") {
                    Picker("Category", selection: $category) {
                        ForEach(SpiritCategory.allCases) { category in
                            Text(category == .americanWhiskey ? "Other American Whiskey" : category.displayName)
                                .tag(category)
                        }
                    }
                    if category == .scotch {
                        Picker("Scotch style", selection: $scotchStyle) {
                            ForEach(ScotchStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        Picker("Region", selection: $scotchRegion) {
                            Text("Not set").tag(ScotchRegion?.none)
                            ForEach(ScotchRegion.allCases) { region in
                                Text(region.displayName).tag(ScotchRegion?.some(region))
                            }
                        }
                    }
                    LabeledContent("ABV %") {
                        TextField("ABV", text: $abv, prompt: Text("Unknown"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Age (years)") {
                        TextField("Age", text: $age, prompt: Text("No age statement"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Style", text: $style, prompt: Text("e.g. Single Malt Scotch Whisky"))
                }

                Section {
                    TextField("Description", text: $description, prompt: Text("Tasting notes or a few words for guests"), axis: .vertical)
                        .lineLimit(4...10)
                } header: {
                    Text("Description")
                } footer: {
                    Text("Shown on the tasting card.")
                }

                Section {
                    Toggle("Hide from the menu", isOn: $isHidden)
                } footer: {
                    Text("Hidden bottles still show in admin mode, marked as hidden.")
                }

                Section {
                    Button("Reset to CellarTracker values", role: .destructive) {
                        confirmingReset = true
                    }
                    .disabled(item.override == nil)
                } footer: {
                    Text("Edits are saved on this iPad only. They never change CellarTracker, and they're kept when the collection syncs.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit Bottle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .confirmationDialog("Remove all edits to this bottle?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { store(nil) }
            }
        }
    }

    private func save() {
        guard let abvValue = parse(abv), let ageValue = parse(age) else {
            errorMessage = "ABV and age need to be numbers, e.g. 46 or 12.5."
            return
        }

        let override = ItemOverride(
            title: changed(title.trimmingCharacters(in: .whitespacesAndNewlines), from: base.menuTitle, allowEmpty: false),
            subtitle: changed(subtitle.trimmingCharacters(in: .whitespacesAndNewlines), from: base.menuSubtitle ?? "", allowEmpty: true),
            category: category == base.category ? nil : category,
            scotchRegion: category == .scotch && scotchRegion != base.rules.scotchRegion ? scotchRegion : nil,
            scotchStyle: category == .scotch && scotchStyle != (base.rules.scotchStyle ?? .singleMalt) ? scotchStyle : nil,
            abv: abvValue == base.abv ? nil : abvValue,
            ageYears: ageValue == base.ageYears ? nil : ageValue,
            style: changed(style.trimmingCharacters(in: .whitespacesAndNewlines), from: base.style ?? "", allowEmpty: true),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
            isHidden: isHidden
        )
        store(override)
    }

    private func store(_ override: ItemOverride?) {
        do {
            try model.saveOverride(override, for: item.id)
            dismiss()
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }

    /// The new text, or `nil` when it matches the original (no edit needed).
    private func changed(_ text: String, from original: String, allowEmpty: Bool) -> String? {
        if text == original { return nil }
        if text.isEmpty && !allowEmpty { return nil }
        return text
    }

    /// Parses "46", "46.5" or "46%". Empty is valid (no value) and returns
    /// `.some(nil)`; anything else that isn't a number returns `nil`.
    private func parse(_ text: String) -> Double?? {
        let cleaned = text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { return .some(nil) }
        guard let value = Double(cleaned.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return .some(value)
    }
}
