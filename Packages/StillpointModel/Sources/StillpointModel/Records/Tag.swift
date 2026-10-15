import Foundation
import GRDB

public struct Tag: IdentifiedRecord {
    public static let databaseTableName = "tag"

    public var id: String
    public var ownerID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public var title: String
    public var parentID: String?
    /// A single character; ⌃ + this key toggles the tag on the selection.
    public var shortcut: String?
    public var sortKey: String

    public init(id: String, title: String, createdAt: Date, sortKey: String) {
        self.id = id
        self.ownerID = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.deletedAt = nil
        self.title = title
        self.parentID = nil
        self.shortcut = nil
        self.sortKey = sortKey
    }
}

/// Item ↔ tag. Removing a tag tombstones the row so the removal can sync.
public struct ItemTag: SyncedRecord {
    public static let databaseTableName = "item_tag"

    public var itemID: String
    public var tagID: String
    public var ownerID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(itemID: String, tagID: String, createdAt: Date) {
        self.itemID = itemID
        self.tagID = tagID
        self.ownerID = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.deletedAt = nil
    }

    public var primaryKey: [String: DatabaseValue] {
        ["itemID": itemID.databaseValue, "tagID": tagID.databaseValue]
    }

    public var entityID: String { "\(itemID)|\(tagID)" }
}

/// Area ↔ tag.
public struct AreaTag: SyncedRecord {
    public static let databaseTableName = "area_tag"

    public var areaID: String
    public var tagID: String
    public var ownerID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(areaID: String, tagID: String, createdAt: Date) {
        self.areaID = areaID
        self.tagID = tagID
        self.ownerID = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.deletedAt = nil
    }

    public var primaryKey: [String: DatabaseValue] {
        ["areaID": areaID.databaseValue, "tagID": tagID.databaseValue]
    }

    public var entityID: String { "\(areaID)|\(tagID)" }
}
