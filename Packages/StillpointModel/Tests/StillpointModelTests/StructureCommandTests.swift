import Foundation
import GRDB
import Testing
@testable import StillpointModel

struct StructureCommandTests {
    @Test func moveTodoBetweenContainers() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Home").value
        let project = try await h.store.createProject(title: "P", areaID: area).value
        let heading = try await h.store.createHeading(title: "H", projectID: project).value
        let id = try await h.store.createTodo(title: "x", in: .inbox).value

        try await h.store.move([id], to: .heading(heading))
        var item = try await h.item(id)
        #expect(item.projectID == project && item.headingID == heading && item.areaID == nil && item.bucket == .anytime)

        try await h.store.move([id], to: .area(area))
        item = try await h.item(id)
        #expect(item.projectID == nil && item.headingID == nil && item.areaID == area)

        try await h.store.schedule([id], .today)
        try await h.store.move([id], to: .inbox)
        item = try await h.item(id)
        #expect(item.bucket == .inbox && item.areaID == nil && item.startDay == nil)
    }

    @Test func movingHeadingTakesItsTodos() async throws {
        let h = try TestHarness()
        let p1 = try await h.store.createProject(title: "P1").value
        let p2 = try await h.store.createProject(title: "P2").value
        let heading = try await h.store.createHeading(title: "H", projectID: p1).value
        let todo = try await h.store.createTodo(in: .heading(heading)).value
        try await h.store.move([heading], to: .project(p2))
        #expect(try await h.item(heading).projectID == p2)
        #expect(try await h.item(todo).projectID == p2)
        #expect(try await h.item(todo).headingID == heading)
    }

    @Test func invalidMovesAreRejected() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let other = try await h.store.createProject(title: "Q").value
        await #expect(throws: ModelError.self) { try await h.store.move([project], to: .project(other)) }
        await #expect(throws: ModelError.self) { try await h.store.move([project], to: .inbox) }
        let todo = try await h.store.createTodo(in: .inbox).value
        await #expect(throws: ModelError.self) { try await h.store.move([todo], to: .today) }
    }

    @Test func moveWithNeighboursPlacesBetweenThem() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let a = try await h.store.createTodo(title: "a", in: .project(project)).value
        let b = try await h.store.createTodo(title: "b", in: .project(project)).value
        let x = try await h.store.createTodo(title: "x", in: .inbox).value
        try await h.store.move([x], to: .project(project), after: a, before: b)
        #expect(try await h.titles(where: "projectID = ?", [project]) == ["a", "x", "b"])
    }

    @Test func reorderBetweenNeighboursAndRejectsOutOfOrder() async throws {
        let h = try TestHarness()
        let a = try await h.store.createTodo(title: "a", in: .inbox).value
        let b = try await h.store.createTodo(title: "b", in: .inbox).value
        let c = try await h.store.createTodo(title: "c", in: .inbox).value
        try await h.store.reorder([c], after: nil, before: a)
        #expect(try await h.titles(where: "bucket = 0") == ["c", "a", "b"])
        await #expect(throws: ModelError.invalidMove("neighbours out of order")) {
            try await h.store.reorder([a], after: b, before: c)
        }
    }

    @Test func reorderToday() async throws {
        let h = try TestHarness()
        let a = try await h.store.createTodo(title: "a", in: .today).value
        let b = try await h.store.createTodo(title: "b", in: .today).value
        try await h.store.reorder([b], after: nil, before: a, column: .todaySortKey)
        #expect(try await h.titles(where: "todaySortKey IS NOT NULL", order: "todaySortKey") == ["b", "a"])
    }

    @Test func convertTodoToProjectTurnsChecklistIntoTodos() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Home").value
        let parent = try await h.store.createProject(title: "Parent", areaID: area).value
        let id = try await h.store.createTodo(title: "Big", in: .project(parent)).value
        _ = try await h.store.addChecklistItem(to: id, title: "one")
        let two = try await h.store.addChecklistItem(to: id, title: "two").value
        try await h.store.updateChecklistItem(two) { $0.isDone = true }

        try await h.store.convertToProject(id)
        let project = try await h.item(id)
        #expect(project.kind == .project && project.projectID == nil && project.areaID == area)
        let todos = try await h.store.read { db in
            try Item.filter(Column("projectID") == id).order(Column("sortKey")).fetchAll(db)
        }
        #expect(todos.map(\.title) == ["one", "two"])
        #expect(todos.map(\.status) == [.open, .completed])
        let liveChecklist = try await h.store.read { db in try ChecklistItem.filter(Column("deletedAt") == nil).fetchCount(db) }
        #expect(liveChecklist == 0)
    }

    @Test func convertHeadingToProject() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Work").value
        let parent = try await h.store.createProject(title: "Parent", areaID: area).value
        let heading = try await h.store.createHeading(title: "Phase 2", projectID: parent).value
        let todo = try await h.store.createTodo(title: "x", in: .heading(heading)).value
        let newProject = try await h.store.convertHeadingToProject(heading).value
        #expect(try await h.item(newProject).title == "Phase 2")
        #expect(try await h.item(newProject).areaID == area)
        #expect(try await h.item(todo).projectID == newProject)
        #expect(try await h.item(todo).headingID == nil)
        #expect(try await h.item(heading).deletedAt != nil)
    }

    @Test func logPolicyCanOnlyChangeThroughSetLogPolicy() async throws {
        let h = try TestHarness()
        await #expect(throws: ModelError.self) {
            try await h.store.updateSettings { $0.logPolicy = .manually }
        }
        try await h.store.updateSettings { $0.groupTodayByProject = true }
        try await h.store.setLogPolicy(.manually)
        let settings = try await h.store.read { db in try Store.settings(in: db, now: Date()) }
        #expect(settings.logPolicy == .manually && settings.groupTodayByProject)
    }
}
