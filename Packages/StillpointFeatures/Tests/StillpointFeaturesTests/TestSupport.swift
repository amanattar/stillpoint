import Foundation
import StillpointModel
@testable import StillpointFeatures

/// Thursday 2026-10-15 10:00 UTC — the same fixed "now" the model tests use.
let fixedNow = Date(timeIntervalSince1970: 1_792_058_400)

func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

func dates(today: Day = Day(year: 2026, month: 10, day: 15)) -> DateText {
    DateText(today: today, calendar: utcCalendar(), locale: Locale(identifier: "en_US_POSIX"))
}

/// An in-memory store pinned to `fixedNow`, optionally filled with demo data.
func makeStore(demo: Bool = false) async throws -> Store {
    let store = Store(
        writer: try AppDatabase.inMemory(),
        env: ModelEnvironment(now: { fixedNow }, calendar: utcCalendar(), deviceID: "test")
    )
    if demo { try await DemoData.seed(store) }
    return store
}
