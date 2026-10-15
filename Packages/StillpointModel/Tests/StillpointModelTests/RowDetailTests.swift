import Foundation
import GRDB
import Testing
@testable import StillpointModel

struct RowDetailTests {
    @Test func rowsCarryParentTitles() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Home").value
        let project = try await h.store.createProject(title: "Garden", areaID: area).value
        let inProject = try await h.store.createTodo(title: "Weed", in: .project(project)).value
        let inArea = try await h.store.createTodo(title: "Call", in: .area(area)).value
        let loose = try await h.store.createTodo(title: "Loose", in: .anytime).value
        try await h.store.schedule([inProject, inArea, loose, project], .today)

        let content = try await h.store.fetch(.today)
        #expect(content.parentTitles[inProject] == "Garden")
        #expect(content.parentTitles[inArea] == "Home")
        #expect(content.parentTitles[project] == "Home")
        #expect(content.parentTitles[loose] == nil)
    }

    @Test func rowsCarryChecklistAndProjectProgress() async throws {
        let h = try TestHarness()
        let todo = try await h.store.createTodo(title: "Pack", in: .anytime).value
        let first = try await h.store.addChecklistItem(to: todo, title: "Socks").value
        try await h.store.addChecklistItem(to: todo, title: "Shirts")
        try await h.store.updateChecklistItem(first) { $0.isDone = true }
        let project = try await h.store.createProject(title: "Trip").value
        let done = try await h.store.createTodo(in: .project(project)).value
        try await h.store.createTodo(in: .project(project))
        try await h.store.setStatus([done], .completed)

        let anytime = try await h.store.fetch(.anytime)
        #expect(anytime.checklists[todo] == ChecklistProgress(done: 1, total: 2))
        let projects = try await h.store.fetch(.allProjects)
        #expect(projects.projectProgress[project] == 0.5)
    }

    @Test func defaultCalendarFollowsSystemChanges() {
        let env = ModelEnvironment(deviceID: "d")
        #expect(env.calendar == .autoupdatingCurrent)
    }
}

extension RowDetailTests {
    @Test func rowsCarryTagTitles() async throws {
        let h = try TestHarness()
        let tag = try await h.store.createTag(title: "Errand").value
        let todo = try await h.store.createTodo(title: "Milk", in: .inbox).value
        try await h.store.setTags([todo], [tag])
        let content = try await h.store.fetch(.inbox)
        #expect(content.tagIDsByItem[todo] == [tag])
        #expect(content.tagTitles == [tag: "Errand"])
    }
}
