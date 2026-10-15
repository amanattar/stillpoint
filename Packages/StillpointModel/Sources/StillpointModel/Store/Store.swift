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

    /// Reverses `step` and returns the step that redoes it.
    @discardableResult
    public func undo(_ step: UndoStep) async throws -> UndoStep {
        try await perform(step.name) { tx in
            for snapshot in step.snapshots.reversed() {
                let current = try tx.fetchRow(table: snapshot.table, primaryKey: snapshot.primaryKey) ?? snapshot.after
                var target = current
                if let before = snapshot.before {
                    // Reverse only the fields this step changed, so later edits
                    // to other fields of the same row survive.
                    for (column, value) in before where column != "modifiedAt" && snapshot.after[column] != value {
                        target[column] = value
                    }
                } else {
                    // Undoing a creation tombstones the row.
                    target["deletedAt"] = tx.now.timeIntervalSince1970.databaseValue
                }
                try tx.write(table: snapshot.table, entityID: snapshot.entityID, primaryKey: snapshot.primaryKey, values: target)
            }
        }.undo
    }

    public func read<Value: Sendable>(_ body: @escaping @Sendable (Database) throws -> Value) async throws -> Value {
        try await writer.read(body)
    }
}
