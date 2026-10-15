import Foundation
import GRDB

public struct ChecklistItem: IdentifiedRecord {
    public static let databaseTableName = "checklist_item"

    public var id: String
    public var ownerID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public var itemID: String
    public var title: String
    public var isDone: Bool
    public var sortKey: String

    public init(id: String, itemID: String, title: String, createdAt: Date, sortKey: String) {
        self.id = id
        self.ownerID = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.deletedAt = nil
        self.itemID = itemID
        self.title = title
        self.isDone = false
        self.sortKey = sortKey
    }
}
