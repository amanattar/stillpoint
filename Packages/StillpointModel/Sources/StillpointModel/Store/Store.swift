import Foundation
import GRDB

/// The entry point to the model. All writes are commands (see `Commands/`),
/// each one transaction that returns an `UndoStep`.
public final class Store: Sendable {
    public let writer: any DatabaseWriter
    public let env: ModelEnvironment
    let clock: HybridClock

    public init(writer: any DatabaseWriter, env: ModelEnvironment) {
        self.writer = writer
        self.env = env
        self.clock = HybridClock(deviceID: env.deviceID, now: env.now)
    }

    /// Runs `body` in one write transaction.
    public func perform<Value: Sendable>(
        _ name: String,
        _ body: @escaping @Sendable (Transaction) throws -> Value
    ) async throws -> Committed<Value> {
        let env = self.env
        let clock = self.clock
        do {
            return try await writer.write { db in
                let tx = Transaction(db: db, env: env, clock: clock)
                let value = try body(tx)
                return Committed(value: value, undo: UndoStep(name: name, snapshots: tx.snapshots))
            }
        } catch let error as ModelError {
            if case .ruleViolation = error, env.assertOnRuleViolation {
                assertionFailure("\(error)")
            }
            throw error
        }
    }

    /// Columns that only make sense together. If an undo reverts one of them,
    /// it reverts the whole group, so the row can't end up half-scheduled or
    /// half-moved (for example a reminder without a start date).
    static let dependentColumns: [Set<String>] = [
        ["bucket", "startDay", "isEvening", "reminderTime", "todaySortKey"],
        ["kind", "bucket", "projectID", "headingID", "areaID", "sortKey"],
    ]

    /// Reverses `step` and returns the step that redoes it. Throws
    /// `ModelError.undoConflict` (and changes nothing) if later edits depend
    /// on this step, e.g. a to-do was added to a project this step created.
    @discardableResult
    public func undo(_ step: UndoStep) async throws -> UndoStep {
        try await perform(step.name) { tx in
            var touchedItems: [String] = []
            var touchedChecklist: [String] = []
            for snapshot in step.snapshots.reversed() {
                let current = try tx.fetchRow(table: snapshot.table, primaryKey: snapshot.primaryKey) ?? snapshot.after
                var target = current
                if let before = snapshot.before {
                    // Reverse only the fields this step changed (plus their
                    // dependent groups), so later edits to other fields survive.
                    var columns = Set(before.keys.filter { $0 != "modifiedAt" && snapshot.after[$0] != before[$0] })
                    for group in Store.dependentColumns where !group.isDisjoint(with: columns) {
                        columns.formUnion(group)
                    }
                    for column in columns {
                        target[column] = before[column]
                    }
                } else {
                    // Undoing a creation tombstones the row.
                    target["deletedAt"] = tx.now.timeIntervalSince1970.databaseValue
                }
                try tx.write(table: snapshot.table, entityID: snapshot.entityID, primaryKey: snapshot.primaryKey, values: target)
                if snapshot.table == Item.databaseTableName { touchedItems.append(snapshot.entityID) }
                if snapshot.table == ChecklistItem.databaseTableName { touchedChecklist.append(snapshot.entityID) }
            }
            do {
                try Store.validateAfterUndo(items: touchedItems, checklist: touchedChecklist, in: tx)
            } catch ModelError.ruleViolation {
                throw ModelError.undoConflict
            }
        }.undo
    }

    /// Every live row the undo touched, and every live child of a touched item, must still obey the rules.
    private static func validateAfterUndo(items: [String], checklist: [String], in tx: Transaction) throws {
        for id in items {
            guard let item = try Item.fetchOne(tx.db, key: id), item.deletedAt == nil else { continue }
            try Rules.validate(item, in: tx)
            let children = try Item.fetchAll(
                tx.db,
                sql: "SELECT * FROM item WHERE deletedAt IS NULL AND (projectID = ? OR headingID = ?)",
                arguments: [id, id]
            )
            for child in children {
                try Rules.validate(child, in: tx)
            }
            let entries = try ChecklistItem.fetchAll(tx.db, sql: "SELECT * FROM checklist_item WHERE deletedAt IS NULL AND itemID = ?", arguments: [id])
            for entry in entries {
                try Rules.validate(entry, in: tx)
            }
        }
        for id in checklist {
            guard let entry = try ChecklistItem.fetchOne(tx.db, key: id), entry.deletedAt == nil else { continue }
            try Rules.validate(entry, in: tx)
        }
    }

    public func read<Value: Sendable>(_ body: @escaping @Sendable (Database) throws -> Value) async throws -> Value {
        try await writer.read(body)
    }
}
