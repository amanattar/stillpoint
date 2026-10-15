import Foundation
import GRDB

/// Every table that syncs: stores dates as Unix seconds (REAL) and carries
/// the common sync columns.
public protocol SyncedRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    var ownerID: String? { get set }
    var createdAt: Date { get set }
    var modifiedAt: Date { get set }
    var deletedAt: Date? { get set }
    /// Primary-key column values, used for snapshots and change-log entries.
    var primaryKey: [String: DatabaseValue] { get }
    /// A single string identifying the row in the change log.
    var entityID: String { get }
}

extension SyncedRecord {
    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSince1970
    }

    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSince1970
    }
}

/// Records whose primary key is a single `id` column.
public protocol IdentifiedRecord: SyncedRecord, Identifiable where ID == String {}

extension IdentifiedRecord {
    public var primaryKey: [String: DatabaseValue] { ["id": id.databaseValue] }
    public var entityID: String { id }
}
