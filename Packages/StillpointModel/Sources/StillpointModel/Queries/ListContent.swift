/// A list shown in the main pane.
public enum ListID: Hashable, Sendable {
    case inbox, today, upcoming, anytime, someday, deadlines, logbook, trash
    case allProjects, laterProjects
    case project(String)
    case area(String)
}

public enum SectionKind: Sendable, Equatable {
    case plain
    case evening
    case day(Day)
    case restOfMonth(from: Day, through: Day)
    /// Any day in the month; the section covers the whole month.
    case month(Day)
    case area(String)
    case project(String)
    case heading(String)
}

public struct ListSection: Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: SectionKind
    public var title: String?
    public var items: [Item]

    public init(id: String, kind: SectionKind, title: String?, items: [Item]) {
        self.id = id
        self.kind = kind
        self.title = title
        self.items = items
    }
}

public struct ChecklistProgress: Sendable, Equatable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

public struct ListContent: Sendable, Equatable {
    public var sections: [ListSection]
    /// Projects and areas: items scheduled for later or Someday ("Show N later items").
    public var later: [Item]
    /// Projects and areas: logged items ("Show N logged items").
    public var logged: [Item]
    /// Live tag IDs for every item in this content.
    public var tagIDsByItem: [String: [String]]
    /// Titles of every tag in `tagIDsByItem`.
    public var tagTitles: [String: String] = [:]
    /// The project or area title shown under a row (to-dos and projects that have a parent).
    public var parentTitles: [String: String] = [:]
    /// Checklist progress for to-dos that have a checklist.
    public var checklists: [String: ChecklistProgress] = [:]
    /// Closed ÷ total to-dos for every project row in this content.
    public var projectProgress: [String: Double] = [:]

    public init(
        sections: [ListSection], later: [Item], logged: [Item], tagIDsByItem: [String: [String]],
        tagTitles: [String: String] = [:], parentTitles: [String: String] = [:],
        checklists: [String: ChecklistProgress] = [:], projectProgress: [String: Double] = [:]
    ) {
        self.sections = sections
        self.later = later
        self.logged = logged
        self.tagIDsByItem = tagIDsByItem
        self.tagTitles = tagTitles
        self.parentTitles = parentTitles
        self.checklists = checklists
        self.projectProgress = projectProgress
    }

    public var allItems: [Item] { sections.flatMap(\.items) }
}
