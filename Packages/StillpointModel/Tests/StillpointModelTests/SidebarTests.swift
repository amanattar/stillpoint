import Foundation
import GRDB
import Testing
@testable import StillpointModel

struct SidebarTests {
    @Test func countsOpenInboxAndTodayItems() async throws {
        let h = try TestHarness()
        try await h.store.createTodo(in: .inbox)
        let doneInbox = try await h.store.createTodo(in: .inbox).value
        try await h.store.setStatus([doneInbox], .completed)
        try await h.store.createTodo(in: .today)
        try await h.store.createTodo(in: .evening)
        let due = try await h.store.createTodo(in: .someday).value
        try await h.store.setDeadline([due], h.today)

        let sidebar = try await h.store.fetchSidebar()
        #expect(sidebar.inboxCount == 1)
        #expect(sidebar.todayCount == 3)
        #expect(sidebar.dueCount == 1)
    }

    @Test func groupsActiveProjectsUnderAreasWithProgress() async throws {
        let h = try TestHarness()
        let work = try await h.store.createArea(title: "Work").value
        let launch = try await h.store.createProject(title: "Launch", areaID: work).value
        try await h.store.createProject(title: "Loose")
        try await h.store.createProject(title: "Parked", areaID: work, someday: true)
        let a = try await h.store.createTodo(in: .project(launch)).value
        try await h.store.createTodo(in: .project(launch))
        try await h.store.createTodo(in: .project(launch))
        let canceled = try await h.store.createTodo(in: .project(launch)).value
        try await h.store.setStatus([a], .completed)
        try await h.store.setStatus([canceled], .canceled)

        let sidebar = try await h.store.fetchSidebar()
        #expect(sidebar.looseProjects.map(\.item.title) == ["Loose"])
        #expect(sidebar.areas.map(\.area.title) == ["Work"])
        #expect(sidebar.areas[0].projects.map(\.item.title) == ["Launch"])
        #expect(sidebar.areas[0].projects[0].progress == 0.5)
        #expect(sidebar.looseProjects[0].progress == 0)
    }

    @Test func emptyAreasStillAppear() async throws {
        let h = try TestHarness()
        try await h.store.createArea(title: "Empty")
        #expect(try await h.store.fetchSidebar().areas.map(\.projects.count) == [0])
    }

    @Test func observingSettingsEmitsChanges() async throws {
        let h = try TestHarness()
        var iterator = h.store.observeSettings().makeAsyncIterator()
        #expect(try await iterator.next()?.textSize == .medium)
        try await h.store.updateSettings { $0.textSize = .large }
        #expect(try await iterator.next()?.textSize == .large)
    }
}
