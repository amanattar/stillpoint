import GRDB

/// The data rules from spec §4.3, checked on every item write.
enum Rules {
    static func validate(_ item: Item, in tx: Transaction) throws {
        func fail(_ message: String) -> ModelError {
            .ruleViolation("\(item.kind) \(item.id): \(message)")
        }

        switch item.kind {
        case .heading:
            guard let projectID = item.projectID else { throw fail("heading needs a project") }
            guard item.headingID == nil, item.areaID == nil else { throw fail("heading can't have a heading or area") }
            try requireLive(projectID, kind: .project, in: tx, else: fail("heading's project not found"))
        case .project:
            guard item.projectID == nil, item.headingID == nil else { throw fail("projects can't be nested") }
        case .todo:
            if let projectID = item.projectID {
                guard item.areaID == nil else { throw fail("to-do in a project inherits the project's area") }
                try requireLive(projectID, kind: .project, in: tx, else: fail("project not found"))
            }
            if let headingID = item.headingID {
                let heading = try Item.fetchOne(tx.db, key: headingID)
                guard let heading, heading.kind == .heading, heading.deletedAt == nil else { throw fail("heading not found") }
                guard heading.projectID == item.projectID else { throw fail("to-do must be in its heading's project") }
            }
        }

        if item.bucket == .inbox {
            guard item.kind == .todo else { throw fail("only to-dos can be in the Inbox") }
            guard item.projectID == nil, item.areaID == nil else { throw fail("Inbox to-dos have no project or area") }
            guard item.startDay == nil else { throw fail("Inbox to-dos have no start date") }
        }
        if item.startDay != nil, item.bucket != .anytime {
            throw fail("a start date requires the anytime bucket")
        }
        if item.isEvening, item.startDay == nil {
            throw fail("This Evening requires a start date")
        }
        if item.reminderTime != nil, item.startDay == nil {
            throw fail("a reminder requires a start date")
        }
        if let areaID = item.areaID {
            let area = try Area.fetchOne(tx.db, key: areaID)
            guard let area, area.deletedAt == nil else { throw fail("area not found") }
        }
    }

    static func validate(_ checklistItem: ChecklistItem, in tx: Transaction) throws {
        let parent = try Item.fetchOne(tx.db, key: checklistItem.itemID)
        guard let parent, parent.kind == .todo else {
            throw ModelError.ruleViolation("checklist item \(checklistItem.id): parent must be a to-do")
        }
    }

    private static func requireLive(_ id: String, kind: ItemKind, in tx: Transaction, else error: ModelError) throws {
        let item = try Item.fetchOne(tx.db, key: id)
        guard let item, item.kind == kind, item.deletedAt == nil else { throw error }
    }
}
