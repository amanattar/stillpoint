import Foundation
import GRDB

public struct Area: IdentifiedRecord {
    public static let databaseTableName = "area"

    public var id: String
    public var ownerID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public var title: String
    public var sortKey: String
    public var isCollapsed: Bool

    public init(id: String, title: String, createdAt: Date, sortKey: String) {
        self.id = id
        self.ownerID = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.deletedAt = nil
        self.title = title
        self.sortKey = sortKey
        self.isCollapsed = false
    }
}
