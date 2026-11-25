import SwiftUI

@main
struct DavidsLiquorCabinetApp: App {
    @State private var model = CollectionModel()

    var body: some Scene {
        WindowGroup {
            MenuRootView()
                .environment(model)
        }
    }
}
