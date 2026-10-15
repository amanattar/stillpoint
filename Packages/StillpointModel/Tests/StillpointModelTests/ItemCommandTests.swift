import Foundation
import GRDB
import Testing
@testable import StillpointModel

struct ItemCommandTests {
    @Test func createTodoInInboxAppendsInOrder() async throws {
        let h = try TestHarness()
        let a = try await h.store.createTodo(title: "A", in: .inbox).value
        let b = try await h.store.createTodo(title: "B", in: .inbox).value
        let c = try await h.store.createTodo(title: "C", in: .inbox, after: a).value
        let keys = try await [h.item(a), h.item(c), h.item(b)].map(\.sortKey)
        #expect(keys == keys.sorted())
        #expect(try await h.item(a).bucket == .inbox)
    }

    @Test func createInTodayAndEvening() async throws {
        let h = try TestHarness()
        let t = try await h.item(h.store.createTodo(title: "T", in: .today).value)
        let e = try await h.item(h.store.createTodo(title: "E", in: .evening).value)
        #expect(t.startDay == h.today && !t.isEvening && t.bucket == .anytime && t.todaySortKey != nil)
        #expect(e.startDay == h.today && e.isEvening)
    }

    @Test func createInHeadingUsesHeadingsProject() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let heading = try await h.store.createHeading(title: "H", projectID: project).value
        let todo = try await h.item(h.store.createTodo(title: "x", in: .heading(heading)).value)
        #expect(todo.projectID == project && todo.headingID == heading && todo.areaID == nil)
    }

    @Test func schedulingMovesOutOfInbox() async throws {
        let h = try TestHarness()
        let id = try await h.store.createTodo(title: "x", in: .inbox).value
        try await h.store.schedule([id], .day(h.today.adding(days: 3, calendar: .fixture())))
        var item = try await h.item(id)
        #expect(item.bucket == .anytime && item.startDay == h.today.adding(days: 3, calendar: .fixture()))

        try await h.store.schedule([id], .someday)
        item = try await h.item(id)
        #expect(item.bucket == .someday && item.startDay == nil)

        try await h.store.schedule([id], .clear)
        item = try await h.item(id)
        #expect(item.bucket == .anytime && item.startDay == nil)
    }

    @Test func pastDayMeansToday() async throws {
        let h = try TestHarness()
        let id = try await h.store.createTodo(in: .anytime).value
        try await h.store.schedule([id], .day(h.today.adding(days: -5, calendar: .fixture())))
        #expect(try await h.item(id).startDay == h.today)
    }

    @Test func shiftStartIsOneUndoStepAndNeverBeforeToday() async throws {
        let h = try TestHarness()
        let a = try await h.store.createTodo(in: .anytime).value
        let b = try await h.store.createTodo(in: .today).value
        let shift = try await h.store.shiftStart([a, b], byDays: 1)
        let tomorrow = h.today.adding(days: 1, calendar: .fixture())
        #expect(try await h.item(a).startDay == tomorrow)
        #expect(try await h.item(b).startDay == tomorrow)
        try await h.store.undo(shift.undo)
        #expect(try await h.item(a).startDay == nil)
        #expect(try await h.item(b).startDay == h.today)
        try await h.store.shiftStart([b], byDays: -3)
        #expect(try await h.item(b).startDay == h.today)
    }

    @Test func reminderSchedulesForTodayWhenUnscheduled() async throws {
        let h = try TestHarness()
        let id = try await h.store.createTodo(in: .inbox).value
        try await h.store.setReminder(id, minutes: 9 * 60)
        let item = try await h.item(id)
        #expect(item.reminderTime == 540 && item.startDay == h.today && item.bucket == .anytime)
    }

    @Test func completingProjectWithOpenTodosNeedsDecision() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let heading = try await h.store.createHeading(title: "H", projectID: project).value
        let todo = try await h.store.createTodo(in: .heading(heading)).value
        await #expect(throws: ModelError.projectHasOpenItems(count: 1)) {
            try await h.store.setStatus([project], .completed)
        }
        try await h.store.setStatus([project], .completed, openItems: .cancel)
        #expect(try await h.item(todo).status == .canceled)
        #expect(try await h.item(heading).status == .completed)
        #expect(try await h.item(project).stopDate == h.now)
    }

    @Test func archivingHeadingRequiresItsTodosDone() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let heading = try await h.store.createHeading(title: "H", projectID: project).value
        let todo = try await h.store.createTodo(in: .heading(heading)).value
        await #expect(throws: ModelError.headingHasOpenItems(count: 1)) {
            try await h.store.setStatus([heading], .completed)
        }
        try await h.store.setStatus([todo], .completed)
        try await h.store.setStatus([heading], .completed)
        #expect(try await h.item(heading).status == .completed)
    }

    @Test func trashAndPutBackProjectWithChildren() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let todo = try await h.store.createTodo(in: .project(project)).value
        try await h.store.trash([project])
        #expect(try await h.item(todo).trashedAt != nil)
        try await h.store.putBack([project])
        #expect(try await h.item(project).trashedAt == nil)
        #expect(try await h.item(todo).trashedAt == nil)
        #expect(try await h.item(todo).projectID == project)
    }

    @Test func puttingBackTodoWhoseProjectIsStillTrashedSendsItToInbox() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let todo = try await h.store.createTodo(in: .project(project)).value
        try await h.store.trash([project])
        try await h.store.putBack([todo])
        let item = try await h.item(todo)
        #expect(item.projectID == nil && item.bucket == .inbox && item.trashedAt == nil)
    }

    @Test func emptyTrashTombstones() async throws {
        let h = try TestHarness()
        let id = try await h.store.createTodo(in: .inbox).value
        _ = try await h.store.addChecklistItem(to: id, title: "step")
        try await h.store.trash([id])
        try await h.store.emptyTrash()
        #expect(try await h.item(id).deletedAt == h.now)
        let liveChecklist = try await h.store.read { db in
            try ChecklistItem.filter(Column("deletedAt") == nil).fetchCount(db)
        }
        #expect(liveChecklist == 0)
    }

    @Test func duplicateProjectCopiesHeadingsTodosChecklistAndTags() async throws {
        let h = try TestHarness()
        let tag = try await h.store.createTag(title: "Home").value
        let project = try await h.store.createProject(title: "P").value
        let heading = try await h.store.createHeading(title: "H", projectID: project).value
        let todo = try await h.store.createTodo(title: "x", in: .heading(heading)).value
        _ = try await h.store.addChecklistItem(to: todo, title: "step")
        try await h.store.setTags([todo], [tag])

        let copyID = try await h.store.duplicate([project]).value[0]
        let children = try await h.store.read { db in
            try Item.filter(Column("projectID") == copyID).fetchAll(db)
        }
        let copiedHeading = try #require(children.first { $0.kind == .heading })
        let copiedTodo = try #require(children.first { $0.kind == .todo })
        #expect(copiedTodo.headingID == copiedHeading.id)
        let details = try await h.store.read { db in
            (try ChecklistItem.filter(Column("itemID") == copiedTodo.id).fetchCount(db),
             try ItemTag.filter(Column("itemID") == copiedTodo.id).fetchCount(db))
        }
        #expect(details == (1, 1))
        #expect(try await h.item(copyID).sortKey > h.item(project).sortKey)
    }
}
