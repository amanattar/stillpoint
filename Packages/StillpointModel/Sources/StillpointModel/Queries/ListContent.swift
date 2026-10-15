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
}

public struct ListContent: Sendable, Equatable {
    public var sections: [ListSection]
    /// Projects and areas: items scheduled for later or Someday ("Show N later items").
    public var later: [Item]
    /// Projects and areas: logged items ("Show N logged items").
    public var logged: [Item]
    /// Live tag IDs for every item in this content.
    public var tagIDsByItem: [String: [String]]

    public var allItems: [Item] { sections.flatMap(\.items) }
}
