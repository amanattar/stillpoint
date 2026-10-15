import Foundation
import StillpointModel

/// Sample content for screenshots, manual testing and tests.
public enum DemoData {
    public static func seed(_ store: Store) async throws {
        let calendar = store.env.calendar
        let today = store.env.today
        let errand = try await store.createTag(title: "Errand").value
        let home = try await store.createArea(title: "Home").value
        let work = try await store.createArea(title: "Work").value

        try await store.createTodo(title: "Book dentist appointment", in: .inbox)
        try await store.createTodo(title: "Read article on habit tracking", in: .inbox)

        let launch = try await store.createProject(title: "Website relaunch", areaID: work).value
        try await store.setNotes(launch, "Ship the new site before the conference.")
        let design = try await store.createHeading(title: "Design", projectID: launch).value
        let copy = try await store.createTodo(title: "Write homepage copy", in: .project(launch)).value
        try await store.createTodo(title: "Choose typeface", in: .heading(design))
        let review = try await store.createTodo(title: "Review mockups with Sam", in: .heading(design)).value
        try await store.setStatus([review], .completed)
        try await store.schedule([copy], .today)
        try await store.setDeadline([launch], today.adding(days: 9, calendar: calendar))

        let garden = try await store.createProject(title: "Spring garden", areaID: home).value
        let seeds = try await store.createTodo(title: "Buy seeds", in: .project(garden)).value
        try await store.setTags([seeds], [errand])
        try await store.schedule([seeds], .today)
        try await store.createTodo(title: "Fix the fence", in: .project(garden))

        let groceries = try await store.createTodo(title: "Groceries", notes: "For the weekend", in: .area(home)).value
        try await store.addChecklistItem(to: groceries, title: "Milk")
        let eggs = try await store.addChecklistItem(to: groceries, title: "Eggs").value
        try await store.updateChecklistItem(eggs) { $0.isDone = true }
        try await store.setTags([groceries], [errand])
        try await store.schedule([groceries], .evening)

        let call = try await store.createTodo(title: "Call the bank", in: .anytime).value
        try await store.setDeadline([call], today)
        try await store.schedule([call], .today)

        let plan = try await store.createTodo(title: "Plan team offsite", in: .area(work)).value
        try await store.schedule([plan], .day(today.adding(days: 2, calendar: calendar)))
        let taxes = try await store.createTodo(title: "File taxes", in: .anytime).value
        try await store.schedule([taxes], .day(today.adding(days: 20, calendar: calendar)))
        try await store.createTodo(title: "Learn to play the piano", in: .someday)
    }
}
