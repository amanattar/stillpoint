import StillpointModel
import StillpointUI

extension ListID {
    /// A stable string for `@SceneStorage`, so each window reopens on its list.
    public var storageKey: String {
        switch self {
        case .inbox: "inbox"
        case .today: "today"
        case .upcoming: "upcoming"
        case .anytime: "anytime"
        case .someday: "someday"
        case .deadlines: "deadlines"
        case .logbook: "logbook"
        case .trash: "trash"
        case .allProjects: "allProjects"
        case .laterProjects: "laterProjects"
        case .project(let id): "project:\(id)"
        case .area(let id): "area:\(id)"
        }
    }

    public init?(storageKey: String) {
        let simple: [String: ListID] = [
            "inbox": .inbox, "today": .today, "upcoming": .upcoming, "anytime": .anytime,
            "someday": .someday, "deadlines": .deadlines, "logbook": .logbook, "trash": .trash,
            "allProjects": .allProjects, "laterProjects": .laterProjects,
        ]
        if let list = simple[storageKey] {
            self = list
        } else if storageKey.hasPrefix("project:"), storageKey.count > 8 {
            self = .project(String(storageKey.dropFirst(8)))
        } else if storageKey.hasPrefix("area:"), storageKey.count > 5 {
            self = .area(String(storageKey.dropFirst(5)))
        } else {
            return nil
        }
    }

    /// Names for the built-in lists; projects and areas use their own titles.
    public var builtInTitle: String? {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .anytime: "Anytime"
        case .someday: "Someday"
        case .deadlines: "Deadlines"
        case .logbook: "Logbook"
        case .trash: "Trash"
        case .allProjects: "All Projects"
        case .laterProjects: "Later Projects"
        case .project, .area: nil
        }
    }

    public var symbol: ListSymbol {
        switch self {
        case .inbox: .inbox
        case .today: .today
        case .upcoming: .upcoming
        case .anytime: .anytime
        case .someday: .someday
        case .deadlines: .deadlines
        case .logbook: .logbook
        case .trash: .trash
        case .allProjects: .allProjects
        case .laterProjects: .laterProjects
        case .project: .project
        case .area: .area
        }
    }
}
