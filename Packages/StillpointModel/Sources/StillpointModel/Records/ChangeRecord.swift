import Foundation
import GRDB

/// One row of the change log. Written in the same transaction as the edit;
/// phase 5 sync pushes rows whose `pushedAt` is nil.
public struct ChangeRecord: Codable, Sendable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "change"

    public var seq: Int64?
    public var entity: String
    public var entityID: String
    /// JSON array of changed column names.
    public var fields: String
    public var hlc: String
    public var deviceID: String
    public var pushedAt: Double?

    public init(entity: String, entityID: String, fields: [String], hlc: String, deviceID: String) {
        self.seq = nil
        self.entity = entity
        self.entityID = entityID
        let data = try! JSONEncoder().encode(fields.sorted())
        self.fields = String(decoding: data, as: UTF8.self)
        self.hlc = hlc
        self.deviceID = deviceID
        self.pushedAt = nil
    }

    public var fieldList: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(fields.utf8))) ?? []
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        seq = inserted.rowID
    }
}
