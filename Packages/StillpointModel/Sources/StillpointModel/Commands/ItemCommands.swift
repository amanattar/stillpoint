import Foundation
import GRDB

extension Store {
    // MARK: Create

    /// Creates a to-do in `destination`, at the end or right after `afterID`.
    @discardableResult
    public func createTodo(
        title: String = "", notes: String = "", in destination: Destination, after afterID: String? = nil
    ) async throws -> Committed<String> {
        try await perform("New To-Do") { tx in
            var item = Item(id: tx.newID(), kind: .todo, title: title, createdAt: tx.now, sortKey: "")
            item.notes = notes
            let container: Container
            switch destination {
            case .inbox:
                item.bucket = .inbox
                container = .inbox
            case .anytime, .today, .evening:
                item.bucket = .anytime
                container = .noParent(.anytime)
            case .someday:
                item.bucket = .someday
                container = .noParent(.someday)
            case .area(let areaID):
                item.bucket = .anytime
                item.areaID = areaID
                container = .areaTodos(areaID)
            case .project(let projectID):
                item.bucket = .anytime
                item.projectID = projectID
                container = .project(projectID)
            case .heading(let headingID):
                let heading = try tx.item(headingID)
                item.bucket = .anytime
                item.projectID = heading.projectID
                item.headingID = headingID
                container = .project(heading.projectID ?? "")
            }
            if destination == .today || destination == .evening {
                item.startDay = tx.today
                item.isEvening = destination == .evening
                item.todaySortKey = try tx.newKeys(1, column: .todaySortKey, in: .today, after: afterID)[0]
                item.sortKey = try tx.newKeys(1, in: container)[0]
            } else {
                item.sortKey = try tx.newKeys(1, in: container, after: afterID)[0]
            }
            try tx.save(item)
            return item.id
        }
    }

    @discardableResult
    public func createProject(title: String, areaID: String? = nil, someday: Bool = false) async throws -> Committed<String> {
        try await perform("New Project") { tx in
            var project = Item(id: tx.newID(), kind: .project, title: title, createdAt: tx.now, bucket: someday ? .someday : .anytime, sortKey: "")
            project.areaID = areaID
            project.sortKey = try tx.newKeys(1, in: .projects(inArea: areaID))[0]
            try tx.save(project)
            return project.id
        }
    }

    /// Creates a heading at the end of a project, or after `afterID` (an item in that project).
    @discardableResult
    public func createHeading(title: String, projectID: String, after afterID: String? = nil) async throws -> Committed<String> {
        try await perform("New Heading") { tx in
            var heading = Item(id: tx.newID(), kind: .heading, title: title, createdAt: tx.now, bucket: .anytime, sortKey: "")
            heading.projectID = projectID
            heading.sortKey = try tx.newKeys(1, in: .project(projectID), after: afterID)[0]
            try tx.save(heading)
            return heading.id
        }
    }

    // MARK: Edit

    @discardableResult
    public func rename(_ id: String, to title: String) async throws -> Committed<Void> {
        try await perform("Rename") { tx in
            var item = try tx.item(id)
            item.title = title
            try tx.save(item)
        }
    }

    @discardableResult
    public func setNotes(_ id: String, _ notes: String) async throws -> Committed<Void> {
        try await perform("Edit Notes") { tx in
            var item = try tx.item(id)
            item.notes = notes
            try tx.save(item)
        }
    }

    // MARK: When / Deadline / Reminder

    @discardableResult
    public func schedule(_ ids: [String], _ when: When) async throws -> Committed<Void> {
        try await perform("When") { tx in
            let items = try tx.items(ids)
            try Store.apply(items.map { ($0, when) }, in: tx)
        }
    }

    /// ⌃] / ⌃[ : moves each start date by `days` (unscheduled items count
    /// from today), never earlier than today.
    @discardableResult
    public func shiftStart(_ ids: [String], byDays days: Int) async throws -> Committed<Void> {
        try await perform("When") { tx in
            let changes = try tx.items(ids).map { item -> (Item, When) in
                let base = item.startDay ?? tx.today
                let target = max(base.adding(days: days, calendar: tx.env.calendar), tx.today)
                return (item, .day(target))
            }
            try Store.apply(changes, in: tx)
        }
    }

