import GRDB

/// All schema migrations, in order. Never edit a shipped migration; add a new one.
enum Schema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1", migrate: v1)
        return migrator
    }

    private static func syncColumns(_ t: TableDefinition) {
        t.column("ownerID", .text)
        t.column("createdAt", .double).notNull()
        t.column("modifiedAt", .double).notNull()
        t.column("deletedAt", .double)
    }

    private static func v1(_ db: Database) throws {
        try db.create(table: "area") { t in
            t.primaryKey("id", .text)
            syncColumns(t)
            t.column("title", .text).notNull().defaults(to: "")
            t.column("sortKey", .text).notNull()
            t.column("isCollapsed", .boolean).notNull().defaults(to: false)
        }
        try db.create(table: "item") { t in
            t.primaryKey("id", .text)
            syncColumns(t)
            t.column("kind", .integer).notNull()
            t.column("title", .text).notNull().defaults(to: "")
            t.column("notes", .text).notNull().defaults(to: "")
            t.column("status", .integer).notNull().defaults(to: 0)
            t.column("stopDate", .double)
            t.column("bucket", .integer).notNull().defaults(to: 0)
            t.column("startDay", .integer)
            t.column("isEvening", .boolean).notNull().defaults(to: false)
            t.column("reminderTime", .integer)
            t.column("deadlineDay", .integer)
            t.column("projectID", .text)
            t.column("headingID", .text)
            t.column("areaID", .text)
            t.column("sortKey", .text).notNull()
            t.column("todaySortKey", .text)
            t.column("trashedAt", .double)
            t.column("repeatRule", .blob)
            t.column("repeatTemplateID", .text)
            t.column("repeatPaused", .boolean).notNull().defaults(to: false)
            t.column("repeatNextDay", .integer)
        }
        try db.create(index: "item_project", on: "item", columns: ["projectID"])
        try db.create(index: "item_heading", on: "item", columns: ["headingID"])
        try db.create(index: "item_area", on: "item", columns: ["areaID"])
        try db.create(index: "item_startDay", on: "item", columns: ["startDay"])
        try db.create(index: "item_deadlineDay", on: "item", columns: ["deadlineDay"])
        try db.create(index: "item_stopDate", on: "item", columns: ["stopDate"])

        try db.create(table: "tag") { t in
            t.primaryKey("id", .text)
            syncColumns(t)
            t.column("title", .text).notNull().defaults(to: "")
            t.column("parentID", .text)
            t.column("shortcut", .text)
            t.column("sortKey", .text).notNull()
        }
        try db.create(table: "item_tag") { t in
            t.column("itemID", .text).notNull()
            t.column("tagID", .text).notNull()
            syncColumns(t)
            t.primaryKey(["itemID", "tagID"])
        }
        try db.create(index: "item_tag_tag", on: "item_tag", columns: ["tagID"])
        try db.create(table: "area_tag") { t in
            t.column("areaID", .text).notNull()
            t.column("tagID", .text).notNull()
            syncColumns(t)
            t.primaryKey(["areaID", "tagID"])
        }
        try db.create(table: "checklist_item") { t in
            t.primaryKey("id", .text)
            syncColumns(t)
            t.column("itemID", .text).notNull().indexed()
            t.column("title", .text).notNull().defaults(to: "")
            t.column("isDone", .boolean).notNull().defaults(to: false)
            t.column("sortKey", .text).notNull()
        }
        try db.create(table: "settings") { t in
            t.primaryKey("id", .text)
            syncColumns(t)
            t.column("logPolicy", .integer).notNull()
            t.column("manualLogCutoff", .double)
            t.column("groupTodayByProject", .boolean).notNull()
            t.column("appearance", .integer).notNull()
            t.column("textSize", .integer).notNull()
            t.column("accentColor", .text)
        }
        try db.create(table: "change") { t in
            t.autoIncrementedPrimaryKey("seq")
            t.column("entity", .text).notNull()
            t.column("entityID", .text).notNull()
            t.column("fields", .text).notNull()
            t.column("hlc", .text).notNull()
            t.column("deviceID", .text).notNull()
            t.column("pushedAt", .double)
        }
    }
}
