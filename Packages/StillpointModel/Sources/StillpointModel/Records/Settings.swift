import Foundation
import GRDB

public enum LogPolicy: Int, Codable, Sendable, DatabaseValueConvertible {
    /// Completed items move to the Logbook as soon as they are completed.
    case immediately = 0
    /// Completed items move to the Logbook the next day.
    case daily = 1
    /// Completed items stay until Log Completed is chosen.
    case manually = 2
}

public enum Appearance: Int, Codable, Sendable, DatabaseValueConvertible {
    case automatic = 0, light = 1, dark = 2, black = 3
}

public enum TextSize: Int, Codable, Sendable, DatabaseValueConvertible {
    case small = 0, medium = 1, large = 2, extraLarge = 3
}

/// The single settings row (`id == "settings"`). Synced, so preferences
/// follow the user across devices.
public struct Settings: IdentifiedRecord {
    public static let databaseTableName = "settings"
    public static let singletonID = "settings"

    public var id: String
    public var ownerID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public var logPolicy: LogPolicy
    /// Items completed at or before this instant are logged ("Log Completed").
    public var manualLogCutoff: Date?
    public var groupTodayByProject: Bool
    public var appearance: Appearance
    public var textSize: TextSize
    /// Hex colour such as "#3478F6"; nil follows the system accent.
    public var accentColor: String?

    public init(createdAt: Date) {
        self.id = Settings.singletonID
        self.ownerID = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.deletedAt = nil
        self.logPolicy = .daily
        self.manualLogCutoff = nil
        self.groupTodayByProject = false
        self.appearance = .automatic
        self.textSize = .medium
        self.accentColor = nil
    }
}
