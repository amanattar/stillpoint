import Foundation
import GRDB

public enum ItemKind: Int, Codable, Sendable, DatabaseValueConvertible {
    case todo = 0
    case project = 1
    case heading = 2
}

public enum ItemStatus: Int, Codable, Sendable, DatabaseValueConvertible {
    case open = 0
    case canceled = 2
    case completed = 3
}

public enum Bucket: Int, Codable, Sendable, DatabaseValueConvertible {
    case inbox = 0
    case anytime = 1
    case someday = 2
}

/// A to-do, project or heading.
public struct Item: IdentifiedRecord {
    public static let databaseTableName = "item"

    public var id: String
    public var ownerID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public var kind: ItemKind
    public var title: String
    public var notes: String
    public var status: ItemStatus
    public var stopDate: Date?
    public var bucket: Bucket
    public var startDay: Day?
    public var isEvening: Bool
    /// Minutes after midnight on `startDay`. Notifications arrive in phase 3.
    public var reminderTime: Int?
    public var deadlineDay: Day?
    public var projectID: String?
    public var headingID: String?
    public var areaID: String?
    public var sortKey: String
    public var todaySortKey: String?
    public var trashedAt: Date?

    // Repeating (logic arrives in phase 3).
    public var repeatRule: Data?
    public var repeatTemplateID: String?
    public var repeatPaused: Bool
    public var repeatNextDay: Day?

    public init(
        id: String, kind: ItemKind, title: String = "", createdAt: Date,
        bucket: Bucket = .inbox, sortKey: String
    ) {
        self.id = id
        self.ownerID = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.deletedAt = nil
        self.kind = kind
        self.title = title
        self.notes = ""
        self.status = .open
        self.stopDate = nil
        self.bucket = bucket
        self.startDay = nil
        self.isEvening = false
        self.reminderTime = nil
        self.deadlineDay = nil
        self.projectID = nil
        self.headingID = nil
        self.areaID = nil
        self.sortKey = sortKey
        self.todaySortKey = nil
        self.trashedAt = nil
        self.repeatRule = nil
        self.repeatTemplateID = nil
        self.repeatPaused = false
        self.repeatNextDay = nil
    }

    public var isOpen: Bool { status == .open }
}
