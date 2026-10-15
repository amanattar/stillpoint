import Foundation

/// Everything the model needs from the outside world, injectable for tests.
public struct ModelEnvironment: Sendable {
    public var now: @Sendable () -> Date
    public var calendar: Calendar
    public var deviceID: String
    /// When true, a rule violation also triggers `assertionFailure` (debug builds).
    /// The app sets this; tests that check rejections leave it off.
    public var assertOnRuleViolation: Bool

    public init(
        now: @escaping @Sendable () -> Date = { Date() },
        // Autoupdating so a time-zone change while the app runs moves "today" with it.
        calendar: Calendar = .autoupdatingCurrent,
        deviceID: String,
        assertOnRuleViolation: Bool = false
    ) {
        self.now = now
        self.calendar = calendar
        self.deviceID = deviceID
        self.assertOnRuleViolation = assertOnRuleViolation
    }

    public var today: Day { Day(now(), calendar: calendar) }
}
