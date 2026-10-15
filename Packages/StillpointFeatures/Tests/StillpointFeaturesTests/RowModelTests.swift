import Foundation
import Testing
@testable import StillpointFeatures
import StillpointModel

struct RowModelTests {
    func todo(_ change: (inout Item) -> Void = { _ in }) -> Item {
        var item = Item(id: "t", kind: .todo, title: "Task", createdAt: fixedNow, bucket: .anytime, sortKey: "V")
        change(&item)
        return item
    }

    func content(parent: String? = nil) -> ListContent {
        ListContent(sections: [], later: [], logged: [], tagIDsByItem: ["t": ["g"]],
                    tagTitles: ["g": "Errand"], parentTitles: parent.map { ["t": $0] } ?? [:])
    }

    @Test func showsParentTitleOutsideTheParent() {
        let item = todo { $0.projectID = "p" }
        #expect(RowModel(item: item, in: .today, content: content(parent: "Garden"), dates: dates()).detail == "Garden")
        #expect(RowModel(item: item, in: .project("p"), content: content(parent: "Garden"), dates: dates()).detail == nil)
    }

    @Test func todayAndEveningMarksOnlyOutsideToday() {
        let today = todo { $0.startDay = Day(year: 2026, month: 10, day: 15) }
        #expect(RowModel(item: today, in: .anytime, content: content(), dates: dates()).showsTodayMark)
        #expect(!RowModel(item: today, in: .today, content: content(), dates: dates()).showsTodayMark)
        let evening = todo { $0.startDay = Day(year: 2026, month: 10, day: 15); $0.isEvening = true }
        let row = RowModel(item: evening, in: .anytime, content: content(), dates: dates())
        #expect(row.showsEveningMark && !row.showsTodayMark)
    }

    @Test func tagsDeadlineAndClosedState() {
        let item = todo { $0.deadlineDay = Day(year: 2026, month: 10, day: 15); $0.status = .completed }
        let row = RowModel(item: item, in: .anytime, content: content(), dates: dates())
        #expect(row.tags == ["Errand"])
        #expect(row.deadline?.text == "Today" && row.deadline?.isDue == true)
        #expect(row.isClosed)
        #expect(row.leading == .checkbox(.completed))
    }

    @Test func projectsShowProgress() {
        let project = Item(id: "p", kind: .project, title: "P", createdAt: fixedNow, bucket: .anytime, sortKey: "V")
        var listContent = content()
        listContent.projectProgress = ["p": 0.25]
        #expect(RowModel(item: project, in: .allProjects, content: listContent, dates: dates()).leading == .progress(0.25))
    }
}
