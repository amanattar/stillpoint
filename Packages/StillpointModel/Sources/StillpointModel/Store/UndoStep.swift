import GRDB

/// A row before and after one user action. `before == nil` means the row was created.
public struct RowSnapshot: Sendable, Equatable {
    public let table: String
    public let entityID: String
    public let primaryKey: [String: DatabaseValue]
    public let before: [String: DatabaseValue]?
    public var after: [String: DatabaseValue]
}

/// Everything needed to reverse one user action. Pass it to `Store.undo(_:)`,
/// which returns the step that redoes it.
public struct UndoStep: Sendable, Equatable {
    public let name: String
    public let snapshots: [RowSnapshot]

    public var isEmpty: Bool { snapshots.isEmpty }
}

/// The result of a command: its return value plus the step that undoes it.
public struct Committed<Value: Sendable>: Sendable {
    public let value: Value
    public let undo: UndoStep
}