    static func apply(_ changes: [(Item, When)], in tx: Transaction) throws {
        let todayKeys = try tx.newKeys(changes.count, column: .todaySortKey, in: .today)
        for (index, (original, when)) in changes.enumerated() {
            guard original.kind != .heading else {
                throw ModelError.ruleViolation("headings can't be scheduled")
            }
            var item = original
            var resolved = when
            if case .day(let day) = when, day <= tx.today {
                resolved = .today
            }
            switch resolved {
            case .today, .evening:
                item.bucket = .anytime
                item.startDay = tx.today
                item.isEvening = resolved == .evening
                if original.startDay != tx.today || original.todaySortKey == nil || original.isEvening != item.isEvening {
                    item.todaySortKey = todayKeys[index]
                }
            case .day(let day):
                item.bucket = .anytime
                item.startDay = day
                item.isEvening = false
            case .someday:
                item.bucket = .someday
                item.startDay = nil
                item.isEvening = false
                item.reminderTime = nil
            case .clear:
                if item.bucket == .someday { item.bucket = .anytime }
                item.startDay = nil
                item.isEvening = false
                item.reminderTime = nil
            }
            if item.bucket != .inbox, original.bucket == .inbox {
                item.sortKey = try tx.newKeys(1, in: .noParent(item.bucket))[0]
            }
            try tx.save(item)
        }
    }

    @discardableResult
    public func setDeadline(_ ids: [String], _ day: Day?) async throws -> Committed<Void> {
        try await perform("Deadline") { tx in
            for var item in try tx.items(ids) {
                guard item.kind != .heading else { throw ModelError.ruleViolation("headings can't have deadlines") }
                item.deadlineDay = day
                try tx.save(item)
            }
        }
    }

    /// Sets a reminder time (minutes after midnight). Unscheduled items are scheduled for today.
    @discardableResult
    public func setReminder(_ id: String, minutes: Int?) async throws -> Committed<Void> {
        try await perform("Reminder") { tx in
            var item = try tx.item(id)
            if minutes != nil, item.startDay == nil {
                item.bucket = .anytime
                item.startDay = tx.today
                item.todaySortKey = try tx.newKeys(1, column: .todaySortKey, in: .today)[0]
            }
            item.reminderTime = minutes
            try tx.save(item)
        }
    }

    // MARK: Status

    /// Completes or cancels items. A project with open to-dos needs `openItems`.
    @discardableResult
    public func setStatus(_ ids: [String], _ status: ItemStatus, openItems: OpenItemsDecision? = nil) async throws -> Committed<Void> {
        try await perform(status == .open ? "Mark as Incomplete" : status == .completed ? "Complete" : "Cancel") { tx in
            for var item in try tx.items(ids) {
                if status != .open {
                    switch item.kind {
                    case .project:
                        let children = try tx.openTodos(under: item.id)
                        if !children.isEmpty {
                            guard let openItems else { throw ModelError.projectHasOpenItems(count: children.count) }
                            for var child in children {
                                child.status = openItems == .complete ? .completed : .canceled
                                child.stopDate = tx.now
                                try tx.save(child)
                            }
                        }
                        for var heading in try tx.liveItems(where: "kind = 2 AND status = 0 AND projectID = ?", [item.id]) {
                            heading.status = .completed
                            heading.stopDate = tx.now
                            try tx.save(heading)
                        }
                    case .heading:
                        let open = try tx.openTodos(under: item.id)
                        if !open.isEmpty { throw ModelError.headingHasOpenItems(count: open.count) }
                    case .todo:
                        break
                    }
                }
                item.status = status
                item.stopDate = status == .open ? nil : tx.now
                try tx.save(item)
            }
        }
    }

    // MARK: Trash

    /// Moves items (and a project's or heading's children) to the Trash.
    @discardableResult
    public func trash(_ ids: [String]) async throws -> Committed<Void> {
        try await perform("Delete") { tx in
            for item in try tx.items(ids) where item.trashedAt == nil {
                try Store.trash(item, in: tx)
            }
        }
    }

    static func trash(_ item: Item, in tx: Transaction) throws {
        var item = item
        item.trashedAt = tx.now
        try tx.save(item)
        if item.kind != .todo {
            for var child in try tx.liveItems(where: "trashedAt IS NULL AND (projectID = ? OR headingID = ?)", [item.id, item.id]) {
                child.trashedAt = tx.now
                try tx.save(child)
            }
        }
    }

    /// Restores items from the Trash, with the children trashed alongside them.
    @discardableResult
    public func putBack(_ ids: [String]) async throws -> Committed<Void> {
        try await perform("Put Back") { tx in
            for item in try tx.items(ids) {
                guard let trashedAt = item.trashedAt else { continue }
                var group = [item]
                if item.kind != .todo {
                    group += try tx.liveItems(where: "trashedAt = ? AND (projectID = ? OR headingID = ?)", [trashedAt.timeIntervalSince1970, item.id, item.id])
                }
                // Restore parents before children (project, then headings, then to-dos)
                // so the rules see live parents.
                let rank: [ItemKind: Int] = [.project: 0, .heading: 1, .todo: 2]
                for var member in group.sorted(by: { rank[$0.kind]! < rank[$1.kind]! }) {
                    member.trashedAt = nil
                    try Store.detachFromMissingParents(&member, in: tx)
                    try tx.save(member)
                }
            }
        }
    }

