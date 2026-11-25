import SwiftUI

@main
struct DavidsLiquorCabinetApp: App {
    @State private var model = CollectionModel()

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
