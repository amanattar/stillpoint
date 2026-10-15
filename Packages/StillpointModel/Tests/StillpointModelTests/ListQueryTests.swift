import Foundation
import GRDB
import Testing
@testable import StillpointModel

struct ListQueryTests {
    func titles(_ content: ListContent) -> [String] {
        content.allItems.map(\.title)
    }

    @Test func inboxShowsOnlyInboxTodos() async throws {
        let h = try TestHarness()
        try await h.store.createTodo(title: "in", in: .inbox)
        try await h.store.createTodo(title: "out", in: .anytime)
        #expect(titles(try await h.store.fetch(.inbox)) == ["in"])
    }

    @Test func todayHasMainThenEveningAndOverdueStarts() async throws {
        let h = try TestHarness()
        try await h.store.createTodo(title: "a", in: .today)
        try await h.store.createTodo(title: "e", in: .evening)
        let old = try await h.store.createTodo(title: "old", in: .anytime).value
        try await h.store.schedule([old], .day(h.today.adding(days: 1, calendar: .fixture())))
        h.advance(days: 3) // "old" started two days ago and rolls into Today
        let content = try await h.store.fetch(.today)
        #expect(content.sections.map(\.kind) == [.plain, .evening])
        #expect(content.sections[0].items.map(\.title).sorted() == ["a", "old"])
        #expect(content.sections[1].items.map(\.title) == ["e"])
    }

    @Test func todayIncludesDueDeadlines() async throws {
        let h = try TestHarness()
        let id = try await h.store.createTodo(title: "due", in: .someday).value
        try await h.store.setDeadline([id], h.today)
        #expect(titles(try await h.store.fetch(.today)) == ["due"])
    }

    @Test func todayRollsOverAtLocalMidnight() async throws {
        // 23:30 in Kolkata on Oct 15 (18:00 UTC).
        let h = try TestHarness(now: Date(timeIntervalSince1970: 1_792_087_200), timeZone: "Asia/Kolkata")
        let id = try await h.store.createTodo(title: "tomorrow", in: .anytime).value
        try await h.store.schedule([id], .day(h.today.adding(days: 1, calendar: .fixture(timeZone: "Asia/Kolkata"))))
        #expect(titles(try await h.store.fetch(.today)).isEmpty)
        h.advance(seconds: 45 * 60) // 00:15 local
        #expect(titles(try await h.store.fetch(.today)) == ["tomorrow"])
    }

