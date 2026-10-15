import Foundation
import Synchronization
import Testing
@testable import Stillpoint
import StillpointModel

final class MovableNow: Sendable {
    private let date = Mutex(fixedNow)
    var now: Date { date.withLock { $0 } }
    func advance(hours: Double) { date.withLock { $0 = $0.addingTimeInterval(hours * 3600) } }
}

@MainActor
struct DayClockTests {
    @Test func movesForwardOnDayChangeNotification() {
        let center = NotificationCenter()
        let clock = MovableNow()
        let dayClock = DayClock(calendar: utcCalendar(), now: { clock.now }, center: center)
        var changes = 0
        dayClock.onDayChange = { changes += 1 }
        #expect(dayClock.today == Day(year: 2026, month: 10, day: 15))

        clock.advance(hours: 15) // 01:00 on the 16th
        center.post(name: .NSCalendarDayChanged, object: nil)
        #expect(dayClock.today == Day(year: 2026, month: 10, day: 16))
        #expect(changes == 1)
    }

    @Test func ignoresNotificationsWithinTheSameDay() {
        let center = NotificationCenter()
        let clock = MovableNow()
        let dayClock = DayClock(calendar: utcCalendar(), now: { clock.now }, center: center)
        var changes = 0
        dayClock.onDayChange = { changes += 1 }
        clock.advance(hours: 2)
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        #expect(changes == 0)
    }
}
