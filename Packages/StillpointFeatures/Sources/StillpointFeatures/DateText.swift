import Foundation
import StillpointModel

/// Human wording for days: section headers and deadline badges.
public struct DateText: Sendable {
    public let today: Day
    public let calendar: Calendar
    public let locale: Locale

    public init(today: Day, calendar: Calendar, locale: Locale = .autoupdatingCurrent) {
        self.today = today
        self.calendar = calendar
        self.locale = locale
    }

    /// Whole days from today to `day` (negative = past).
    public func offset(to day: Day) -> Int {
        calendar.dateComponents([.day], from: today.date(in: calendar), to: day.date(in: calendar)).day ?? 0
    }

    public func format(_ day: Day, _ template: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: day.date(in: calendar))
    }

    /// "Today", "Tomorrow", "Yesterday", a weekday within the coming week,
    /// otherwise a short date (with the year when it isn't this year).
    public func dayTitle(_ day: Day) -> String {
        switch offset(to: day) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...7: return format(day, "EEEE")
        default: return format(day, day.year == today.year ? "EEEMMMd" : "EEEMMMdy")
        }
    }

    /// Day sections 1–7 days ahead show the day number large beside their title.
    public func showsDayNumber(_ day: Day) -> Bool {
        (1...7).contains(offset(to: day))
    }

    public func sectionTitle(_ section: ListSection) -> String? {
        switch section.kind {
        case .plain, .area, .project, .heading:
            return section.title
        case .evening:
            return "This Evening"
        case .day(let day):
            return dayTitle(day)
        case .restOfMonth(let from, let through):
            return "\(format(from, "MMMd"))–\(through.day)"
        case .month(let day):
            return format(day, day.year == today.year ? "MMMM" : "MMMMy")
        }
    }

    /// Deadline badge text and whether it's due (today or overdue).
    public func deadline(_ day: Day) -> (text: String, isDue: Bool) {
        let days = offset(to: day)
        let text: String = switch days {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        case ..<(-1): "\(-days) days ago"
        case 2...6: format(day, "EEE")
        default: format(day, "MMMd")
        }
        return (text, days <= 0)
    }
}