    @Test func todayCanGroupByProject() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let inProject = try await h.store.createTodo(title: "p1", in: .project(project)).value
        try await h.store.schedule([inProject], .today)
        try await h.store.createTodo(title: "loose", in: .today)
        try await h.store.updateSettings { $0.groupTodayByProject = true }
        let content = try await h.store.fetch(.today)
        #expect(content.sections.map(\.kind) == [.plain, .project(project)])
        #expect(content.sections[1].title == "P")
    }

    @Test func upcomingHasSevenDaysThenRestOfMonthThenMonths() async throws {
        let h = try TestHarness() // Thursday 2026-10-15
        let cal = Calendar.fixture()
        let a = try await h.store.createTodo(title: "in2days", in: .anytime).value
        try await h.store.schedule([a], .day(h.today.adding(days: 2, calendar: cal)))
        let b = try await h.store.createTodo(title: "oct28", in: .anytime).value
        try await h.store.schedule([b], .day(Day(year: 2026, month: 10, day: 28)))
        let c = try await h.store.createTodo(title: "dec", in: .anytime).value
        try await h.store.setDeadline([c], Day(year: 2026, month: 12, day: 3))

        let content = try await h.store.fetch(.upcoming)
        #expect(content.sections.count == 9)
        #expect(content.sections[1].kind == .day(Day(year: 2026, month: 10, day: 17)))
        #expect(content.sections[1].items.map(\.title) == ["in2days"])
        #expect(content.sections[7].kind == .restOfMonth(from: Day(year: 2026, month: 10, day: 23), through: Day(year: 2026, month: 10, day: 31)))
        #expect(content.sections[7].items.map(\.title) == ["oct28"])
        #expect(content.sections[8].kind == .month(Day(year: 2026, month: 12, day: 1)))
        #expect(content.sections[8].items.map(\.title) == ["dec"])
    }

    @Test func anytimeGroupsAndHidesSomedayAndFutureProjects() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Work").value
        let active = try await h.store.createProject(title: "Active", areaID: area).value
        let parked = try await h.store.createProject(title: "Parked", someday: true).value
        try await h.store.createTodo(title: "loose", in: .anytime)
        try await h.store.createTodo(title: "areaTodo", in: .area(area))
        try await h.store.createTodo(title: "activeTodo", in: .project(active))
        try await h.store.createTodo(title: "parkedTodo", in: .project(parked))
        let future = try await h.store.createTodo(title: "future", in: .anytime).value
        try await h.store.schedule([future], .day(h.today.adding(days: 2, calendar: .fixture())))

        let content = try await h.store.fetch(.anytime)
        #expect(content.sections.map(\.kind) == [.plain, .area(area), .project(active)])
        #expect(titles(content) == ["loose", "areaTodo", "activeTodo"])
    }

    @Test func somedayShowsSomedayProjectsNotTheirTodos() async throws {
        let h = try TestHarness()
        let parked = try await h.store.createProject(title: "Parked", someday: true).value
        try await h.store.createTodo(title: "inside", in: .project(parked))
        try await h.store.createTodo(title: "loose", in: .someday)
        #expect(Set(titles(try await h.store.fetch(.someday))) == ["Parked", "loose"])
    }

    @Test func deadlinesSortedByDay() async throws {
        let h = try TestHarness()
        let cal = Calendar.fixture()
        let late = try await h.store.createTodo(title: "late", in: .anytime).value
        let soon = try await h.store.createTodo(title: "soon", in: .anytime).value
        try await h.store.setDeadline([late], h.today.adding(days: 9, calendar: cal))
        try await h.store.setDeadline([soon], h.today.adding(days: 1, calendar: cal))
        #expect(titles(try await h.store.fetch(.deadlines)) == ["soon", "late"])
    }

    @Test func logPolicies() async throws {
        let h = try TestHarness()
        let id = try await h.store.createTodo(title: "done", in: .anytime).value
        try await h.store.setStatus([id], .completed)

        // Daily (default): stays in Anytime today, logged tomorrow.
        #expect(titles(try await h.store.fetch(.anytime)) == ["done"])
        #expect(titles(try await h.store.fetch(.logbook)).isEmpty)
        h.advance(days: 1)
        #expect(titles(try await h.store.fetch(.anytime)).isEmpty)
        #expect(titles(try await h.store.fetch(.logbook)) == ["done"])

        // Manually: stays until Log Completed.
        try await h.store.setLogPolicy(.manually)
        let manual = try await h.store.createTodo(title: "manual", in: .anytime).value
        try await h.store.setStatus([manual], .completed)
        h.advance(days: 5)
        #expect(titles(try await h.store.fetch(.anytime)) == ["manual"]) // "done" stays logged
        #expect(titles(try await h.store.fetch(.logbook)) == ["done"])
        try await h.store.logCompleted()
        #expect(titles(try await h.store.fetch(.anytime)).isEmpty)

        // Immediately.
        try await h.store.setLogPolicy(.immediately)
        let instant = try await h.store.createTodo(title: "instant", in: .anytime).value
        try await h.store.setStatus([instant], .completed)
        #expect(titles(try await h.store.fetch(.anytime)).isEmpty)
    }

    @Test func logbookNestsTodosUnderLoggedProject() async throws {
        let h = try TestHarness()
        try await h.store.setLogPolicy(.immediately)
        let project = try await h.store.createProject(title: "P").value
        try await h.store.createTodo(title: "child", in: .project(project))
        try await h.store.setStatus([project], .completed, openItems: .complete)
        #expect(titles(try await h.store.fetch(.logbook)) == ["P"])
    }

    @Test func trashShowsParentsNotTheirChildren() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        try await h.store.createTodo(title: "child", in: .project(project))
        let loose = try await h.store.createTodo(title: "loose", in: .inbox).value
        try await h.store.trash([project, loose])
        #expect(Set(titles(try await h.store.fetch(.trash))) == ["P", "loose"])
        #expect(titles(try await h.store.fetch(.inbox)).isEmpty)
    }

    @Test func projectHasHeadingsLaterAndLogged() async throws {
        let h = try TestHarness()
        try await h.store.setLogPolicy(.immediately)
        let project = try await h.store.createProject(title: "P").value
        try await h.store.createTodo(title: "loose", in: .project(project))
        let heading = try await h.store.createHeading(title: "H", projectID: project).value
        try await h.store.createTodo(title: "under", in: .heading(heading))
        let emptyHeading = try await h.store.createHeading(title: "Empty", projectID: project).value
        let later = try await h.store.createTodo(title: "later", in: .project(project)).value
        try await h.store.schedule([later], .someday)
        let done = try await h.store.createTodo(title: "done", in: .project(project)).value
        try await h.store.setStatus([done], .completed)

        let content = try await h.store.fetch(.project(project))
        #expect(content.sections.map(\.kind) == [.plain, .heading(heading), .heading(emptyHeading)])
        #expect(content.sections.map { $0.items.map(\.title) } == [["loose"], ["under"], []])
        #expect(content.later.map(\.title) == ["later"])
        #expect(content.logged.map(\.title) == ["done"])
    }

    @Test func areaListsTodosThenProjects() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Home").value
        try await h.store.createProject(title: "Garden", areaID: area)
        try await h.store.createTodo(title: "Call plumber", in: .area(area))
        let content = try await h.store.fetch(.area(area))
        #expect(content.sections.map { $0.items.map(\.title) } == [["Call plumber"], ["Garden"]])
    }

    @Test func allProjectsAndLaterProjects() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Work").value
        try await h.store.createProject(title: "Now", areaID: area)
        try await h.store.createProject(title: "Loose")
        try await h.store.createProject(title: "Parked", someday: true)
        let all = try await h.store.fetch(.allProjects)
        #expect(all.sections.map(\.kind) == [.plain, .area(area)])
        #expect(titles(all) == ["Loose", "Now"])
        #expect(titles(try await h.store.fetch(.laterProjects)) == ["Parked"])
    }

    @Test func tagFilterIncludesNestedTagsAndInheritsFromProjectAndArea() async throws {
        let h = try TestHarness()
        let errands = try await h.store.createTag(title: "Errands").value
        let shops = try await h.store.createTag(title: "Shops", parentID: errands).value
        let area = try await h.store.createArea(title: "Home").value
        try await h.store.setAreaTags(area, [errands])
        let direct = try await h.store.createTodo(title: "direct", in: .anytime).value
        try await h.store.setTags([direct], [shops])
        try await h.store.createTodo(title: "viaArea", in: .area(area))
        try await h.store.createTodo(title: "untagged", in: .anytime)

        let content = try await h.store.fetch(.anytime, tagFilter: errands)
        #expect(Set(titles(content)) == ["direct", "viaArea"])
        #expect(content.tagIDsByItem[direct] == [shops])
    }

    @Test func observationEmitsOnChange() async throws {
        let h = try TestHarness()
        var iterator = h.store.observe(.inbox).makeAsyncIterator()
        #expect(try await iterator.next()?.allItems.isEmpty == true)
        try await h.store.createTodo(title: "new", in: .inbox)
        #expect(try await iterator.next()?.allItems.map(\.title) == ["new"])
    }
}
