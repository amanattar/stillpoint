import Foundation
import GRDB

/// A calendar day stored as a `YYYYMMDD` integer.
///
/// Days are independent of time zone: "today" is the same day on every
/// device regardless of where it is, and never drifts by an hour around DST.
public struct Day: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(year: Int, month: Int, day: Int) {
        self.rawValue = year * 10_000 + month * 100 + day
    }

    public init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public var year: Int { rawValue / 10_000 }
    public var month: Int { rawValue / 100 % 100 }
    public var day: Int { rawValue % 100 }

    /// Noon on this day. Noon avoids days where midnight doesn't exist (DST).
    public func date(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// The first instant of this day.
    public func startOfDay(in calendar: Calendar) -> Date {
        calendar.startOfDay(for: date(in: calendar))
    }

    public func adding(days: Int, calendar: Calendar) -> Day {
        Day(calendar.date(byAdding: .day, value: days, to: date(in: calendar))!, calendar: calendar)
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

extension Day: Codable {
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension Day: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue { rawValue.databaseValue }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Day? {
        Int.fromDatabaseValue(dbValue).map(Day.init(rawValue:))
    }
}
