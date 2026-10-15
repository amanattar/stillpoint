import Testing
@testable import StillpointFeatures
import StillpointModel

struct DateTextTests {
    let text = dates()

    @Test func dayTitles() {
        #expect(text.dayTitle(Day(year: 2026, month: 10, day: 15)) == "Today")
        #expect(text.dayTitle(Day(year: 2026, month: 10, day: 16)) == "Tomorrow")
        #expect(text.dayTitle(Day(year: 2026, month: 10, day: 14)) == "Yesterday")
        #expect(text.dayTitle(Day(year: 2026, month: 10, day: 17)) == "Saturday")
        #expect(text.dayTitle(Day(year: 2026, month: 10, day: 22)) == "Thursday")
        #expect(text.showsDayNumber(Day(year: 2026, month: 10, day: 22)))
        #expect(!text.showsDayNumber(Day(year: 2026, month: 10, day: 23)))
        #expect(!text.showsDayNumber(Day(year: 2026, month: 10, day: 15)))
        #expect(text.dayTitle(Day(year: 2026, month: 10, day: 28)) == "Wed, Oct 28")
        #expect(text.dayTitle(Day(year: 2027, month: 1, day: 4)) == "Mon, Jan 4, 2027")
    }

    @Test func sectionTitles() {
        func section(_ kind: SectionKind, _ title: String? = nil) -> ListSection {
            ListSection(id: "s", kind: kind, title: title, items: [])
        }
        #expect(text.sectionTitle(section(.evening)) == "This Evening")
        #expect(text.sectionTitle(section(.plain)) == nil)
        #expect(text.sectionTitle(section(.project("p"), "Garden")) == "Garden")
        #expect(text.sectionTitle(section(.restOfMonth(from: Day(year: 2026, month: 10, day: 23), through: Day(year: 2026, month: 10, day: 31)))) == "Oct 23–31")
        #expect(text.sectionTitle(section(.month(Day(year: 2026, month: 12, day: 1)))) == "December")
        #expect(text.sectionTitle(section(.month(Day(year: 2027, month: 2, day: 1)))) == "February 2027")
    }

    @Test func deadlines() {
        #expect(text.deadline(Day(year: 2026, month: 10, day: 15)) == ("Today", true))
        #expect(text.deadline(Day(year: 2026, month: 10, day: 12)) == ("3 days ago", true))
        #expect(text.deadline(Day(year: 2026, month: 10, day: 14)) == ("Yesterday", true))
        #expect(text.deadline(Day(year: 2026, month: 10, day: 16)) == ("Tomorrow", false))
        #expect(text.deadline(Day(year: 2026, month: 10, day: 19)) == ("Mon", false))
        #expect(text.deadline(Day(year: 2026, month: 11, day: 2)) == ("Nov 2", false))
    }
}
