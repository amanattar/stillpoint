import StillpointFeatures
import StillpointModel
import StillpointUI
import SwiftUI

/// The main pane for one list: header, sections and rows, updating live.
struct ListScreen: View {
    let store: Store
    let list: ListID
    @Environment(DayClock.self) private var clock
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @State private var content: ListContent?
    @State private var title = ""
    @State private var notes = ""
    @State private var showsLater = false
    @State private var showsLogged = false

    private struct Subscription: Equatable {
        let list: ListID
        let today: Day
    }

    var body: some View {
        ScrollView {
            ListBody(
                list: list, title: title, notes: notes, content: content,
                dates: DateText(today: clock.today, calendar: clock.calendar),
                showsLater: $showsLater, showsLogged: $showsLogged
            )
            .padding(.horizontal, metrics.contentInset)
            .padding(.bottom, metrics.contentInset)
        }
        .background(palette.background.color)
        .task(id: Subscription(list: list, today: clock.today)) {
            await observe()
        }
    }

    private func observe() async {
        showsLater = false
        showsLogged = false
        content = nil
        do {
            for try await update in store.observe(list) {
                (title, notes) = try await store.header(for: list)
                content = update
            }
        } catch {
            content = nil
        }
    }
}
