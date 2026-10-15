/// Where a new or moved item goes.
public enum Destination: Sendable, Equatable {
    case inbox
    /// Anytime, with no project or area.
    case anytime
    /// Someday, with no project or area.
    case someday
    /// Create-only: Anytime, scheduled for today.
    case today
    /// Create-only: Anytime, scheduled for this evening.
    case evening
    case area(String)
    case project(String)
    case heading(String)
}

/// The When choices from the When popover and the ⌘T / ⌘E / ⌘O / ⌘R shortcuts.
public enum When: Sendable, Equatable {
    case today
    case evening
    case day(Day)
    case someday
    /// Remove the start date (Someday becomes Anytime).
    case clear
}

/// What to do with a project's open to-dos when the project is completed.
public enum OpenItemsDecision: Sendable {
    case complete
    case cancel
}

/// Which ordering a reorder changes: the list's own order or Today's.
public enum OrderColumn: String, Sendable {
    case sortKey
    case todaySortKey
}
