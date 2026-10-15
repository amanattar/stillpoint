import StillpointFeatures
import StillpointModel
import StillpointUI
import SwiftUI

/// The glass sidebar: fixed lists, then projects and areas.
struct SidebarView: View {
    let store: Store
    @Binding var selection: ListID?
    @Environment(DayClock.self) private var clock
    @State private var content: SidebarContent?

    var body: some View {
        SidebarList(content: content, selection: $selection)
            .task(id: clock.today) {
                do {
                    for try await update in store.observeSidebar() {
                        content = update
                    }
                } catch {}
            }
    }
}
