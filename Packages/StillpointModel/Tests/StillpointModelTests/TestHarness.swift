import Foundation
import GRDB
import Synchronization
@testable import StillpointModel

/// A store on an in-memory database with a controllable clock.
/// Default "now" is 2026-10-15 10:00 UTC (a Thursday).
final class TestHarness: Sendable {
    let store: Store
    private let clock: TestClock

    static let defaultNow = Date(timeIntervalSince1970: 1_792_058_400)

    init(now: Date = TestHarness.defaultNow, timeZone: String = "UTC") throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        let clock = TestClock(now)
        self.clock = clock
        store = Store(writer: queue, env: ModelEnvironment(
            now: { clock.now },
            calendar: .fixture(timeZone: timeZone),
            deviceID: "test-device"
        ))
    }

    var now: Date { clock.now }
    var today: Day { store.env.today }

    func advance(seconds: TimeInterval) {
        clock.advance(seconds: seconds)
    }

    func advance(days: Int) {
        advance(seconds: Double(days) * 86_400)
    }

    func item(_ id: String) async throws -> Item {
        try await store.read { db in try Item.fetchOne(db, key: id)! }
    }

    func changes() async throws -> [ChangeRecord] {
        try await store.read { db in try ChangeRecord.order(Column("seq")).fetchAll(db) }
    }

    /// Titles of live, untrashed items matching `condition`, in `order`.
    func titles(where condition: String, order: String = "sortKey", _ arguments: StatementArguments = []) async throws -> [String] {
        try await store.read { db in
            try String.fetchAll(db, sql: "SELECT title FROM item WHERE deletedAt IS NULL AND trashedAt IS NULL AND (\(condition)) ORDER BY \(order)", arguments: arguments)
        }
    }

    /// Live tag IDs on an item.
    func tagIDs(_ itemID: String) async throws -> [String] {
        try await store.read { db in
            try String.fetchAll(db, sql: """
                SELECT item_tag.tagID FROM item_tag JOIN tag ON tag.id = item_tag.tagID
                WHERE item_tag.itemID = ? AND item_tag.deletedAt IS NULL AND tag.deletedAt IS NULL
                """, arguments: [itemID])
        }
    }
}

/// A settable clock shared between a test and its store.
final class TestClock: Sendable {
    private let date: Mutex<Date>

    init(_ date: Date) {
        self.date = Mutex(date)
    }

    var now: Date { date.withLock { $0 } }

    func advance(seconds: TimeInterval) {
        date.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}
