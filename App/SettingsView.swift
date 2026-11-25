import CellarKit
import SwiftUI

/// CellarTracker login, sync status, and collection info.
///
/// Not yet protected: the admin PIN / Face ID gate comes in phase 4.
struct SettingsView: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                cellarTrackerSection
                menuSection
                adminSection
                collectionSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var cellarTrackerSection: some View {
        Section {
            if model.hasCredentials {
                LabeledContent("Status", value: "Connected")
                LabeledContent("Last synced") {
                    Text(model.lastSynced.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                }
                Button {
                    Task { await model.syncNow() }
                } label: {
                    HStack {
                        Text("Sync now")
                        if model.isSyncing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(model.isSyncing)
                Button("Sign out", role: .destructive) { confirmingSignOut = true }
                    .confirmationDialog(
                        "Sign out of CellarTracker?",
                        isPresented: $confirmingSignOut,
                        titleVisibility: .visible
                    ) {
                        Button("Sign out", role: .destructive) { model.signOut() }
                    } message: {
                        Text("The menu will go back to sample data until you sign in again.")
                    }
            } else {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit(signIn)
                Button(action: signIn) {
                    HStack {
                        Text("Sign in and sync")
                        if model.isSyncing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(username.isEmpty || password.isEmpty || model.isSyncing)
            }
            if let error = model.syncError {
                Text(error).foregroundStyle(.red)
            }
        } header: {
            Text("CellarTracker")
        } footer: {
            Text("The login is stored only on this iPad, in the Keychain. CellarTracker has no read-only logins, so this is the account's full password.")
        }
    }

    private var menuSection: some View {
        @Bindable var model = model
        return Section {
            Picker("New arrivals", selection: $model.newArrivalDays) {
                ForEach(CollectionModel.newArrivalChoices, id: \.self) { days in
                    Text("Last \(days) days").tag(days)
                }
            }
        } header: {
            Text("Menu")
        } footer: {
            Text("Bottles count as new arrivals for this long after their CellarTracker purchase date.")
        }
    }

    private var adminSection: some View {
        @Bindable var model = model
        return Section {
            Toggle("Admin mode", isOn: $model.isAdmin)
        } header: {
            Text("Admin")
        } footer: {
            Text("Shows an Edit button on each bottle's card, and hidden bottles on the menu. Turns off when the app is closed.")
        }
    }

    private var collectionSection: some View {
        Section("Collection") {
            LabeledContent("Showing", value: model.isSampleData ? "Sample data" : "CellarTracker")
            LabeledContent("Bottles", value: "\(model.totalBottles)")
            LabeledContent("Products", value: "\(MenuBuilder.items(from: model.bottles).count)")
            if !model.unmappedLocations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Locations not assigned to a house")
                        .foregroundStyle(.orange)
                    Text(model.unmappedLocations.joined(separator: ", "))
                        .font(.footnote)
                    Text("Bottles here only show under \"All\". Assigning locations comes in a later update.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func signIn() {
        let credentials = CellarTrackerCredentials(
            username: username.trimmingCharacters(in: .whitespaces),
            password: password
        )
        Task {
            if await model.signIn(credentials) {
                password = ""
            }
        }
    }
}
