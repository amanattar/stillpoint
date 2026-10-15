import Foundation
import GRDB

extension Store {
    // MARK: Move

    /// Moves items to another container (the Move popover, or a drop on the sidebar).
    /// Today / This Evening / Someday are scheduling, so use `schedule` for those.
    /// With `after`/`before` (neighbour IDs in the target list) the items are placed between them.
    @discardableResult
    public func move(_ ids: [String], to destination: Destination, after afterID: String? = nil, before beforeID: String? = nil) async throws -> Committed<Void> {
        try await perform("Move") { tx in
            let items = try tx.items(ids)
            var moved: [Item] = []
            for original in items {
                var item = original
                switch (item.kind, destination) {
                case (.todo, .inbox):
                    item.projectID = nil; item.headingID = nil; item.areaID = nil
                    item.bucket = .inbox; item.startDay = nil; item.isEvening = false; item.reminderTime = nil
                case (.todo, .anytime):
                    item.projectID = nil; item.headingID = nil; item.areaID = nil
                    if item.bucket == .inbox { item.bucket = .anytime }
                case (.todo, .area(let areaID)):
                    item.projectID = nil; item.headingID = nil; item.areaID = areaID
                    if item.bucket == .inbox { item.bucket = .anytime }
                case (.todo, .project(let projectID)):
                    item.projectID = projectID; item.headingID = nil; item.areaID = nil
                    if item.bucket == .inbox { item.bucket = .anytime }
                case (.todo, .heading(let headingID)):
                    let heading = try tx.item(headingID)
                    item.projectID = heading.projectID; item.headingID = headingID; item.areaID = nil
                    if item.bucket == .inbox { item.bucket = .anytime }
                case (.project, .area(let areaID)):
                    item.areaID = areaID
                case (.project, .anytime):
                    item.areaID = nil
                case (.heading, .project(let projectID)):
                    item.projectID = projectID
                default:
                    throw ModelError.invalidMove("can't move a \(item.kind) to \(destination)")
                }
                moved.append(item)
            }

            let keys: [String]
            if afterID != nil || beforeID != nil {
                keys = try tx.keysBetween(moved.count, column: .sortKey, after: afterID, before: beforeID)
            } else if let first = moved.first {
                keys = try tx.newKeys(moved.count, in: Container.of(first))
            } else {
                keys = []
            }
            // Headings move first so their to-dos can follow them into the new project.
            for (index, var item) in moved.enumerated() {
                item.sortKey = keys[index]
                try tx.save(item)
                if item.kind == .heading {
                    for var child in try tx.liveItems(where: "headingID = ?", [item.id]) {
                        child.projectID = item.projectID
                        try tx.save(child)
                    }
                }
            }
        }
    }

    /// Reorders items within the list they're displayed in, between two neighbours.
    @discardableResult
    public func reorder(_ ids: [String], after afterID: String?, before beforeID: String?, column: OrderColumn = .sortKey) async throws -> Committed<Void> {
        try await perform("Move") { tx in
            let keys = try tx.keysBetween(ids.count, column: column, after: afterID, before: beforeID)
            for (index, var item) in try tx.items(ids).enumerated() {
                switch column {
                case .sortKey: item.sortKey = keys[index]
                case .todaySortKey: item.todaySortKey = keys[index]
                }
                try tx.save(item)
            }
        }
    }

    // MARK: Convert

    /// Turns a to-do into a project. Its checklist becomes to-dos in the new project.
    @discardableResult
    public func convertToProject(_ todoID: String) async throws -> Committed<Void> {
        try await perform("Convert to Project") { tx in
            var item = try tx.item(todoID)
            guard item.kind == .todo else { throw ModelError.invalidMove("only to-dos can be converted") }
            if let projectID = item.projectID {
                item.areaID = try tx.item(projectID).areaID
            }
            item.kind = .project
            item.projectID = nil
            item.headingID = nil
            if item.bucket == .inbox { item.bucket = .anytime }
            item.sortKey = try tx.newKeys(1, in: .projects(inArea: item.areaID))[0]
            try tx.save(item)

            let checklist = try ChecklistItem
                .filter(Column("itemID") == todoID && Column("deletedAt") == nil)
                .order(Column("sortKey"))
                .fetchAll(tx.db)
            let keys = try tx.newKeys(checklist.count, in: .project(todoID))
            for (index, entry) in checklist.enumerated() {
                var todo = Item(id: tx.newID(), kind: .todo, title: entry.title, createdAt: tx.now, bucket: .anytime, sortKey: keys[index])
                todo.projectID = todoID
                if entry.isDone {
                    todo.status = .completed
                    todo.stopDate = tx.now
                }
                try tx.save(todo)
                try tx.delete(entry)
            }
        }
    }

    /// Turns a heading into its own project (in the same area); its to-dos move with it.
    @discardableResult
    public func convertHeadingToProject(_ headingID: String) async throws -> Committed<String> {
        try await perform("Convert to Project") { tx in
            let heading = try tx.item(headingID)
            guard heading.kind == .heading, let parentID = heading.projectID else {
                throw ModelError.invalidMove("not a heading")
            }
            let parent = try tx.item(parentID)
            var project = Item(id: tx.newID(), kind: .project, title: heading.title, createdAt: tx.now, bucket: .anytime, sortKey: "")
            project.areaID = parent.areaID
            project.sortKey = try tx.newKeys(1, in: .projects(inArea: parent.areaID), after: parentID)[0]
            try tx.save(project)
            for var todo in try tx.liveItems(where: "headingID = ?", [headingID]) {
                todo.projectID = project.id
                todo.headingID = nil
                try tx.save(todo)
            }
            try tx.delete(heading)
            return project.id
        }
    }

    // MARK: Logbook

    /// "Log Completed": logs every completed or canceled item now.
    @discardableResult
    public func logCompleted() async throws -> Committed<Void> {
        try await perform("Log Completed") { tx in
            var settings = try Store.settings(in: tx.db, now: tx.now)
            settings.manualLogCutoff = tx.now
            try tx.save(settings)
        }
    }

    /// Changes when completed items are logged. Items already logged under the
    /// old policy stay logged: the cutoff advances to cover them first.
    @discardableResult
    public func setLogPolicy(_ policy: LogPolicy) async throws -> Committed<Void> {
        try await perform("Settings") { tx in
            var settings = try Store.settings(in: tx.db, now: tx.now)
            let alreadyLogged: Date? = switch settings.logPolicy {
            case .immediately: tx.now
            case .daily: tx.today.startOfDay(in: tx.env.calendar)
            case .manually: nil
            }
            if let alreadyLogged, alreadyLogged > (settings.manualLogCutoff ?? .distantPast) {
                settings.manualLogCutoff = alreadyLogged
            }
            settings.logPolicy = policy
            try tx.save(settings)
        }
    }
}
