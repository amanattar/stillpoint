public enum ModelError: Error, Equatable, Sendable {
    /// A write would break one of the data rules (spec §4.3). Always a bug in the caller.
    case ruleViolation(String)
    case notFound(String)
    /// Completing a project with open to-dos needs an explicit decision.
    case projectHasOpenItems(count: Int)
    /// A heading can only be archived once all its to-dos are done.
    case headingHasOpenItems(count: Int)
    case duplicateShortcut(String)
    case invalidMove(String)
    /// Undoing this step would leave data that breaks the rules (later edits depend on it).
    case undoConflict
}
