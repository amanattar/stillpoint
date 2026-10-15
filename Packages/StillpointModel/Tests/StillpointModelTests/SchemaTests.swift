import Foundation
import GRDB
import Testing
@testable import StillpointModel

struct SchemaTests {
    @Test func migratesEmptyDatabase() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        let tables = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'grdb%' AND name NOT LIKE 'sqlite%' ORDER BY name")
        }
        #expect(tables == ["area", "area_tag", "change", "checklist_item", "item", "item_tag", "settings", "tag"])
    }

    @Test func itemRoundTripsAllColumns() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        var item = Item(id: "a", kind: .todo, title: "Buy milk", createdAt: Date(timeIntervalSince1970: 100), sortKey: "V")
        item.startDay = Day(year: 2026, month: 10, day: 15)
        item.deadlineDay = Day(year: 2026, month: 10, day: 20)
        item.stopDate = Date(timeIntervalSince1970: 200)
        item.reminderTime = 15 * 60
        try queue.write { db in try item.insert(db) }
        let loaded = try queue.read { db in try Item.fetchOne(db, key: "a") }
        #expect(loaded == item)
        // Dates and days are stored as plain numbers, as the sync schema expects.
        let raw = try queue.read { db in try Row.fetchOne(db, sql: "SELECT createdAt, startDay FROM item")! }
        #expect(raw["createdAt"] as Double == 100)
        #expect(raw["startDay"] as Int == 20_261_015)
    }
}
