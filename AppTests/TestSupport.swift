import Foundation
@testable import Stillpoint
import StillpointModel

/// Thursday 2026-10-15 10:00 UTC — the same fixed "now" the model tests use.
let fixedNow = Date(timeIntervalSince1970: 1_792_058_400)

func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("stillpoint-app-tests-\(UUID().uuidString)")
}
