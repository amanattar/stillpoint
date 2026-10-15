import Foundation
import Observation
import StillpointModel

/// Publishes the current calendar day. Lists re-subscribe when it changes,
/// so Today moves forward at local midnight, after waking from sleep on a
/// new day, and when the time zone changes.
@MainActor
@Observable
final class DayClock {
    private(set) var today: Day
    let calendar: Calendar
    @ObservationIgnored var onDayChange: (() -> Void)?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init(
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() },
        center: NotificationCenter = .default
    ) {
        self.calendar = calendar
        self.now = now
        today = Day(now(), calendar: calendar)
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    /// Re-reads the day; notifies only when it actually changed.
    func refresh() {
        let day = Day(now(), calendar: calendar)
        guard day != today else { return }
        today = day
        onDayChange?()
    }
}
