import CellarKit
import SwiftUI

/// Server status, admin unlock, CellarTracker sync and collection info.
struct SettingsView: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var passcode = ""
    @State private var unlockError: String?
    @State private var isUnlocking = false
    @State private var username = ""
    @State private var password = ""
    @State private var confirmingSignOut = false
    @State private var uploadMessage: String?
    @State private var isUploading = false

    var body: some View {
        NavigationStack {
            Form {
                menuSection
                adminSection
                if model.isAdmin {
                    cellarTrackerSection
                    if !model.localEdits.isEmpty { localEditsSection }
                }
                collectionSection
            }
            .navigationTitle("Settings")
            .onAppear { model.isSettingsOpen = true }
            .onDisappear { model.isSettingsOpen = false }
            .sheet(item: Binding(
                get: { model.syncReport },
                set: { model.syncReport = $0 }
            )) { report in
                SyncReportView(report: report)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Sections

    private var menuSection: some View {
        Section {
            LabeledContent("Server", value: model.isServerConfigured ? "Connected" : "Not set up in this build")
            LabeledContent("Collection synced") {
                Text(model.lastSynced.map { $0.formatted(.relative(presentation: .named)) } ?? "Not yet")
            }
            Button {
                Task { await model.sync() }
            } label: {
                HStack {
                    Text("Sync now")
                    if model.isBusy {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!model.isServerConfigured || model.isBusy)
            if let error = model.syncError {
                Text(error).foregroundStyle(.red)
            }
        } header: {
            Text("Menu")
        } footer: {
            Text(model.isAdmin && model.hasCredentials
                ? "Downloads the collection from CellarTracker and updates every iPad and the web page."
                : "Every iPad shows the same collection and edits, and checks for changes whenever the app opens. In admin mode with a CellarTracker login, Sync also downloads from CellarTracker.")
        }
    }

    private var adminSection: some View {
        Section {
            if model.isAdmin {
                LabeledContent("Admin mode", value: "On")
                Button("Lock admin mode") { model.lockAdmin() }
            } else {
                SecureField("Admin passcode", text: $passcode)
                    .textContentType(.password)
                    .onSubmit(unlock)
                Button(action: unlock) {
                    HStack {
                        Text("Unlock admin mode")
                        if isUnlocking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(passcode.isEmpty || isUnlocking)
                if let unlockError {
                    Text(unlockError).foregroundStyle(.red)
                }
            }
        } header: {
            Text("Admin")
        } footer: {
            Text("Admin mode lets you sync from CellarTracker, edit bottles and see hidden ones. It locks again when the app is closed.")
        }
    }

    private var cellarTrackerSection: some View {
        Section {
            if model.hasCredentials {
                LabeledContent("Login", value: "Saved on this iPad")
                Button("Forget CellarTracker login", role: .destructive) { confirmingSignOut = true }
                    .confirmationDialog(
                        "Forget the CellarTracker login on this iPad?",
                        isPresented: $confirmingSignOut,
                        titleVisibility: .visible
                    ) {
                        Button("Forget login", role: .destructive) { model.signOut() }
                    } message: {
                        Text("The menu stays as it is. You'll need the login again to sync from this iPad.")
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
        } header: {
            Text("CellarTracker")
        } footer: {
            Text("The login is saved only on this iPad, in the Keychain. For each sync it's passed to the cabinet server, used once to download the collection, and not stored there.")
        }
    }

    private var localEditsSection: some View {
        Section {
            Button {
                uploadEdits()
            } label: {
                HStack {
                    Text(model.localEdits.count == 1 ? "Upload 1 edit" : "Upload \(model.localEdits.count) edits")
                    if isUploading {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isUploading)
            if let uploadMessage {
                Text(uploadMessage).foregroundStyle(.secondary)
            }
        } header: {
            Text("Edits saved on this iPad")
        } footer: {
            Text("Edits made before the menu was shared are only on this iPad. Upload them once so every iPad gets them.")
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
                    Text("Bottles here only show under \"Both houses\".")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Actions

    private func unlock() {
        guard !passcode.isEmpty else { return }
        isUnlocking = true
        unlockError = nil
        Task {
            unlockError = await model.unlockAdmin(passcode: passcode)
            isUnlocking = false
            if unlockError == nil { passcode = "" }
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

    private func uploadEdits() {
        isUploading = true
        uploadMessage = nil
        Task {
            do {
                let count = try await model.uploadLocalEdits()
                uploadMessage = count == 1 ? "Uploaded 1 edit." : "Uploaded \(count) edits."
            } catch {
                uploadMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isUploading = false
        }
    }
}
