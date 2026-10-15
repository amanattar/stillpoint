import Foundation
import GRDB

/// The context every command runs in. Writes go through `save(_:)`, which
/// validates rules, skips no-op writes, appends to the change log and
/// records undo snapshots.
public final class Transaction {
    public let db: Database
    public let env: ModelEnvironment
    public let now: Date
    public let today: Day
    let clock: HybridClock

    private(set) var snapshots: [RowSnapshot] = []
    private var snapshotIndex: [String: Int] = [:]

    init(db: Database, env: ModelEnvironment, clock: HybridClock) {
        self.db = db
        self.env = env
        self.now = env.now()
        self.today = Day(now, calendar: env.calendar)
        self.clock = clock
    }

    public func newID() -> String {
        EntityID.make(at: now)
    }

    /// Insert or update a record.
    public func save<R: SyncedRecord>(_ record: R) throws {
        if let item = record as? Item {
            try Rules.validate(item, in: self)
        } else if let checklistItem = record as? ChecklistItem {
            try Rules.validate(checklistItem, in: self)
        }
        try write(
            table: R.databaseTableName,
            entityID: record.entityID,
            primaryKey: record.primaryKey,
            values: record.databaseDictionary
        )
    }

    /// Tombstone a record so the deletion can sync.
    public func delete<R: SyncedRecord>(_ record: R) throws {
        var tombstone = record
        tombstone.deletedAt = now
        try write(
            table: R.databaseTableName,
            entityID: tombstone.entityID,
            primaryKey: tombstone.primaryKey,
            values: tombstone.databaseDictionary
        )
    }

    /// Writes raw column values. Used by `save` and by undo.
    func write(table: String, entityID: String, primaryKey: [String: DatabaseValue], values: [String: DatabaseValue]) throws {
        let current = try fetchRow(table: table, primaryKey: primaryKey)
        var values = values
        values["modifiedAt"] = now.timeIntervalSince1970.databaseValue
        let changed = values.keys.filter { $0 != "modifiedAt" && current?[$0] != values[$0] }
        if current != nil, changed.isEmpty {
            return
        }

        let columns = values.keys.sorted()
        let columnList = columns.map(\.quotedDatabaseIdentifier).joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
        try db.execute(
            sql: "INSERT OR REPLACE INTO \(table.quotedDatabaseIdentifier) (\(columnList)) VALUES (\(placeholders))",
            arguments: StatementArguments(columns.map { values[$0]! })
        )

        var change = ChangeRecord(entity: table, entityID: entityID, fields: changed, hlc: clock.tick(), deviceID: env.deviceID)
        try change.insert(db)

        let key = "\(table)|\(entityID)"
        if let index = snapshotIndex[key] {
            snapshots[index].after = values
        } else {
            snapshotIndex[key] = snapshots.count
            snapshots.append(RowSnapshot(table: table, entityID: entityID, primaryKey: primaryKey, before: current, after: values))
        }
    }

    func fetchRow(table: String, primaryKey: [String: DatabaseValue]) throws -> [String: DatabaseValue]? {
        let columns = primaryKey.keys.sorted()
        let condition = columns.map { "\($0.quotedDatabaseIdentifier) = ?" }.joined(separator: " AND ")
        let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM \(table.quotedDatabaseIdentifier) WHERE \(condition)",
            arguments: StatementArguments(columns.map { primaryKey[$0]! })
        )
        return row.map { Dictionary($0.map { ($0, $1) }, uniquingKeysWith: { first, _ in first }) }
    }
}