    /// Clears links to parents that were deleted or are still in the Trash.
    static func detachFromMissingParents(_ item: inout Item, in tx: Transaction) throws {
        func isGone(_ id: String?) throws -> Bool {
            guard let id else { return false }
            guard let parent = try Item.fetchOne(tx.db, key: id) else { return true }
            return parent.deletedAt != nil || parent.trashedAt != nil
        }
        if try isGone(item.headingID) {
            item.headingID = nil
        }
        if try isGone(item.projectID) {
            if item.kind == .heading {
                throw ModelError.invalidMove("heading's project is gone")
            }
            item.projectID = nil
            item.headingID = nil
            item.bucket = item.startDay == nil ? .inbox : .anytime
            item.sortKey = try tx.newKeys(1, in: Container.of(item))[0]
        }
        if let areaID = item.areaID {
            let area = try Area.fetchOne(tx.db, key: areaID)
            if area == nil || area?.deletedAt != nil {
                item.areaID = nil
            }
        }
        if item.bucket == .inbox, item.projectID == nil, item.areaID == nil, item.kind == .project {
            item.bucket = .anytime
        }
    }

    /// Permanently removes everything in the Trash (tombstones it, for sync).
    @discardableResult
    public func emptyTrash() async throws -> Committed<Void> {
        try await perform("Empty Trash") { tx in
            let trashed = try tx.liveItems(where: "trashedAt IS NOT NULL")
            for item in trashed {
                for checklistItem in try ChecklistItem.filter(Column("itemID") == item.id && Column("deletedAt") == nil).fetchAll(tx.db) {
                    try tx.delete(checklistItem)
                }
                for link in try ItemTag.filter(Column("itemID") == item.id && Column("deletedAt") == nil).fetchAll(tx.db) {
                    try tx.delete(link)
                }
                try tx.delete(item)
            }
        }
    }

    // MARK: Duplicate

    /// Duplicates to-dos and projects (with their contents) right after the originals.
    @discardableResult
    public func duplicate(_ ids: [String]) async throws -> Committed<[String]> {
        try await perform("Duplicate") { tx in
            var newIDs: [String] = []
            for original in try tx.items(ids) {
                guard original.kind != .heading else { throw ModelError.ruleViolation("headings can't be duplicated") }
                guard original.repeatRule == nil else { throw ModelError.ruleViolation("repeating items can't be duplicated") }
                var copy = original
                copy.id = tx.newID()
                copy.createdAt = tx.now
                copy.sortKey = try tx.newKeys(1, in: Container.of(original), after: original.id)[0]
                if original.todaySortKey != nil {
                    copy.todaySortKey = try tx.newKeys(1, column: .todaySortKey, in: .today, after: original.id)[0]
                }
                try tx.save(copy)
                try Store.copyDetails(from: original.id, to: copy.id, in: tx)
                if original.kind == .project {
                    var headingMap: [String: String] = [:]
                    let children = try tx.liveItems(where: "projectID = ? AND trashedAt IS NULL", [original.id])
                    for child in children.sorted(by: { $0.kind.rawValue > $1.kind.rawValue }) {
                        var childCopy = child
                        childCopy.id = tx.newID()
                        childCopy.createdAt = tx.now
                        childCopy.projectID = copy.id
                        childCopy.headingID = child.headingID.flatMap { headingMap[$0] }
                        if child.kind == .heading { headingMap[child.id] = childCopy.id }
                        try tx.save(childCopy)
                        try Store.copyDetails(from: child.id, to: childCopy.id, in: tx)
                    }
                }
                newIDs.append(copy.id)
            }
            return newIDs
        }
    }

    /// Copies checklist items and tags.
    static func copyDetails(from sourceID: String, to targetID: String, in tx: Transaction) throws {
        for source in try ChecklistItem.filter(Column("itemID") == sourceID && Column("deletedAt") == nil).fetchAll(tx.db) {
            var copy = source
            copy.id = tx.newID()
            copy.itemID = targetID
            copy.createdAt = tx.now
            try tx.save(copy)
        }
        for link in try ItemTag.filter(Column("itemID") == sourceID && Column("deletedAt") == nil).fetchAll(tx.db) {
            try tx.save(ItemTag(itemID: targetID, tagID: link.tagID, createdAt: tx.now))
        }
    }
}
