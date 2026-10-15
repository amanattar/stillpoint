import StillpointFeatures
import StillpointModel
import StillpointUI
import SwiftUI

/// One Stillpoint window: sidebar plus the selected list. Each window keeps its own selection.
struct MainWindow: View {
    let store: Store
    @SceneStorage("selectedList") private var storedSelection = ListID.inbox.storageKey
    @State private var selection: ListID? = .inbox

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } detail: {
            ListScreen(store: store, list: selection ?? .inbox)
        }
        .toolbar(removing: .title)
        .onAppear {
            selection = ListID(storageKey: storedSelection) ?? .inbox
        }
        .onChange(of: selection) { _, newValue in
            storedSelection = (newValue ?? .inbox).storageKey
        }
    }
}
