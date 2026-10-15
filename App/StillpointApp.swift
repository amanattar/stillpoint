import SwiftUI

@main
struct StillpointApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup("Stillpoint", id: "main") {
            RootView()
                .environment(model)
                .task { await DemoLaunch.seedIfRequested(model) }
        }
        .windowToolbarStyle(.unified)
    }
}
