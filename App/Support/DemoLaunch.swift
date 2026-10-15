import Foundation
import StillpointFeatures
import StillpointModel

/// Launch with `-dataFolderName Demo -seedDemoData YES` to fill a separate demo database;
/// it never touches the real one.
enum DemoLaunch {
    @MainActor
    static func seedIfRequested(_ model: AppModel, defaults: UserDefaults = .standard) async {
        guard defaults.bool(forKey: "seedDemoData"), defaults.string(forKey: "dataFolderName") != nil else { return }
        model.start()
        guard let store = model.store,
              let sidebar = try? await store.fetchSidebar(),
              sidebar.inboxCount == 0, sidebar.areas.isEmpty
        else { return }
        try? await DemoData.seed(store)
    }
}
