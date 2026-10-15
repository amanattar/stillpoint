import SwiftUI

/// The icon and tint for each kind of list in the sidebar and list headers.
public enum ListSymbol: Sendable, Hashable {
    case inbox, today, evening, upcoming, anytime, someday, logbook, trash, deadlines
    case allProjects, laterProjects, area, project, tag

    public var systemName: String {
        switch self {
        case .inbox: "tray"
        case .today: "sun.max.fill"
        case .evening: "moon.fill"
        case .upcoming: "calendar"
        case .anytime: "square.stack"
        case .someday: "archivebox"
        case .logbook: "checkmark.seal"
        case .trash: "trash"
        case .deadlines: "flag"
        case .allProjects: "list.bullet"
        case .laterProjects: "clock"
        case .area: "square.grid.2x2"
        case .project: "circle"
        case .tag: "tag"
        }
    }

    public func tint(in palette: Palette) -> RGBA {
        switch self {
        case .inbox: palette.inbox
        case .today: palette.today
        case .evening: palette.evening
        case .upcoming: palette.upcoming
        case .anytime: palette.anytime
        case .someday: palette.someday
        case .logbook: palette.logbook
        case .trash: palette.trash
        case .deadlines: palette.deadline
        case .allProjects, .laterProjects, .area, .project, .tag: palette.textSecondary
        }
    }
}
