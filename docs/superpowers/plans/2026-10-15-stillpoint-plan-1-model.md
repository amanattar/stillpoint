# Stillpoint Plan 1 — StillpointModel (data layer) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `StillpointModel`, the UI-free, sync-ready data layer for Stillpoint: schema, data rules, every command, field-level undo, change log, all list queries, backups and safe opening. It's fully tested, with no app UI yet.

**Architecture:** A Swift package over SQLite via GRDB 7. All writes go through `Store.perform`, which runs one transaction, validates the rules, appends a `change` row for each changed record, and returns an `UndoStep`. Lists are SQL queries plus Swift grouping, observable with GRDB `ValueObservation`.

**Tech Stack:** Swift 6.4 (tools 6.2, Swift 6 language mode), GRDB.swift ≥ 7.11.0, Swift Testing, macOS 26 / iOS 26.

**Spec:** `docs/superpowers/specs/2026-10-13-stillpoint-core-design.md` (§4 data model, §6.4 undo, §7 data safety, §8 model tests).

**This is plan 1 of 4 for sub-project 1.** Plan 2: StillpointUI tokens and the app shell. Plan 3: task-list editing (cells, card, popovers, keyboard, drag and drop). Plan 4: Quick Find, tag bar, Settings, polish, CI.

**Verified:** every code block below was compiled and tested in order before this plan was written. After each task the full suite passes with the test count stated in that task's step 4.

## Global Constraints

- Platforms: `.macOS(.v26), .iOS(.v26)`. Swift tools version `6.2`, Swift 6 language mode (strict concurrency, no warnings).
- Only dependency: `https://github.com/groue/GRDB.swift` `from: "7.11.0"`. `StillpointModel` must not import SwiftUI, AppKit or UIKit.
- IDs are lowercase UUIDv7 strings. Days are `YYYYMMDD` integers. Dates are stored as Unix seconds (REAL). Ordering uses fractional `sortKey` strings. Deletion is a tombstone (`deletedAt`) (spec §4.4).
- Every write goes through `Store.perform` → `Transaction.save` / `delete`. Never write tables directly from commands.
- Original identity only: no Cultured Code names, assets or code. App name "Stillpoint", bundle ID `com.yourco.stillpoint`.
- License: GPL-3.0.
- **Git is local-only:** never add a remote, push, or use `gh`. Before the **first** commit, ask the user which name and email to use and set them with `git config user.name` / `git config user.email` in this repo only. The global config belongs to a different account.
- Run all package commands from `Packages/StillpointModel`.

## Review Focus

These are inputs and failure modes the spec implies but a casual implementation would miss. Each has a test in the task that owns it:

1. **Undoing an older step after later edits to the same item.** For example, undoing a rename made before a notes edit must keep the notes. Covered by `PipelineTests.undoingAnOlderStepKeepsLaterEditsToOtherFields` (Task 5).
2. **Changing the Logbook policy.** Items already logged must not jump back into lists. Covered by `ListQueryTests.logPolicies` (Task 8) and `setLogPolicy` (Task 7). `updateSettings` refuses to change the policy (`StructureCommandTests.logPolicyCanOnlyChangeThroughSetLogPolicy`).
3. **Drag-reorder with stale or mismatched neighbours** from the UI must return `invalidMove`, never crash on `SortKey`'s precondition. Covered by `StructureCommandTests.reorderBetweenNeighboursAndRejectsOutOfOrder` (Task 7).
4. **Put Back when the parent project or area is gone** (still trashed, or deleted). The item lands in the Inbox or Anytime, never orphaned. Covered by `ItemCommandTests.puttingBackTodoWhoseProjectIsStillTrashedSendsItToInbox` and `AreaTagChecklistTests.deletingAreaTrashesContentAndPutBackDetachesIt` (Task 6).
5. **Time zones and midnight.** Today must roll over at *local* midnight, including zones like UTC+5:30. Covered by `ListQueryTests.todayRollsOverAtLocalMidnight` and `DayTests.fromDateUsesCalendarTimeZone`. Re-subscribing at midnight while the app runs belongs to Plan 2 (see the note in Task 8).

## File Map

```
Stillpoint/
├── .gitignore  LICENSE  README.md
└── Packages/StillpointModel/
    ├── Package.swift
    ├── Sources/StillpointModel/
    │   ├── Core/       Day, SortKey, EntityID, HybridClock, ModelEnvironment
    │   ├── Records/    SyncedRecord, Item, Area, Tag (+ItemTag, AreaTag), ChecklistItem, Settings, ChangeRecord
    │   ├── Database/   Schema, BackupManager, AppDatabase
    │   ├── Store/      ModelError, UndoStep, Transaction, Rules, Store
    │   ├── Commands/   Destination, TransactionHelpers, ItemCommands, AreaTagChecklistCommands, StructureCommands
    │   └── Queries/    ListContent, ListQueries
    └── Tests/StillpointModelTests/   one test file per area + Fixtures, TestHarness
```

---

### Task 1: Repository scaffold, package and `Day`

Creates the repo skeleton, the `StillpointModel` Swift package, and the `Day` type: a calendar day stored as a `YYYYMMDD` integer (spec §4.4).
**Files:**
- Create: `.gitignore`, `README.md`, `LICENSE`
- Create: `Packages/StillpointModel/Package.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Core/Day.swift`
- Test: `Packages/StillpointModel/Tests/StillpointModelTests/Fixtures.swift`
- Test: `Packages/StillpointModel/Tests/StillpointModelTests/DayTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
- `struct Day: Hashable, Comparable, Sendable, Codable, DatabaseValueConvertible` with `init(rawValue:)`, `init(year:month:day:)`, `init(_ date: Date, calendar: Calendar)`, `year`/`month`/`day`, `date(in:) -> Date` (noon), `startOfDay(in:) -> Date`, `adding(days:calendar:) -> Day`
- Test helper `Calendar.fixture(timeZone: String = "UTC")`

- [ ] **Step 1: Create the repository files**

From `~/Developer/Stillpoint` (git is already initialized there). `LICENSE` is the official GPL-3.0 text from gnu.org:

```bash
curl -fsSL https://www.gnu.org/licenses/gpl-3.0.txt -o LICENSE
mkdir -p Packages/StillpointModel/Sources/StillpointModel/Core Packages/StillpointModel/Tests/StillpointModelTests
```

`.gitignore`:

```gitignore
.DS_Store
.build/
.swiftpm/
DerivedData/
*.xcodeproj/
xcuserdata/
```

`README.md`:

```markdown
# Stillpoint

A free, open-source task manager for macOS (iPhone and iPad later), with optional sync through your own Supabase project.

Status: early development. Licensed under GPL-3.0.

## Development

    cd Packages/StillpointModel && swift test
```

`Packages/StillpointModel/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StillpointModel",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "StillpointModel", targets: ["StillpointModel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.0"),
    ],
    targets: [
        .target(
            name: "StillpointModel",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "StillpointModelTests",
            dependencies: ["StillpointModel"]
        ),
    ]
)
```

- [ ] **Step 2: Write the failing tests**

`Packages/StillpointModel/Tests/StillpointModelTests/Fixtures.swift`:

```swift
import Foundation
@testable import StillpointModel

extension Calendar {
    static func fixture(timeZone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}
```

`Packages/StillpointModel/Tests/StillpointModelTests/DayTests.swift`:

```swift
import Foundation
import Testing
@testable import StillpointModel

struct DayTests {
    @Test func componentsRoundTrip() {
        let day = Day(year: 2026, month: 3, day: 9)
        #expect(day.rawValue == 20_260_309)
        #expect(day.year == 2026)
        #expect(day.month == 3)
        #expect(day.day == 9)
        #expect(day.description == "2026-03-09")
    }

    @Test func fromDateUsesCalendarTimeZone() {
        // 2026-10-15 23:30 UTC is already Oct 16 in Kolkata (UTC+5:30).
        let date = Date(timeIntervalSince1970: 1_792_107_000)
        #expect(Day(date, calendar: .fixture(timeZone: "UTC")) == Day(year: 2026, month: 10, day: 15))
        #expect(Day(date, calendar: .fixture(timeZone: "Asia/Kolkata")) == Day(year: 2026, month: 10, day: 16))
    }

    @Test func addingDaysCrossesMonthYearAndDST() {
        let berlin = Calendar.fixture(timeZone: "Europe/Berlin")
        #expect(Day(year: 2026, month: 12, day: 31).adding(days: 1, calendar: berlin) == Day(year: 2027, month: 1, day: 1))
        #expect(Day(year: 2028, month: 3, day: 1).adding(days: -1, calendar: berlin) == Day(year: 2028, month: 2, day: 29))
        // DST ends in Berlin on 2026-10-25.
        #expect(Day(year: 2026, month: 10, day: 24).adding(days: 2, calendar: berlin) == Day(year: 2026, month: 10, day: 26))
    }

    @Test func ordering() {
        #expect(Day(year: 2026, month: 1, day: 31) < Day(year: 2026, month: 2, day: 1))
    }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `cd Packages/StillpointModel && swift test`
Expected: the build fails with `error: cannot find 'Day' in scope`.

- [ ] **Step 4: Implement**

`Packages/StillpointModel/Sources/StillpointModel/Core/Day.swift`:

```swift
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
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `cd Packages/StillpointModel && swift test`
Expected: `✔ Test run with 4 tests … passed`, with no compiler warnings.

- [ ] **Step 6: Commit (first commit: ask the user for the repo-local git name/email first; see Global Constraints)**

```bash
git add Packages/StillpointModel/Sources/StillpointModel/Core/Day.swift Packages/StillpointModel/Tests/StillpointModelTests/Fixtures.swift Packages/StillpointModel/Tests/StillpointModelTests/DayTests.swift .gitignore README.md LICENSE Packages/StillpointModel/Package.swift
git commit -m "feat(model): scaffold package and Day type"
```

### Task 2: Fractional sort keys

`SortKey` generates ordering keys between any two keys, so a reorder rewrites one row (spec §4.4). Appending and prepending step by one digit so keys stay short.
**Files:**
- Create: `Packages/StillpointModel/Sources/StillpointModel/Core/SortKey.swift`
- Test: `Packages/StillpointModel/Tests/StillpointModelTests/SortKeyTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
- `SortKey.between(_ lower: String?, _ upper: String?) -> String` (precondition: lower < upper)
- `SortKey.sequence(count: Int, after: String?, before: String?) -> [String]`

- [ ] **Step 1: Write the failing tests**

`Packages/StillpointModel/Tests/StillpointModelTests/SortKeyTests.swift`:

```swift
import Testing
@testable import StillpointModel

struct SortKeyTests {
    @Test func firstKeyIsMiddle() {
        #expect(SortKey.between(nil, nil) == "V")
    }

    @Test func betweenIsStrictlyBetween() {
        let pairs: [(String?, String?)] = [(nil, "V"), ("V", nil), ("V", "W"), ("V", "V1"), ("z", nil), ("Vz", "W"), (nil, "01")]
        for (a, b) in pairs {
            let k = SortKey.between(a, b)
            if let a { #expect(a < k, "\(a) < \(k)") }
            if let b { #expect(k < b, "\(k) < \(b)") }
            #expect(!k.hasSuffix("0"))
        }
    }

    @Test func sequenceIsAscending() {
        let keys = SortKey.sequence(count: 50, after: "A", before: "B")
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == 50)
        #expect(keys.allSatisfy { $0 > "A" && $0 < "B" })
    }

    @Test func tenThousandRandomInsertsStayOrderedAndUnique() {
        var rng = SeededGenerator(seed: 42)
        var keys: [String] = []
        for _ in 0..<10_000 {
            let i = Int.random(in: 0...keys.count, using: &rng)
            let lower = i > 0 ? keys[i - 1] : nil
            let upper = i < keys.count ? keys[i] : nil
            keys.insert(SortKey.between(lower, upper), at: i)
        }
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == keys.count)
        #expect(keys.map(\.count).max()! < 40)
    }

    @Test func repeatedAppendGrowsSlowly() {
        var last: String? = nil
        for _ in 0..<1_000 { last = SortKey.between(last, nil) }
        #expect(last!.count < 40)
    }
}

/// Deterministic RNG (SplitMix64) so failures are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension SortKeyTests {
    @Test func repeatedPrependGrowsSlowly() {
        var first: String? = nil
        var keys: [String] = []
        for _ in 0..<1_000 {
            first = SortKey.between(nil, first)
            keys.insert(first!, at: 0)
        }
        #expect(keys == keys.sorted())
        #expect(keys.allSatisfy { !$0.hasSuffix("0") })
        #expect(first!.count < 40)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd Packages/StillpointModel && swift test`
Expected: the build fails with `error: cannot find 'SortKey' in scope`.

- [ ] **Step 3: Implement**

`Packages/StillpointModel/Sources/StillpointModel/Core/SortKey.swift`:

```swift
/// Fractional ordering keys.
///
/// A key is a base-62 fraction (`"V"` ≈ 0.5). A new key can always be made
/// between two others, so moving an item rewrites only that item's key.
/// Keys never end in `"0"`, which guarantees there is always room before them.
public enum SortKey {
    static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    /// A key strictly between `lower` and `upper`. `nil` means unbounded.
    public static func between(_ lower: String?, _ upper: String?) -> String {
        let a = lower.map(Array.init) ?? []
        let b = upper.map(Array.init)
        if let b {
            precondition(a.lexicographicallyPrecedes(b), "SortKey.between: \(lower ?? "nil") must be < \(upper ?? "nil")")
        }
        // Appending and prepending are the common cases: step by one digit
        // instead of halving the gap, so keys grow ~1 char per 30-60 items.
        if lower != nil, b == nil {
            return String(increment(a))
        }
        if lower == nil, let b {
            return String(decrement(b))
        }
        return String(midpoint(a, b))
    }

    /// `count` ascending keys, all strictly between `lower` and `upper`.
    public static func sequence(count: Int, after lower: String?, before upper: String?) -> [String] {
        var keys: [String] = []
        var previous = lower
        for _ in 0..<count {
            let key = between(previous, upper)
            keys.append(key)
            previous = key
        }
        return keys
    }

    private static func index(_ c: Character) -> Int {
        digits.firstIndex(of: c)!
    }

    /// The shortest key greater than `a`.
    private static func increment(_ a: [Character]) -> [Character] {
        guard let first = a.first else { return [digits[digits.count / 2]] }
        let d = index(first)
        if d < digits.count - 1 {
            return [digits[d + 1]]
        }
        return [first] + increment(Array(a.dropFirst()))
    }

    /// A short key less than `b`, never ending in "0".
    private static func decrement(_ b: [Character]) -> [Character] {
        let d = index(b[0])
        if d >= 2 {
            return [digits[d - 1]]
        }
        if d == 1 {
            return ["0", digits[digits.count - 1]]
        }
        return ["0"] + decrement(Array(b.dropFirst()))
    }

    private static func midpoint(_ a: [Character], _ b: [Character]?) -> [Character] {
        if let b {
            // Skip the shared prefix, treating a missing digit in `a` as "0".
            var n = 0
            while n < b.count, (n < a.count ? a[n] : "0") == b[n] {
                n += 1
            }
            if n > 0 {
                let rest = midpoint(Array(a.dropFirst(n)), Array(b.dropFirst(n)))
                return Array(b.prefix(n)) + rest
            }
        }
        let da = a.isEmpty ? 0 : index(a[0])
        let db = b.map { index($0[0]) } ?? digits.count
        if db - da > 1 {
            return [digits[(da + db) / 2]]
        }
        // Adjacent first digits.
        if let b, b.count > 1 {
            return [b[0]]
        }
        return [digits[da]] + midpoint(Array(a.dropFirst()), nil)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd Packages/StillpointModel && swift test`
Expected: `✔ Test run with 10 tests … passed`, with no compiler warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/StillpointModel/Sources/StillpointModel/Core/SortKey.swift Packages/StillpointModel/Tests/StillpointModelTests/SortKeyTests.swift
git commit -m "feat(model): fractional sort keys"
```

### Task 3: IDs, hybrid logical clock, environment

UUIDv7 IDs, the hybrid logical clock stamped on every change-log row, and `ModelEnvironment`: the injected clock, calendar and device ID that make every time-dependent test deterministic.
**Files:**
- Create: `Packages/StillpointModel/Sources/StillpointModel/Core/EntityID.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Core/HybridClock.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Core/ModelEnvironment.swift`
- Test: `Packages/StillpointModel/Tests/StillpointModelTests/ClockAndIDTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
- `EntityID.make(at: Date) -> String` (lowercase UUIDv7)
- `final class HybridClock: Sendable` — `init(deviceID:now:)`, `tick() -> String` (`"<13-digit ms>-<6-digit counter>-<deviceID>"`)
- `struct ModelEnvironment: Sendable` — `now`, `calendar`, `deviceID`, `assertOnRuleViolation`, computed `today: Day`

- [ ] **Step 1: Write the failing tests**

`Packages/StillpointModel/Tests/StillpointModelTests/ClockAndIDTests.swift`:

```swift
import Foundation
import Synchronization
import Testing
@testable import StillpointModel

struct ClockAndIDTests {
    @Test func uuidV7Format() {
        let id = EntityID.make(at: Date(timeIntervalSince1970: 1_792_000_000))
        #expect(id.count == 36)
        let parts = id.split(separator: "-")
        #expect(parts.map(\.count) == [8, 4, 4, 4, 12])
        #expect(parts[2].first == "7")
        #expect("89ab".contains(parts[3].first!))
    }

    @Test func uuidV7SortsByTime() {
        let a = EntityID.make(at: Date(timeIntervalSince1970: 1_000))
        let b = EntityID.make(at: Date(timeIntervalSince1970: 2_000))
        #expect(a < b)
    }

    @Test func clockIsMonotonicWhenWallClockStallsOrGoesBack() {
        let wall = Mutex(Date(timeIntervalSince1970: 1_000))
        let clock = HybridClock(deviceID: "dev", now: { wall.withLock { $0 } })
        let t1 = clock.tick()
        let t2 = clock.tick()
        wall.withLock { $0 = Date(timeIntervalSince1970: 999) }
        let t3 = clock.tick()
        wall.withLock { $0 = Date(timeIntervalSince1970: 1_001) }
        let t4 = clock.tick()
        #expect(t1 < t2 && t2 < t3 && t3 < t4)
        #expect(t1 == "0000001000000-000000-dev")
        #expect(t4 == "0000001001000-000000-dev")
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd Packages/StillpointModel && swift test`
Expected: the build fails with `error: cannot find 'EntityID' in scope`.

- [ ] **Step 3: Implement**

`Packages/StillpointModel/Sources/StillpointModel/Core/EntityID.swift`:

```swift
import Foundation

/// UUIDv7 identifiers: globally unique and sortable by creation time.
public enum EntityID {
    public static func make(at date: Date) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let ms = UInt64(max(0, date.timeIntervalSince1970 * 1000))
        for i in 0..<6 {
            bytes[i] = UInt8((ms >> (8 * UInt64(5 - i))) & 0xFF)
        }
        for i in 6..<16 {
            bytes[i] = UInt8.random(in: 0...255)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70 // version 7
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let parts = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4),
                     hex.dropFirst(16).prefix(4), hex.dropFirst(20)]
        return parts.joined(separator: "-")
    }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Core/HybridClock.swift`:

```swift
import Foundation
import Synchronization

/// A hybrid logical clock: wall-clock milliseconds plus a counter, so
/// timestamps from one device always increase even if the clock stalls.
/// Format: `"<13-digit ms>-<6-digit counter>-<deviceID>"`, which sorts as text.
public final class HybridClock: Sendable {
    public let deviceID: String
    private let now: @Sendable () -> Date
    private let state = Mutex<(ms: Int64, counter: Int)>((0, 0))

    public init(deviceID: String, now: @escaping @Sendable () -> Date) {
        self.deviceID = deviceID
        self.now = now
    }

    public func tick() -> String {
        let wall = Int64(now().timeIntervalSince1970 * 1000)
        let (ms, counter) = state.withLock { state in
            if wall > state.ms {
                state = (wall, 0)
            } else {
                state.counter += 1
            }
            return state
        }
        return String(format: "%013lld-%06d-", ms, counter) + deviceID
    }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Core/ModelEnvironment.swift`:

```swift
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
        calendar: Calendar = .current,
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
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd Packages/StillpointModel && swift test`
Expected: `✔ Test run with 13 tests … passed`, with no compiler warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/StillpointModel/Sources/StillpointModel/Core/EntityID.swift Packages/StillpointModel/Sources/StillpointModel/Core/HybridClock.swift Packages/StillpointModel/Sources/StillpointModel/Core/ModelEnvironment.swift Packages/StillpointModel/Tests/StillpointModelTests/ClockAndIDTests.swift
git commit -m "feat(model): UUIDv7 ids, hybrid clock, environment"
```

### Task 4: Records and the v1 schema

One record type per table (spec §4.1) and migration `v1`. Dates are stored as Unix seconds (REAL) and days as integers, so phase 5 can mirror the tables 1:1 in Postgres.
**Files:**
- Create: `Packages/StillpointModel/Sources/StillpointModel/Records/SyncedRecord.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Records/Item.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Records/Area.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Records/Tag.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Records/ChecklistItem.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Records/Settings.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Records/ChangeRecord.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Database/Schema.swift`
- Test: `Packages/StillpointModel/Tests/StillpointModelTests/SchemaTests.swift`

**Interfaces:**
- Consumes: `Day` (Task 1)
- Produces:
- `protocol SyncedRecord` (`ownerID`, `createdAt`, `modifiedAt`, `deletedAt`, `primaryKey: [String: DatabaseValue]`, `entityID: String`); `protocol IdentifiedRecord` for single-`id` tables
- `Item` with `ItemKind` (todo/project/heading), `ItemStatus` (open=0/canceled=2/completed=3), `Bucket` (inbox/anytime/someday); `init(id:kind:title:createdAt:bucket:sortKey:)`
- `Area`, `Tag`, `ItemTag`, `AreaTag`, `ChecklistItem`, `Settings` (`singletonID = "settings"`, `LogPolicy`, `Appearance`, `TextSize`), `ChangeRecord` (`fieldList: [String]`)
- `enum Schema { static var migrator: DatabaseMigrator }` (internal)

- [ ] **Step 1: Write the failing tests**

`Packages/StillpointModel/Tests/StillpointModelTests/SchemaTests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import StillpointModel

struct SchemaTests {
    @Test func migratesEmptyDatabase() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        let tables = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'grdb%' AND name NOT LIKE 'sqlite%' ORDER BY name")
        }
        #expect(tables == ["area", "area_tag", "change", "checklist_item", "item", "item_tag", "settings", "tag"])
    }

    @Test func itemRoundTripsAllColumns() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        var item = Item(id: "a", kind: .todo, title: "Buy milk", createdAt: Date(timeIntervalSince1970: 100), sortKey: "V")
        item.startDay = Day(year: 2026, month: 10, day: 15)
        item.deadlineDay = Day(year: 2026, month: 10, day: 20)
        item.stopDate = Date(timeIntervalSince1970: 200)
        item.reminderTime = 15 * 60
        try queue.write { db in try item.insert(db) }
        let loaded = try queue.read { db in try Item.fetchOne(db, key: "a") }
        #expect(loaded == item)
        // Dates and days are stored as plain numbers, as the sync schema expects.
        let raw = try queue.read { db in try Row.fetchOne(db, sql: "SELECT createdAt, startDay FROM item")! }
        #expect(raw["createdAt"] as Double == 100)
        #expect(raw["startDay"] as Int == 20_261_015)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd Packages/StillpointModel && swift test`
Expected: the build fails with `error: cannot find 'Schema' in scope`.

- [ ] **Step 3: Implement**

`Packages/StillpointModel/Sources/StillpointModel/Records/SyncedRecord.swift`:

```swift
import Foundation
import GRDB

/// Every table that syncs: stores dates as Unix seconds (REAL) and carries
/// the common sync columns.
public protocol SyncedRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    var ownerID: String? { get set }
    var createdAt: Date { get set }
    var modifiedAt: Date { get set }
    var deletedAt: Date? { get set }
    /// Primary-key column values, used for snapshots and change-log entries.
    var primaryKey: [String: DatabaseValue] { get }
    /// A single string identifying the row in the change log.
    var entityID: String { get }
}

extension SyncedRecord {
    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSince1970
    }

    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSince1970
    }
}

/// Records whose primary key is a single `id` column.
public protocol IdentifiedRecord: SyncedRecord, Identifiable where ID == String {}

extension IdentifiedRecord {
    public var primaryKey: [String: DatabaseValue] { ["id": id.databaseValue] }
    public var entityID: String { id }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Records/Item.swift`:

```swift
import Foundation
import GRDB

public enum ItemKind: Int, Codable, Sendable, DatabaseValueConvertible {
    case todo = 0
    case project = 1
    case heading = 2
}

public enum ItemStatus: Int, Codable, Sendable, DatabaseValueConvertible {
    case open = 0
    case canceled = 2
    case completed = 3
}

public enum Bucket: Int, Codable, Sendable, DatabaseValueConvertible {
    case inbox = 0
    case anytime = 1
    case someday = 2
}

/// A to-do, project or heading.
public struct Item: IdentifiedRecord {
    public static let databaseTableName = "item"

    public var id: String
    public var ownerID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public var kind: ItemKind
    public var title: String
    public var notes: String
    public var status: ItemStatus
    public var stopDate: Date?
    public var bucket: Bucket
    public var startDay: Day?
    public var isEvening: Bool
    /// Minutes after midnight on `startDay`. Notifications arrive in phase 3.
    public var reminderTime: Int?
    public var deadlineDay: Day?
    public var projectID: String?
    public var headingID: String?
    public var areaID: String?
    public var sortKey: String
    public var todaySortKey: String?
    public var trashedAt: Date?

    // Repeating (logic arrives in phase 3).
    public var repeatRule: Data?
    public var repeatTemplateID: String?
    public var repeatPaused: Bool
    public var repeatNextDay: Day?

    public init(
        id: String, kind: ItemKind, title: String = "", createdAt: Date,
        bucket: Bucket = .inbox, sortKey: String
    ) {
        self.id = id
        self.ownerID = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.deletedAt = nil
        self.kind = kind
        self.title = title
        self.notes = ""
        self.status = .open
        self.stopDate = nil
        self.bucket = bucket
        self.startDay = nil
        self.isEvening = false
        self.reminderTime = nil
        self.deadlineDay = nil
        self.projectID = nil
        self.headingID = nil
        self.areaID = nil
        self.sortKey = sortKey
        self.todaySortKey = nil
        self.trashedAt = nil
        self.repeatRule = nil
        self.repeatTemplateID = nil
        self.repeatPaused = false
        self.repeatNextDay = nil
    }

    public var isOpen: Bool { status == .open }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Records/Area.swift`:

```swift
import Foundation
import GRDB

public struct Area: IdentifiedRecord {
    public static let databaseTableName = "area"

    public var id: String
    public var ownerID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public var title: String
    public var sortKey: String
    public var isCollapsed: Bool

    public init(id: String, title: String, createdAt: Date, sortKey: String) {
        self.id = id
        self.ownerID = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.deletedAt = nil
        self.title = title
        self.sortKey = sortKey
        self.isCollapsed = false
    }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Records/Tag.swift`:

```swift
import Foundation
import GRDB

public struct Tag: IdentifiedRecord {
    public static let databaseTableName = "tag"

    public var id: String
    public var ownerID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public var title: String
    public var parentID: String?
    /// A single character; ⌃ + this key toggles the tag on the selection.
    public var shortcut: String?
    public var sortKey: String

    public init(id: String, title: String, createdAt: Date, sortKey: String) {
        self.id = id
        self.ownerID = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.deletedAt = nil
        self.title = title
        self.parentID = nil
        self.shortcut = nil
        self.sortKey = sortKey
    }
}

/// Item ↔ tag. Removing a tag tombstones the row so the removal can sync.
public struct ItemTag: SyncedRecord {
    public static let databaseTableName = "item_tag"

    public var itemID: String
    public var tagID: String
    public var ownerID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(itemID: String, tagID: String, createdAt: Date) {
        self.itemID = itemID
        self.tagID = tagID
        self.ownerID = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.deletedAt = nil
    }

    public var primaryKey: [String: DatabaseValue] {
        ["itemID": itemID.databaseValue, "tagID": tagID.databaseValue]
    }

    public var entityID: String { "\(itemID)|\(tagID)" }
}

/// Area ↔ tag.
public struct AreaTag: SyncedRecord {
    public static let databaseTableName = "area_tag"

    public var areaID: String
    public var tagID: String
    public var ownerID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(areaID: String, tagID: String, createdAt: Date) {
        self.areaID = areaID
        self.tagID = tagID
        self.ownerID = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.deletedAt = nil
    }

    public var primaryKey: [String: DatabaseValue] {
        ["areaID": areaID.databaseValue, "tagID": tagID.databaseValue]
    }

    public var entityID: String { "\(areaID)|\(tagID)" }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Records/ChecklistItem.swift`:

```swift
import Foundation
import GRDB

public struct ChecklistItem: IdentifiedRecord {
    public static let databaseTableName = "checklist_item"

    public var id: String
    public var ownerID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public var itemID: String
    public var title: String
    public var isDone: Bool
    public var sortKey: String

    public init(id: String, itemID: String, title: String, createdAt: Date, sortKey: String) {
        self.id = id
        self.ownerID = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.deletedAt = nil
        self.itemID = itemID
        self.title = title
        self.isDone = false
        self.sortKey = sortKey
    }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Records/Settings.swift`:

```swift
import Foundation
import GRDB

public enum LogPolicy: Int, Codable, Sendable, DatabaseValueConvertible {
    /// Completed items move to the Logbook as soon as they are completed.
    case immediately = 0
    /// Completed items move to the Logbook the next day.
    case daily = 1
    /// Completed items stay until Log Completed is chosen.
    case manually = 2
}

public enum Appearance: Int, Codable, Sendable, DatabaseValueConvertible {
    case automatic = 0, light = 1, dark = 2, black = 3
}

public enum TextSize: Int, Codable, Sendable, DatabaseValueConvertible {
    case small = 0, medium = 1, large = 2, extraLarge = 3
}

/// The single settings row (`id == "settings"`). Synced, so preferences
/// follow the user across devices.
public struct Settings: IdentifiedRecord {
    public static let databaseTableName = "settings"
    public static let singletonID = "settings"

    public var id: String
    public var ownerID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public var logPolicy: LogPolicy
    /// Items completed at or before this instant are logged ("Log Completed").
    public var manualLogCutoff: Date?
    public var groupTodayByProject: Bool
    public var appearance: Appearance
    public var textSize: TextSize
    /// Hex colour such as "#3478F6"; nil follows the system accent.
    public var accentColor: String?

    public init(createdAt: Date) {
        self.id = Settings.singletonID
        self.ownerID = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.deletedAt = nil
        self.logPolicy = .daily
        self.manualLogCutoff = nil
        self.groupTodayByProject = false
        self.appearance = .automatic
        self.textSize = .medium
        self.accentColor = nil
    }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Records/ChangeRecord.swift`:

```swift
import Foundation
import GRDB

/// One row of the change log. Written in the same transaction as the edit;
/// phase 5 sync pushes rows whose `pushedAt` is nil.
public struct ChangeRecord: Codable, Sendable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "change"

    public var seq: Int64?
    public var entity: String
    public var entityID: String
    /// JSON array of changed column names.
    public var fields: String
    public var hlc: String
    public var deviceID: String
    public var pushedAt: Double?

    public init(entity: String, entityID: String, fields: [String], hlc: String, deviceID: String) {
        self.seq = nil
        self.entity = entity
        self.entityID = entityID
        let data = try! JSONEncoder().encode(fields.sorted())
        self.fields = String(decoding: data, as: UTF8.self)
        self.hlc = hlc
        self.deviceID = deviceID
        self.pushedAt = nil
    }

    public var fieldList: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(fields.utf8))) ?? []
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        seq = inserted.rowID
    }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Database/Schema.swift`:

```swift
import GRDB

/// All schema migrations, in order. Never edit a shipped migration; add a new one.
enum Schema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1", migrate: v1)
        return migrator
    }

    private static func syncColumns(_ t: TableDefinition) {
        t.column("ownerID", .text)
        t.column("createdAt", .double).notNull()
        t.column("modifiedAt", .double).notNull()
        t.column("deletedAt", .double)
    }

    private static func v1(_ db: Database) throws {
        try db.create(table: "area") { t in
            t.primaryKey("id", .text)
            syncColumns(t)
            t.column("title", .text).notNull().defaults(to: "")
            t.column("sortKey", .text).notNull()
            t.column("isCollapsed", .boolean).notNull().defaults(to: false)
        }
        try db.create(table: "item") { t in
            t.primaryKey("id", .text)
            syncColumns(t)
            t.column("kind", .integer).notNull()
            t.column("title", .text).notNull().defaults(to: "")
            t.column("notes", .text).notNull().defaults(to: "")
            t.column("status", .integer).notNull().defaults(to: 0)
            t.column("stopDate", .double)
            t.column("bucket", .integer).notNull().defaults(to: 0)
            t.column("startDay", .integer)
            t.column("isEvening", .boolean).notNull().defaults(to: false)
            t.column("reminderTime", .integer)
            t.column("deadlineDay", .integer)
            t.column("projectID", .text)
            t.column("headingID", .text)
            t.column("areaID", .text)
            t.column("sortKey", .text).notNull()
            t.column("todaySortKey", .text)
            t.column("trashedAt", .double)
            t.column("repeatRule", .blob)
            t.column("repeatTemplateID", .text)
            t.column("repeatPaused", .boolean).notNull().defaults(to: false)
            t.column("repeatNextDay", .integer)
        }
        try db.create(index: "item_project", on: "item", columns: ["projectID"])
        try db.create(index: "item_heading", on: "item", columns: ["headingID"])
        try db.create(index: "item_area", on: "item", columns: ["areaID"])
        try db.create(index: "item_startDay", on: "item", columns: ["startDay"])
        try db.create(index: "item_deadlineDay", on: "item", columns: ["deadlineDay"])
        try db.create(index: "item_stopDate", on: "item", columns: ["stopDate"])

        try db.create(table: "tag") { t in
            t.primaryKey("id", .text)
            syncColumns(t)
            t.column("title", .text).notNull().defaults(to: "")
            t.column("parentID", .text)
            t.column("shortcut", .text)
            t.column("sortKey", .text).notNull()
        }
        try db.create(table: "item_tag") { t in
            t.column("itemID", .text).notNull()
            t.column("tagID", .text).notNull()
            syncColumns(t)
            t.primaryKey(["itemID", "tagID"])
        }
        try db.create(index: "item_tag_tag", on: "item_tag", columns: ["tagID"])
        try db.create(table: "area_tag") { t in
            t.column("areaID", .text).notNull()
            t.column("tagID", .text).notNull()
            syncColumns(t)
            t.primaryKey(["areaID", "tagID"])
        }
        try db.create(table: "checklist_item") { t in
            t.primaryKey("id", .text)
            syncColumns(t)
            t.column("itemID", .text).notNull().indexed()
            t.column("title", .text).notNull().defaults(to: "")
            t.column("isDone", .boolean).notNull().defaults(to: false)
            t.column("sortKey", .text).notNull()
        }
        try db.create(table: "settings") { t in
            t.primaryKey("id", .text)
            syncColumns(t)
            t.column("logPolicy", .integer).notNull()
            t.column("manualLogCutoff", .double)
            t.column("groupTodayByProject", .boolean).notNull()
            t.column("appearance", .integer).notNull()
            t.column("textSize", .integer).notNull()
            t.column("accentColor", .text)
        }
        try db.create(table: "change") { t in
            t.autoIncrementedPrimaryKey("seq")
            t.column("entity", .text).notNull()
            t.column("entityID", .text).notNull()
            t.column("fields", .text).notNull()
            t.column("hlc", .text).notNull()
            t.column("deviceID", .text).notNull()
            t.column("pushedAt", .double)
        }
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd Packages/StillpointModel && swift test`
Expected: `✔ Test run with 15 tests … passed`, with no compiler warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/StillpointModel/Sources/StillpointModel/Records/SyncedRecord.swift Packages/StillpointModel/Sources/StillpointModel/Records/Item.swift Packages/StillpointModel/Sources/StillpointModel/Records/Area.swift Packages/StillpointModel/Sources/StillpointModel/Records/Tag.swift Packages/StillpointModel/Sources/StillpointModel/Records/ChecklistItem.swift Packages/StillpointModel/Sources/StillpointModel/Records/Settings.swift Packages/StillpointModel/Sources/StillpointModel/Records/ChangeRecord.swift Packages/StillpointModel/Sources/StillpointModel/Database/Schema.swift Packages/StillpointModel/Tests/StillpointModelTests/SchemaTests.swift
git commit -m "feat(model): records and v1 schema"
```

### Task 5: Write pipeline: transactions, rules, undo, change log

Every write runs through `Store.perform`, whose `Transaction.save` validates the data rules (spec §4.3), skips no-op writes, appends a `change` row listing the changed fields, and records before/after snapshots. `Store.undo` reverses **only the fields a step changed**, so a later edit to another field of the same row survives.
**Files:**
- Create: `Packages/StillpointModel/Sources/StillpointModel/Store/ModelError.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Store/UndoStep.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Store/Transaction.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Store/Rules.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Store/Store.swift`
- Test: `Packages/StillpointModel/Tests/StillpointModelTests/TestHarness.swift`
- Test: `Packages/StillpointModel/Tests/StillpointModelTests/PipelineTests.swift`
- Test: `Packages/StillpointModel/Tests/StillpointModelTests/RulesTests.swift`

**Interfaces:**
- Consumes: Tasks 1–4
- Produces:
- `final class Store: Sendable` — `init(writer: any DatabaseWriter, env:)`, `perform<V: Sendable>(_ name: String, _ body: @escaping @Sendable (Transaction) throws -> V) async throws -> Committed<V>`, `undo(_ step: UndoStep) async throws -> UndoStep` (returns the redo step), `read<V>(_:)`
- `final class Transaction` — `db`, `env`, `now`, `today`, `newID()`, `save(_ record: some SyncedRecord)`, `delete(_ record:)` (tombstone)
- `struct UndoStep: Sendable, Equatable` (`name`, `snapshots`, `isEmpty`); `struct Committed<V>` (`value`, `undo`)
- `enum ModelError: Error, Equatable` — `ruleViolation(String)`, `notFound(String)`, `projectHasOpenItems(count:)`, `headingHasOpenItems(count:)`, `duplicateShortcut(String)`, `invalidMove(String)`
- Test helper `TestHarness` (in-memory store; default now 2026-10-15 10:00 UTC; `advance(days:)`, `advance(seconds:)`, `item(_:)`, `changes()`, `titles(where:order:_:)`, `tagIDs(_:)`)

> **Deliberate deviation from spec §4.3 rule 6:** the spec says This Evening requires a start day of *today or later*. That would make every evening item invalid the day after it rolls over, and block unrelated edits to it. The rule implemented is "This Evening requires a start date". The spec should be updated to match.

- [ ] **Step 1: Write the failing tests**

`Packages/StillpointModel/Tests/StillpointModelTests/TestHarness.swift`:

```swift
import Foundation
import GRDB
import Synchronization
@testable import StillpointModel

/// A store on an in-memory database with a controllable clock.
/// Default "now" is 2026-10-15 10:00 UTC (a Thursday).
final class TestHarness: Sendable {
    let store: Store
    private let clock: TestClock

    static let defaultNow = Date(timeIntervalSince1970: 1_792_058_400)

    init(now: Date = TestHarness.defaultNow, timeZone: String = "UTC") throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        let clock = TestClock(now)
        self.clock = clock
        store = Store(writer: queue, env: ModelEnvironment(
            now: { clock.now },
            calendar: .fixture(timeZone: timeZone),
            deviceID: "test-device"
        ))
    }

    var now: Date { clock.now }
    var today: Day { store.env.today }

    func advance(seconds: TimeInterval) {
        clock.advance(seconds: seconds)
    }

    func advance(days: Int) {
        advance(seconds: Double(days) * 86_400)
    }

    func item(_ id: String) async throws -> Item {
        try await store.read { db in try Item.fetchOne(db, key: id)! }
    }

    func changes() async throws -> [ChangeRecord] {
        try await store.read { db in try ChangeRecord.order(Column("seq")).fetchAll(db) }
    }

    /// Titles of live, untrashed items matching `condition`, in `order`.
    func titles(where condition: String, order: String = "sortKey", _ arguments: StatementArguments = []) async throws -> [String] {
        try await store.read { db in
            try String.fetchAll(db, sql: "SELECT title FROM item WHERE deletedAt IS NULL AND trashedAt IS NULL AND (\(condition)) ORDER BY \(order)", arguments: arguments)
        }
    }

    /// Live tag IDs on an item.
    func tagIDs(_ itemID: String) async throws -> [String] {
        try await store.read { db in
            try String.fetchAll(db, sql: """
                SELECT item_tag.tagID FROM item_tag JOIN tag ON tag.id = item_tag.tagID
                WHERE item_tag.itemID = ? AND item_tag.deletedAt IS NULL AND tag.deletedAt IS NULL
                """, arguments: [itemID])
        }
    }
}

/// A settable clock shared between a test and its store.
final class TestClock: Sendable {
    private let date: Mutex<Date>

    init(_ date: Date) {
        self.date = Mutex(date)
    }

    var now: Date { date.withLock { $0 } }

    func advance(seconds: TimeInterval) {
        date.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}
```

`Packages/StillpointModel/Tests/StillpointModelTests/PipelineTests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import StillpointModel

/// Tests the write pipeline directly through `perform`, without commands.
struct PipelineTests {
    static func save(_ h: TestHarness, _ change: @escaping @Sendable (inout Item) -> Void, id: String = "a") async throws -> UndoStep {
        try await h.store.perform("edit") { tx in
            var item = try Item.fetchOne(tx.db, key: id)
                ?? Item(id: id, kind: .todo, createdAt: tx.now, sortKey: "V")
            change(&item)
            try tx.save(item)
        }.undo
    }

    @Test func everyWriteAppendsChangeWithChangedFieldsOnly() async throws {
        let h = try TestHarness()
        _ = try await Self.save(h) { $0.title = "A" }
        _ = try await Self.save(h) { $0.title = "B" }
        let changes = try await h.changes()
        #expect(changes.count == 2)
        #expect(changes[1].entity == "item" && changes[1].entityID == "a")
        #expect(changes[1].fieldList == ["title"])
        #expect(changes[0].hlc < changes[1].hlc)
        #expect(changes.allSatisfy { $0.deviceID == "test-device" && $0.pushedAt == nil })
    }

    @Test func noOpWriteIsSkipped() async throws {
        let h = try TestHarness()
        _ = try await Self.save(h) { $0.title = "A" }
        let step = try await Self.save(h) { $0.title = "A" }
        #expect(step.isEmpty)
        #expect(try await h.changes().count == 1)
    }

    @Test func undoAndRedoRoundTrip() async throws {
        let h = try TestHarness()
        _ = try await Self.save(h) { $0.title = "A" }
        let rename = try await Self.save(h) { $0.title = "B" }
        let redo = try await h.store.undo(rename)
        #expect(try await h.item("a").title == "A")
        try await h.store.undo(redo)
        #expect(try await h.item("a").title == "B")
    }

    @Test func undoingCreateTombstonesAndRedoRestores() async throws {
        let h = try TestHarness()
        let created = try await Self.save(h) { $0.title = "A" }
        let redo = try await h.store.undo(created)
        #expect(try await h.item("a").deletedAt != nil)
        try await h.store.undo(redo)
        #expect(try await h.item("a").deletedAt == nil)
    }

    @Test func undoingAnOlderStepKeepsLaterEditsToOtherFields() async throws {
        let h = try TestHarness()
        _ = try await Self.save(h) { $0.title = "A" }
        let rename = try await Self.save(h) { $0.title = "B" }
        _ = try await Self.save(h) { $0.notes = "later note" }
        try await h.store.undo(rename)
        let item = try await h.item("a")
        #expect(item.title == "A")
        #expect(item.notes == "later note")
    }

    @Test func manyRowsInOneStepUndoTogether() async throws {
        let h = try TestHarness()
        _ = try await Self.save(h, { $0.title = "A" }, id: "a")
        _ = try await Self.save(h, { $0.title = "B" }, id: "b")
        let step = try await h.store.perform("bulk") { tx in
            for id in ["a", "b"] {
                var item = try Item.fetchOne(tx.db, key: id)!
                item.bucket = .someday
                try tx.save(item)
            }
        }.undo
        try await h.store.undo(step)
        #expect(try await h.item("a").bucket == .inbox)
        #expect(try await h.item("b").bucket == .inbox)
    }

    @Test func failedTransactionWritesNothing() async throws {
        let h = try TestHarness()
        await #expect(throws: ModelError.self) {
            try await h.store.perform("broken") { tx in
                try tx.save(Item(id: "ok", kind: .todo, createdAt: tx.now, sortKey: "V"))
                var bad = Item(id: "bad", kind: .todo, createdAt: tx.now, sortKey: "W")
                bad.isEvening = true // violates "This Evening requires a start date"
                try tx.save(bad)
            }
        }
        #expect(try await h.changes().isEmpty)
        #expect(try await h.store.read { db in try Item.fetchCount(db) } == 0)
    }
}
```

`Packages/StillpointModel/Tests/StillpointModelTests/RulesTests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import StillpointModel

/// Each test writes a deliberately broken item directly through a transaction.
struct RulesTests {
    /// Seeds project "P", project "Q" and heading "H" (in Q), then expects `build` to be rejected.
    func expectViolation(_ build: @escaping @Sendable (Transaction) throws -> Item) async throws {
        let h = try TestHarness()
        try await h.store.perform("seed") { tx in
            let p = Item(id: "P", kind: .project, title: "P", createdAt: tx.now, bucket: .anytime, sortKey: "V")
            let q = Item(id: "Q", kind: .project, title: "Q", createdAt: tx.now, bucket: .anytime, sortKey: "W")
            var heading = Item(id: "H", kind: .heading, title: "H", createdAt: tx.now, bucket: .anytime, sortKey: "X")
            heading.projectID = "Q"
            try tx.save(p)
            try tx.save(q)
            try tx.save(heading)
        }
        await #expect(throws: ModelError.self) {
            try await h.store.perform("test") { tx in
                try tx.save(try build(tx))
            }
        }
    }

    static func todo(_ tx: Transaction) -> Item {
        Item(id: tx.newID(), kind: .todo, createdAt: tx.now, bucket: .anytime, sortKey: "V")
    }

    static func id(_ tx: Transaction, titled title: String) throws -> String {
        try String.fetchOne(tx.db, sql: "SELECT id FROM item WHERE title = ?", arguments: [title])!
    }

    @Test func headingNeedsProject() async throws {
        try await expectViolation { tx in
            Item(id: tx.newID(), kind: .heading, createdAt: tx.now, bucket: .anytime, sortKey: "V")
        }
    }

    @Test func projectsCantNest() async throws {
        try await expectViolation { tx in
            var p = Item(id: tx.newID(), kind: .project, createdAt: tx.now, bucket: .anytime, sortKey: "V")
            p.projectID = try Self.id(tx, titled: "P")
            return p
        }
    }

    @Test func todoMustBeInItsHeadingsProject() async throws {
        try await expectViolation { tx in
            var t = Self.todo(tx)
            t.projectID = try Self.id(tx, titled: "P")
            t.headingID = try Self.id(tx, titled: "H") // H belongs to Q
            return t
        }
    }

    @Test func todoInProjectHasNoArea() async throws {
        try await expectViolation { tx in
            let area = Area(id: tx.newID(), title: "A", createdAt: tx.now, sortKey: "V")
            try tx.save(area)
            var t = Self.todo(tx)
            t.projectID = try Self.id(tx, titled: "P")
            t.areaID = area.id
            return t
        }
    }

    @Test func startDayRequiresAnytime() async throws {
        try await expectViolation { tx in
            var t = Self.todo(tx)
            t.bucket = .someday
            t.startDay = tx.today
            return t
        }
    }

    @Test func eveningRequiresStartDay() async throws {
        try await expectViolation { tx in
            var t = Self.todo(tx)
            t.isEvening = true
            return t
        }
    }

    @Test func inboxItemsHaveNoParentOrDate() async throws {
        try await expectViolation { tx in
            var t = Self.todo(tx)
            t.bucket = .inbox
            t.projectID = try Self.id(tx, titled: "P")
            return t
        }
    }

    @Test func checklistParentMustBeTodo() async throws {
        let h = try TestHarness()
        await #expect(throws: ModelError.self) {
            try await h.store.perform("test") { tx in
                try tx.save(Item(id: "P", kind: .project, createdAt: tx.now, bucket: .anytime, sortKey: "V"))
                try tx.save(ChecklistItem(id: "c", itemID: "P", title: "x", createdAt: tx.now, sortKey: "V"))
            }
        }
    }

    @Test func validWritesPass() async throws {
        let h = try TestHarness()
        try await h.store.perform("valid") { tx in
            let project = Item(id: "P", kind: .project, createdAt: tx.now, bucket: .anytime, sortKey: "V")
            var heading = Item(id: "H", kind: .heading, createdAt: tx.now, bucket: .anytime, sortKey: "W")
            heading.projectID = "P"
            var todo = Item(id: "T", kind: .todo, createdAt: tx.now, bucket: .anytime, sortKey: "X")
            todo.projectID = "P"
            todo.headingID = "H"
            todo.startDay = tx.today
            todo.isEvening = true
            try tx.save(project)
            try tx.save(heading)
            try tx.save(todo)
        }
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd Packages/StillpointModel && swift test`
Expected: the build fails with `error: cannot find 'Store' in scope`.

- [ ] **Step 3: Implement**

`Packages/StillpointModel/Sources/StillpointModel/Store/ModelError.swift`:

```swift
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
}
```

`Packages/StillpointModel/Sources/StillpointModel/Store/UndoStep.swift`:

```swift
import GRDB

/// A row before and after one user action. `before == nil` means the row was created.
public struct RowSnapshot: Sendable, Equatable {
    public let table: String
    public let entityID: String
    public let primaryKey: [String: DatabaseValue]
    public let before: [String: DatabaseValue]?
    public var after: [String: DatabaseValue]
}

/// Everything needed to reverse one user action. Pass it to `Store.undo(_:)`,
/// which returns the step that redoes it.
public struct UndoStep: Sendable, Equatable {
    public let name: String
    public let snapshots: [RowSnapshot]

    public var isEmpty: Bool { snapshots.isEmpty }
}

/// The result of a command: its return value plus the step that undoes it.
public struct Committed<Value: Sendable>: Sendable {
    public let value: Value
    public let undo: UndoStep
}
```

`Packages/StillpointModel/Sources/StillpointModel/Store/Transaction.swift`:

```swift
import Foundation
import GRDB

/// The context every command runs in. Writes go through `save(_:)`, which
/// validates rules, skips no-op writes, appends to the change log and
/// records undo snapshots.
public final class Transaction {
    public let db: Database
    public let env: ModelEnvironment
    public let now: Date
    public let today: Day
    let clock: HybridClock

    private(set) var snapshots: [RowSnapshot] = []
    private var snapshotIndex: [String: Int] = [:]

    init(db: Database, env: ModelEnvironment, clock: HybridClock) {
        self.db = db
        self.env = env
        self.now = env.now()
        self.today = Day(now, calendar: env.calendar)
        self.clock = clock
    }

    public func newID() -> String {
        EntityID.make(at: now)
    }

    /// Insert or update a record.
    public func save<R: SyncedRecord>(_ record: R) throws {
        if let item = record as? Item {
            try Rules.validate(item, in: self)
        } else if let checklistItem = record as? ChecklistItem {
            try Rules.validate(checklistItem, in: self)
        }
        try write(
            table: R.databaseTableName,
            entityID: record.entityID,
            primaryKey: record.primaryKey,
            values: record.databaseDictionary
        )
    }

    /// Tombstone a record so the deletion can sync.
    public func delete<R: SyncedRecord>(_ record: R) throws {
        var tombstone = record
        tombstone.deletedAt = now
        try write(
            table: R.databaseTableName,
            entityID: tombstone.entityID,
            primaryKey: tombstone.primaryKey,
            values: tombstone.databaseDictionary
        )
    }

    /// Writes raw column values. Used by `save` and by undo.
    func write(table: String, entityID: String, primaryKey: [String: DatabaseValue], values: [String: DatabaseValue]) throws {
        let current = try fetchRow(table: table, primaryKey: primaryKey)
        var values = values
        values["modifiedAt"] = now.timeIntervalSince1970.databaseValue
        let changed = values.keys.filter { $0 != "modifiedAt" && current?[$0] != values[$0] }
        if current != nil, changed.isEmpty {
            return
        }

        let columns = values.keys.sorted()
        let columnList = columns.map(\.quotedDatabaseIdentifier).joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
        try db.execute(
            sql: "INSERT OR REPLACE INTO \(table.quotedDatabaseIdentifier) (\(columnList)) VALUES (\(placeholders))",
            arguments: StatementArguments(columns.map { values[$0]! })
        )

        var change = ChangeRecord(entity: table, entityID: entityID, fields: changed, hlc: clock.tick(), deviceID: env.deviceID)
        try change.insert(db)

        let key = "\(table)|\(entityID)"
        if let index = snapshotIndex[key] {
            snapshots[index].after = values
        } else {
            snapshotIndex[key] = snapshots.count
            snapshots.append(RowSnapshot(table: table, entityID: entityID, primaryKey: primaryKey, before: current, after: values))
        }
    }

    func fetchRow(table: String, primaryKey: [String: DatabaseValue]) throws -> [String: DatabaseValue]? {
        let columns = primaryKey.keys.sorted()
        let condition = columns.map { "\($0.quotedDatabaseIdentifier) = ?" }.joined(separator: " AND ")
        let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM \(table.quotedDatabaseIdentifier) WHERE \(condition)",
            arguments: StatementArguments(columns.map { primaryKey[$0]! })
        )
        return row.map { Dictionary($0.map { ($0, $1) }, uniquingKeysWith: { first, _ in first }) }
    }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Store/Rules.swift`:

```swift
import GRDB

/// The data rules from spec §4.3, checked on every item write.
enum Rules {
    static func validate(_ item: Item, in tx: Transaction) throws {
        func fail(_ message: String) -> ModelError {
            .ruleViolation("\(item.kind) \(item.id): \(message)")
        }

        switch item.kind {
        case .heading:
            guard let projectID = item.projectID else { throw fail("heading needs a project") }
            guard item.headingID == nil, item.areaID == nil else { throw fail("heading can't have a heading or area") }
            try requireLive(projectID, kind: .project, in: tx, else: fail("heading's project not found"))
        case .project:
            guard item.projectID == nil, item.headingID == nil else { throw fail("projects can't be nested") }
        case .todo:
            if let projectID = item.projectID {
                guard item.areaID == nil else { throw fail("to-do in a project inherits the project's area") }
                try requireLive(projectID, kind: .project, in: tx, else: fail("project not found"))
            }
            if let headingID = item.headingID {
                let heading = try Item.fetchOne(tx.db, key: headingID)
                guard let heading, heading.kind == .heading, heading.deletedAt == nil else { throw fail("heading not found") }
                guard heading.projectID == item.projectID else { throw fail("to-do must be in its heading's project") }
            }
        }

        if item.bucket == .inbox {
            guard item.kind == .todo else { throw fail("only to-dos can be in the Inbox") }
            guard item.projectID == nil, item.areaID == nil else { throw fail("Inbox to-dos have no project or area") }
            guard item.startDay == nil else { throw fail("Inbox to-dos have no start date") }
        }
        if item.startDay != nil, item.bucket != .anytime {
            throw fail("a start date requires the anytime bucket")
        }
        if item.isEvening, item.startDay == nil {
            throw fail("This Evening requires a start date")
        }
        if item.reminderTime != nil, item.startDay == nil {
            throw fail("a reminder requires a start date")
        }
        if let areaID = item.areaID {
            let area = try Area.fetchOne(tx.db, key: areaID)
            guard let area, area.deletedAt == nil else { throw fail("area not found") }
        }
    }

    static func validate(_ checklistItem: ChecklistItem, in tx: Transaction) throws {
        let parent = try Item.fetchOne(tx.db, key: checklistItem.itemID)
        guard let parent, parent.kind == .todo else {
            throw ModelError.ruleViolation("checklist item \(checklistItem.id): parent must be a to-do")
        }
    }

    private static func requireLive(_ id: String, kind: ItemKind, in tx: Transaction, else error: ModelError) throws {
        let item = try Item.fetchOne(tx.db, key: id)
        guard let item, item.kind == kind, item.deletedAt == nil else { throw error }
    }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Store/Store.swift`:

```swift
import Foundation
import GRDB

/// The entry point to the model. All writes are commands (see `Commands/`),
/// each one transaction that returns an `UndoStep`.
public final class Store: Sendable {
    public let writer: any DatabaseWriter
    public let env: ModelEnvironment
    let clock: HybridClock

    public init(writer: any DatabaseWriter, env: ModelEnvironment) {
        self.writer = writer
        self.env = env
        self.clock = HybridClock(deviceID: env.deviceID, now: env.now)
    }

    /// Runs `body` in one write transaction.
    public func perform<Value: Sendable>(
        _ name: String,
        _ body: @escaping @Sendable (Transaction) throws -> Value
    ) async throws -> Committed<Value> {
        let env = self.env
        let clock = self.clock
        do {
            return try await writer.write { db in
                let tx = Transaction(db: db, env: env, clock: clock)
                let value = try body(tx)
                return Committed(value: value, undo: UndoStep(name: name, snapshots: tx.snapshots))
            }
        } catch let error as ModelError {
            if case .ruleViolation = error, env.assertOnRuleViolation {
                assertionFailure("\(error)")
            }
            throw error
        }
    }

    /// Reverses `step` and returns the step that redoes it.
    @discardableResult
    public func undo(_ step: UndoStep) async throws -> UndoStep {
        try await perform(step.name) { tx in
            for snapshot in step.snapshots.reversed() {
                let current = try tx.fetchRow(table: snapshot.table, primaryKey: snapshot.primaryKey) ?? snapshot.after
                var target = current
                if let before = snapshot.before {
                    // Reverse only the fields this step changed, so later edits
                    // to other fields of the same row survive.
                    for (column, value) in before where column != "modifiedAt" && snapshot.after[column] != value {
                        target[column] = value
                    }
                } else {
                    // Undoing a creation tombstones the row.
                    target["deletedAt"] = tx.now.timeIntervalSince1970.databaseValue
                }
                try tx.write(table: snapshot.table, entityID: snapshot.entityID, primaryKey: snapshot.primaryKey, values: target)
            }
        }.undo
    }

    public func read<Value: Sendable>(_ body: @escaping @Sendable (Database) throws -> Value) async throws -> Value {
        try await writer.read(body)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd Packages/StillpointModel && swift test`
Expected: `✔ Test run with 31 tests … passed`, with no compiler warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/StillpointModel/Sources/StillpointModel/Store/ModelError.swift Packages/StillpointModel/Sources/StillpointModel/Store/UndoStep.swift Packages/StillpointModel/Sources/StillpointModel/Store/Transaction.swift Packages/StillpointModel/Sources/StillpointModel/Store/Rules.swift Packages/StillpointModel/Sources/StillpointModel/Store/Store.swift Packages/StillpointModel/Tests/StillpointModelTests/TestHarness.swift Packages/StillpointModel/Tests/StillpointModelTests/PipelineTests.swift Packages/StillpointModel/Tests/StillpointModelTests/RulesTests.swift
git commit -m "feat(model): write pipeline with rules, change log and field-level undo"
```

### Task 6: Item, area, tag, checklist and settings commands

The commands behind New To-Do / Project / Heading, When, Deadline, Reminder, Complete/Cancel, Trash / Put Back / Empty Trash, Duplicate, plus areas, tags (nesting, ⌃-shortcuts, toggle), checklists and settings.
**Files:**
- Create: `Packages/StillpointModel/Sources/StillpointModel/Commands/Destination.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Commands/TransactionHelpers.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Commands/ItemCommands.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Commands/AreaTagChecklistCommands.swift`
- Test: `Packages/StillpointModel/Tests/StillpointModelTests/ItemCommandTests.swift`
- Test: `Packages/StillpointModel/Tests/StillpointModelTests/AreaTagChecklistTests.swift`

**Interfaces:**
- Consumes: `Store`, `Transaction`, records (Tasks 4–5)
- Produces:
- `enum Destination` (`inbox`, `anytime`, `someday`, `today`, `evening`, `area(id)`, `project(id)`, `heading(id)`), `enum When` (`today`, `evening`, `day(Day)`, `someday`, `clear`), `enum OpenItemsDecision` (`complete`, `cancel`), `enum OrderColumn` (`sortKey`, `todaySortKey`)
- `Store`: `createTodo(title:notes:in:after:) -> Committed<String>`, `createProject(title:areaID:someday:)`, `createHeading(title:projectID:after:)`, `rename(_:to:)`, `setNotes(_:_:)`, `schedule(_ ids:, _ when:)`, `shiftStart(_:byDays:)`, `setDeadline(_:_:)`, `setReminder(_:minutes:)`, `setStatus(_:_:openItems:)`, `trash(_:)`, `putBack(_:)`, `emptyTrash()`, `duplicate(_:) -> Committed<[String]>`
- `Store`: `createArea(title:)`, `updateArea(_:_:)`, `reorderArea(_:after:before:)`, `deleteArea(_:)`, `setAreaTags(_:_:)`, `createTag(title:parentID:)`, `renameTag`, `setTagShortcut`, `setTagParent`, `deleteTag`, `setTags(_:_:)`, `toggleTag(_:_:)`, `addChecklistItem(to:title:after:)`, `updateChecklistItem(_:_:)`, `reorderChecklistItem(_:after:before:)`, `deleteChecklistItem(_:)`, `static settings(in:now:) -> Settings`, `updateSettings(_:)` (rejects log-policy changes)
- Internal: `Container` (key spaces), `Transaction.item(_:)`, `liveItems(where:_:)`, `newKeys(_:column:in:after:)`, `keysBetween(_:column:after:before:)`, `openTodos(under:)`, `Store.trash(_:in:)`, `Store.detachFromMissingParents(_:in:)`

- [ ] **Step 1: Write the failing tests**

`Packages/StillpointModel/Tests/StillpointModelTests/ItemCommandTests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import StillpointModel

struct ItemCommandTests {
    @Test func createTodoInInboxAppendsInOrder() async throws {
        let h = try TestHarness()
        let a = try await h.store.createTodo(title: "A", in: .inbox).value
        let b = try await h.store.createTodo(title: "B", in: .inbox).value
        let c = try await h.store.createTodo(title: "C", in: .inbox, after: a).value
        let keys = try await [h.item(a), h.item(c), h.item(b)].map(\.sortKey)
        #expect(keys == keys.sorted())
        #expect(try await h.item(a).bucket == .inbox)
    }

    @Test func createInTodayAndEvening() async throws {
        let h = try TestHarness()
        let t = try await h.item(h.store.createTodo(title: "T", in: .today).value)
        let e = try await h.item(h.store.createTodo(title: "E", in: .evening).value)
        #expect(t.startDay == h.today && !t.isEvening && t.bucket == .anytime && t.todaySortKey != nil)
        #expect(e.startDay == h.today && e.isEvening)
    }

    @Test func createInHeadingUsesHeadingsProject() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let heading = try await h.store.createHeading(title: "H", projectID: project).value
        let todo = try await h.item(h.store.createTodo(title: "x", in: .heading(heading)).value)
        #expect(todo.projectID == project && todo.headingID == heading && todo.areaID == nil)
    }

    @Test func schedulingMovesOutOfInbox() async throws {
        let h = try TestHarness()
        let id = try await h.store.createTodo(title: "x", in: .inbox).value
        try await h.store.schedule([id], .day(h.today.adding(days: 3, calendar: .fixture())))
        var item = try await h.item(id)
        #expect(item.bucket == .anytime && item.startDay == h.today.adding(days: 3, calendar: .fixture()))

        try await h.store.schedule([id], .someday)
        item = try await h.item(id)
        #expect(item.bucket == .someday && item.startDay == nil)

        try await h.store.schedule([id], .clear)
        item = try await h.item(id)
        #expect(item.bucket == .anytime && item.startDay == nil)
    }

    @Test func pastDayMeansToday() async throws {
        let h = try TestHarness()
        let id = try await h.store.createTodo(in: .anytime).value
        try await h.store.schedule([id], .day(h.today.adding(days: -5, calendar: .fixture())))
        #expect(try await h.item(id).startDay == h.today)
    }

    @Test func shiftStartIsOneUndoStepAndNeverBeforeToday() async throws {
        let h = try TestHarness()
        let a = try await h.store.createTodo(in: .anytime).value
        let b = try await h.store.createTodo(in: .today).value
        let shift = try await h.store.shiftStart([a, b], byDays: 1)
        let tomorrow = h.today.adding(days: 1, calendar: .fixture())
        #expect(try await h.item(a).startDay == tomorrow)
        #expect(try await h.item(b).startDay == tomorrow)
        try await h.store.undo(shift.undo)
        #expect(try await h.item(a).startDay == nil)
        #expect(try await h.item(b).startDay == h.today)
        try await h.store.shiftStart([b], byDays: -3)
        #expect(try await h.item(b).startDay == h.today)
    }

    @Test func reminderSchedulesForTodayWhenUnscheduled() async throws {
        let h = try TestHarness()
        let id = try await h.store.createTodo(in: .inbox).value
        try await h.store.setReminder(id, minutes: 9 * 60)
        let item = try await h.item(id)
        #expect(item.reminderTime == 540 && item.startDay == h.today && item.bucket == .anytime)
    }

    @Test func completingProjectWithOpenTodosNeedsDecision() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let heading = try await h.store.createHeading(title: "H", projectID: project).value
        let todo = try await h.store.createTodo(in: .heading(heading)).value
        await #expect(throws: ModelError.projectHasOpenItems(count: 1)) {
            try await h.store.setStatus([project], .completed)
        }
        try await h.store.setStatus([project], .completed, openItems: .cancel)
        #expect(try await h.item(todo).status == .canceled)
        #expect(try await h.item(heading).status == .completed)
        #expect(try await h.item(project).stopDate == h.now)
    }

    @Test func archivingHeadingRequiresItsTodosDone() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let heading = try await h.store.createHeading(title: "H", projectID: project).value
        let todo = try await h.store.createTodo(in: .heading(heading)).value
        await #expect(throws: ModelError.headingHasOpenItems(count: 1)) {
            try await h.store.setStatus([heading], .completed)
        }
        try await h.store.setStatus([todo], .completed)
        try await h.store.setStatus([heading], .completed)
        #expect(try await h.item(heading).status == .completed)
    }

    @Test func trashAndPutBackProjectWithChildren() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let todo = try await h.store.createTodo(in: .project(project)).value
        try await h.store.trash([project])
        #expect(try await h.item(todo).trashedAt != nil)
        try await h.store.putBack([project])
        #expect(try await h.item(project).trashedAt == nil)
        #expect(try await h.item(todo).trashedAt == nil)
        #expect(try await h.item(todo).projectID == project)
    }

    @Test func puttingBackTodoWhoseProjectIsStillTrashedSendsItToInbox() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let todo = try await h.store.createTodo(in: .project(project)).value
        try await h.store.trash([project])
        try await h.store.putBack([todo])
        let item = try await h.item(todo)
        #expect(item.projectID == nil && item.bucket == .inbox && item.trashedAt == nil)
    }

    @Test func emptyTrashTombstones() async throws {
        let h = try TestHarness()
        let id = try await h.store.createTodo(in: .inbox).value
        _ = try await h.store.addChecklistItem(to: id, title: "step")
        try await h.store.trash([id])
        try await h.store.emptyTrash()
        #expect(try await h.item(id).deletedAt == h.now)
        let liveChecklist = try await h.store.read { db in
            try ChecklistItem.filter(Column("deletedAt") == nil).fetchCount(db)
        }
        #expect(liveChecklist == 0)
    }

    @Test func duplicateProjectCopiesHeadingsTodosChecklistAndTags() async throws {
        let h = try TestHarness()
        let tag = try await h.store.createTag(title: "Home").value
        let project = try await h.store.createProject(title: "P").value
        let heading = try await h.store.createHeading(title: "H", projectID: project).value
        let todo = try await h.store.createTodo(title: "x", in: .heading(heading)).value
        _ = try await h.store.addChecklistItem(to: todo, title: "step")
        try await h.store.setTags([todo], [tag])

        let copyID = try await h.store.duplicate([project]).value[0]
        let children = try await h.store.read { db in
            try Item.filter(Column("projectID") == copyID).fetchAll(db)
        }
        let copiedHeading = try #require(children.first { $0.kind == .heading })
        let copiedTodo = try #require(children.first { $0.kind == .todo })
        #expect(copiedTodo.headingID == copiedHeading.id)
        let details = try await h.store.read { db in
            (try ChecklistItem.filter(Column("itemID") == copiedTodo.id).fetchCount(db),
             try ItemTag.filter(Column("itemID") == copiedTodo.id).fetchCount(db))
        }
        #expect(details == (1, 1))
        #expect(try await h.item(copyID).sortKey > h.item(project).sortKey)
    }
}
```

`Packages/StillpointModel/Tests/StillpointModelTests/AreaTagChecklistTests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import StillpointModel

struct AreaTagChecklistTests {
    @Test func deletingAreaTrashesContentAndPutBackDetachesIt() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Old").value
        let project = try await h.store.createProject(title: "P", areaID: area).value
        let todo = try await h.store.createTodo(title: "t", in: .area(area)).value
        try await h.store.deleteArea(area)
        #expect(try await h.item(project).trashedAt != nil)
        #expect(try await h.item(todo).trashedAt != nil)
        try await h.store.putBack([todo, project])
        #expect(try await h.item(todo).areaID == nil)
        #expect(try await h.item(todo).bucket == .anytime)
        #expect(try await h.item(project).areaID == nil)
    }

    @Test func areaReorderAndUpdate() async throws {
        let h = try TestHarness()
        let a = try await h.store.createArea(title: "A").value
        let b = try await h.store.createArea(title: "B").value
        try await h.store.reorderArea(b, after: nil, before: a)
        try await h.store.updateArea(a) { $0.isCollapsed = true }
        let areas = try await h.store.read { db in try Area.order(Column("sortKey")).fetchAll(db) }
        #expect(areas.map(\.title) == ["B", "A"])
        #expect(areas[1].isCollapsed)
    }

    @Test func tagShortcutsAreUniqueCaseInsensitively() async throws {
        let h = try TestHarness()
        let home = try await h.store.createTag(title: "Home").value
        let work = try await h.store.createTag(title: "Work").value
        try await h.store.setTagShortcut(home, "H")
        await #expect(throws: ModelError.duplicateShortcut("h")) {
            try await h.store.setTagShortcut(work, "h")
        }
        try await h.store.setTagShortcut(home, nil)
        try await h.store.setTagShortcut(work, "h")
    }

    @Test func tagNestingRefusesCycles() async throws {
        let h = try TestHarness()
        let a = try await h.store.createTag(title: "A").value
        let b = try await h.store.createTag(title: "B", parentID: a).value
        await #expect(throws: ModelError.self) { try await h.store.setTagParent(a, b) }
        await #expect(throws: ModelError.self) { try await h.store.setTagParent(a, a) }
    }

    @Test func deletingTagRemovesNestedTagsAndLinks() async throws {
        let h = try TestHarness()
        let parent = try await h.store.createTag(title: "P").value
        let child = try await h.store.createTag(title: "C", parentID: parent).value
        let todo = try await h.store.createTodo(in: .inbox).value
        try await h.store.setTags([todo], [child])
        try await h.store.deleteTag(parent)
        let live = try await h.store.read { db in
            (try Tag.filter(Column("deletedAt") == nil).fetchCount(db),
             try ItemTag.filter(Column("deletedAt") == nil).fetchCount(db))
        }
        #expect(live == (0, 0))
        #expect(try await h.tagIDs(todo).isEmpty)
    }

    @Test func toggleTagAddsToAllUnlessAllHaveIt() async throws {
        let h = try TestHarness()
        let tag = try await h.store.createTag(title: "T").value
        let a = try await h.store.createTodo(in: .inbox).value
        let b = try await h.store.createTodo(in: .inbox).value
        try await h.store.setTags([a], [tag])
        try await h.store.toggleTag([a, b], tag)
        #expect(try await h.tagIDs(a) == [tag])
        #expect(try await h.tagIDs(b) == [tag])
        try await h.store.toggleTag([a, b], tag)
        #expect(try await h.tagIDs(a).isEmpty)
        #expect(try await h.tagIDs(b).isEmpty)
        try await h.store.toggleTag([a], tag) // re-adding revives the tombstoned link
        #expect(try await h.tagIDs(a) == [tag])
    }

    @Test func checklistInsertAfterAndReorder() async throws {
        let h = try TestHarness()
        let todo = try await h.store.createTodo(in: .inbox).value
        let one = try await h.store.addChecklistItem(to: todo, title: "one").value
        let three = try await h.store.addChecklistItem(to: todo, title: "three").value
        _ = try await h.store.addChecklistItem(to: todo, title: "two", after: one)
        func titles() async throws -> [String] {
            try await h.store.read { db in
                try ChecklistItem.filter(Column("itemID") == todo && Column("deletedAt") == nil).order(Column("sortKey")).fetchAll(db).map(\.title)
            }
        }
        #expect(try await titles() == ["one", "two", "three"])
        try await h.store.reorderChecklistItem(three, after: nil, before: one)
        #expect(try await titles() == ["three", "one", "two"])
        try await h.store.deleteChecklistItem(three)
        #expect(try await titles() == ["one", "two"])
    }

}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd Packages/StillpointModel && swift test`
Expected: the build fails with `error: value of type 'Store' has no member 'createTodo'`.

- [ ] **Step 3: Implement**

`Packages/StillpointModel/Sources/StillpointModel/Commands/Destination.swift`:

```swift
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
```

`Packages/StillpointModel/Sources/StillpointModel/Commands/TransactionHelpers.swift`:

```swift
import GRDB

/// A set of items that share one ordering ("key space").
struct Container {
    let sql: String
    let arguments: StatementArguments

    static let inbox = Container(sql: "kind = 0 AND bucket = 0", arguments: [])
    static let today = Container(sql: "todaySortKey IS NOT NULL", arguments: [])
    static func noParent(_ bucket: Bucket) -> Container {
        Container(sql: "kind = 0 AND projectID IS NULL AND areaID IS NULL AND bucket = ?", arguments: [bucket.rawValue])
    }
    static func areaTodos(_ areaID: String) -> Container {
        Container(sql: "kind = 0 AND projectID IS NULL AND areaID = ?", arguments: [areaID])
    }
    static func projects(inArea areaID: String?) -> Container {
        Container(sql: "kind = 1 AND areaID IS ?", arguments: [areaID])
    }
    static func project(_ projectID: String) -> Container {
        Container(sql: "projectID = ?", arguments: [projectID])
    }

    /// The container an item currently belongs to.
    static func of(_ item: Item) -> Container {
        if item.kind == .project { return .projects(inArea: item.areaID) }
        if let projectID = item.projectID { return .project(projectID) }
        if let areaID = item.areaID { return .areaTodos(areaID) }
        if item.bucket == .inbox { return .inbox }
        return .noParent(item.bucket)
    }
}

extension Transaction {
    /// A live (not tombstoned) item.
    func item(_ id: String) throws -> Item {
        guard let item = try Item.fetchOne(db, key: id), item.deletedAt == nil else {
            throw ModelError.notFound("item \(id)")
        }
        return item
    }

    func items(_ ids: [String]) throws -> [Item] {
        try ids.map(item)
    }

    /// Live, untrashed items matching `sql`.
    func liveItems(where sql: String, _ arguments: StatementArguments = []) throws -> [Item] {
        try Item.fetchAll(db, sql: "SELECT * FROM item WHERE deletedAt IS NULL AND (\(sql)) ORDER BY sortKey", arguments: arguments)
    }

    /// `count` new keys for `column` in `container`: after `afterID` (before its
    /// next sibling) or, with no `afterID`, at the end.
    func newKeys(_ count: Int, column: OrderColumn = .sortKey, in container: Container, after afterID: String? = nil) throws -> [String] {
        let col = column.rawValue
        if let afterID,
           let lower = try String.fetchOne(db, sql: "SELECT \(col) FROM item WHERE id = ?", arguments: [afterID]) {
            let upper = try String.fetchOne(
                db,
                sql: "SELECT MIN(\(col)) FROM item WHERE deletedAt IS NULL AND (\(container.sql)) AND \(col) > ?",
                arguments: container.arguments + [lower]
            )
            return SortKey.sequence(count: count, after: lower, before: upper)
        }
        let last = try String.fetchOne(
            db,
            sql: "SELECT MAX(\(col)) FROM item WHERE deletedAt IS NULL AND (\(container.sql))",
            arguments: container.arguments
        )
        return SortKey.sequence(count: count, after: last, before: nil)
    }

    /// Keys strictly between two neighbouring items' keys. Throws if the
    /// neighbours are out of order (they must come from the same displayed list).
    func keysBetween(_ count: Int, column: OrderColumn, after afterID: String?, before beforeID: String?) throws -> [String] {
        let col = column.rawValue
        func key(_ id: String?) throws -> String? {
            guard let id else { return nil }
            return try String.fetchOne(db, sql: "SELECT \(col) FROM item WHERE id = ?", arguments: [id])
        }
        let lower = try key(afterID)
        let upper = try key(beforeID)
        if let lower, let upper, lower >= upper {
            throw ModelError.invalidMove("neighbours out of order")
        }
        return SortKey.sequence(count: count, after: lower, before: upper)
    }

    /// Open, untrashed to-dos directly under a project or heading.
    func openTodos(under parentID: String) throws -> [Item] {
        try liveItems(where: "kind = 0 AND status = 0 AND trashedAt IS NULL AND (projectID = ? OR headingID = ?)", [parentID, parentID])
    }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Commands/ItemCommands.swift`:

```swift
import Foundation
import GRDB

extension Store {
    // MARK: Create

    /// Creates a to-do in `destination`, at the end or right after `afterID`.
    @discardableResult
    public func createTodo(
        title: String = "", notes: String = "", in destination: Destination, after afterID: String? = nil
    ) async throws -> Committed<String> {
        try await perform("New To-Do") { tx in
            var item = Item(id: tx.newID(), kind: .todo, title: title, createdAt: tx.now, sortKey: "")
            item.notes = notes
            let container: Container
            switch destination {
            case .inbox:
                item.bucket = .inbox
                container = .inbox
            case .anytime, .today, .evening:
                item.bucket = .anytime
                container = .noParent(.anytime)
            case .someday:
                item.bucket = .someday
                container = .noParent(.someday)
            case .area(let areaID):
                item.bucket = .anytime
                item.areaID = areaID
                container = .areaTodos(areaID)
            case .project(let projectID):
                item.bucket = .anytime
                item.projectID = projectID
                container = .project(projectID)
            case .heading(let headingID):
                let heading = try tx.item(headingID)
                item.bucket = .anytime
                item.projectID = heading.projectID
                item.headingID = headingID
                container = .project(heading.projectID ?? "")
            }
            if destination == .today || destination == .evening {
                item.startDay = tx.today
                item.isEvening = destination == .evening
                item.todaySortKey = try tx.newKeys(1, column: .todaySortKey, in: .today, after: afterID)[0]
                item.sortKey = try tx.newKeys(1, in: container)[0]
            } else {
                item.sortKey = try tx.newKeys(1, in: container, after: afterID)[0]
            }
            try tx.save(item)
            return item.id
        }
    }

    @discardableResult
    public func createProject(title: String, areaID: String? = nil, someday: Bool = false) async throws -> Committed<String> {
        try await perform("New Project") { tx in
            var project = Item(id: tx.newID(), kind: .project, title: title, createdAt: tx.now, bucket: someday ? .someday : .anytime, sortKey: "")
            project.areaID = areaID
            project.sortKey = try tx.newKeys(1, in: .projects(inArea: areaID))[0]
            try tx.save(project)
            return project.id
        }
    }

    /// Creates a heading at the end of a project, or after `afterID` (an item in that project).
    @discardableResult
    public func createHeading(title: String, projectID: String, after afterID: String? = nil) async throws -> Committed<String> {
        try await perform("New Heading") { tx in
            var heading = Item(id: tx.newID(), kind: .heading, title: title, createdAt: tx.now, bucket: .anytime, sortKey: "")
            heading.projectID = projectID
            heading.sortKey = try tx.newKeys(1, in: .project(projectID), after: afterID)[0]
            try tx.save(heading)
            return heading.id
        }
    }

    // MARK: Edit

    @discardableResult
    public func rename(_ id: String, to title: String) async throws -> Committed<Void> {
        try await perform("Rename") { tx in
            var item = try tx.item(id)
            item.title = title
            try tx.save(item)
        }
    }

    @discardableResult
    public func setNotes(_ id: String, _ notes: String) async throws -> Committed<Void> {
        try await perform("Edit Notes") { tx in
            var item = try tx.item(id)
            item.notes = notes
            try tx.save(item)
        }
    }

    // MARK: When / Deadline / Reminder

    @discardableResult
    public func schedule(_ ids: [String], _ when: When) async throws -> Committed<Void> {
        try await perform("When") { tx in
            let items = try tx.items(ids)
            try Store.apply(items.map { ($0, when) }, in: tx)
        }
    }

    /// ⌃] / ⌃[ : moves each start date by `days` (unscheduled items count
    /// from today), never earlier than today.
    @discardableResult
    public func shiftStart(_ ids: [String], byDays days: Int) async throws -> Committed<Void> {
        try await perform("When") { tx in
            let changes = try tx.items(ids).map { item -> (Item, When) in
                let base = item.startDay ?? tx.today
                let target = max(base.adding(days: days, calendar: tx.env.calendar), tx.today)
                return (item, .day(target))
            }
            try Store.apply(changes, in: tx)
        }
    }

    static func apply(_ changes: [(Item, When)], in tx: Transaction) throws {
        let todayKeys = try tx.newKeys(changes.count, column: .todaySortKey, in: .today)
        for (index, (original, when)) in changes.enumerated() {
            guard original.kind != .heading else {
                throw ModelError.ruleViolation("headings can't be scheduled")
            }
            var item = original
            var resolved = when
            if case .day(let day) = when, day <= tx.today {
                resolved = .today
            }
            switch resolved {
            case .today, .evening:
                item.bucket = .anytime
                item.startDay = tx.today
                item.isEvening = resolved == .evening
                if original.startDay != tx.today || original.todaySortKey == nil || original.isEvening != item.isEvening {
                    item.todaySortKey = todayKeys[index]
                }
            case .day(let day):
                item.bucket = .anytime
                item.startDay = day
                item.isEvening = false
            case .someday:
                item.bucket = .someday
                item.startDay = nil
                item.isEvening = false
                item.reminderTime = nil
            case .clear:
                if item.bucket == .someday { item.bucket = .anytime }
                item.startDay = nil
                item.isEvening = false
                item.reminderTime = nil
            }
            if item.bucket != .inbox, original.bucket == .inbox {
                item.sortKey = try tx.newKeys(1, in: .noParent(item.bucket))[0]
            }
            try tx.save(item)
        }
    }

    @discardableResult
    public func setDeadline(_ ids: [String], _ day: Day?) async throws -> Committed<Void> {
        try await perform("Deadline") { tx in
            for var item in try tx.items(ids) {
                guard item.kind != .heading else { throw ModelError.ruleViolation("headings can't have deadlines") }
                item.deadlineDay = day
                try tx.save(item)
            }
        }
    }

    /// Sets a reminder time (minutes after midnight). Unscheduled items are scheduled for today.
    @discardableResult
    public func setReminder(_ id: String, minutes: Int?) async throws -> Committed<Void> {
        try await perform("Reminder") { tx in
            var item = try tx.item(id)
            if minutes != nil, item.startDay == nil {
                item.bucket = .anytime
                item.startDay = tx.today
                item.todaySortKey = try tx.newKeys(1, column: .todaySortKey, in: .today)[0]
            }
            item.reminderTime = minutes
            try tx.save(item)
        }
    }

    // MARK: Status

    /// Completes or cancels items. A project with open to-dos needs `openItems`.
    @discardableResult
    public func setStatus(_ ids: [String], _ status: ItemStatus, openItems: OpenItemsDecision? = nil) async throws -> Committed<Void> {
        try await perform(status == .open ? "Mark as Incomplete" : status == .completed ? "Complete" : "Cancel") { tx in
            for var item in try tx.items(ids) {
                if status != .open {
                    switch item.kind {
                    case .project:
                        let children = try tx.openTodos(under: item.id)
                        if !children.isEmpty {
                            guard let openItems else { throw ModelError.projectHasOpenItems(count: children.count) }
                            for var child in children {
                                child.status = openItems == .complete ? .completed : .canceled
                                child.stopDate = tx.now
                                try tx.save(child)
                            }
                        }
                        for var heading in try tx.liveItems(where: "kind = 2 AND status = 0 AND projectID = ?", [item.id]) {
                            heading.status = .completed
                            heading.stopDate = tx.now
                            try tx.save(heading)
                        }
                    case .heading:
                        let open = try tx.openTodos(under: item.id)
                        if !open.isEmpty { throw ModelError.headingHasOpenItems(count: open.count) }
                    case .todo:
                        break
                    }
                }
                item.status = status
                item.stopDate = status == .open ? nil : tx.now
                try tx.save(item)
            }
        }
    }

    // MARK: Trash

    /// Moves items (and a project's or heading's children) to the Trash.
    @discardableResult
    public func trash(_ ids: [String]) async throws -> Committed<Void> {
        try await perform("Delete") { tx in
            for item in try tx.items(ids) where item.trashedAt == nil {
                try Store.trash(item, in: tx)
            }
        }
    }

    static func trash(_ item: Item, in tx: Transaction) throws {
        var item = item
        item.trashedAt = tx.now
        try tx.save(item)
        if item.kind != .todo {
            for var child in try tx.liveItems(where: "trashedAt IS NULL AND (projectID = ? OR headingID = ?)", [item.id, item.id]) {
                child.trashedAt = tx.now
                try tx.save(child)
            }
        }
    }

    /// Restores items from the Trash, with the children trashed alongside them.
    @discardableResult
    public func putBack(_ ids: [String]) async throws -> Committed<Void> {
        try await perform("Put Back") { tx in
            for item in try tx.items(ids) {
                guard let trashedAt = item.trashedAt else { continue }
                var group = [item]
                if item.kind != .todo {
                    group += try tx.liveItems(where: "trashedAt = ? AND (projectID = ? OR headingID = ?)", [trashedAt.timeIntervalSince1970, item.id, item.id])
                }
                // Restore parents before children so the rules see live parents.
                for var member in group.sorted(by: { $0.kind.rawValue > $1.kind.rawValue }) {
                    member.trashedAt = nil
                    try Store.detachFromMissingParents(&member, in: tx)
                    try tx.save(member)
                }
            }
        }
    }

    /// Clears links to parents that were deleted or are still in the Trash.
    static func detachFromMissingParents(_ item: inout Item, in tx: Transaction) throws {
        func isGone(_ id: String?) throws -> Bool {
            guard let id else { return false }
            guard let parent = try Item.fetchOne(tx.db, key: id) else { return true }
            return parent.deletedAt != nil || parent.trashedAt != nil
        }
        if try isGone(item.headingID) {
            item.headingID = nil
        }
        if try isGone(item.projectID) {
            if item.kind == .heading {
                throw ModelError.invalidMove("heading's project is gone")
            }
            item.projectID = nil
            item.headingID = nil
            item.bucket = item.startDay == nil ? .inbox : .anytime
            item.sortKey = try tx.newKeys(1, in: Container.of(item))[0]
        }
        if let areaID = item.areaID {
            let area = try Area.fetchOne(tx.db, key: areaID)
            if area == nil || area?.deletedAt != nil {
                item.areaID = nil
            }
        }
        if item.bucket == .inbox, item.projectID == nil, item.areaID == nil, item.kind == .project {
            item.bucket = .anytime
        }
    }

    /// Permanently removes everything in the Trash (tombstones it, for sync).
    @discardableResult
    public func emptyTrash() async throws -> Committed<Void> {
        try await perform("Empty Trash") { tx in
            let trashed = try tx.liveItems(where: "trashedAt IS NOT NULL")
            for item in trashed {
                for checklistItem in try ChecklistItem.filter(Column("itemID") == item.id && Column("deletedAt") == nil).fetchAll(tx.db) {
                    try tx.delete(checklistItem)
                }
                for link in try ItemTag.filter(Column("itemID") == item.id && Column("deletedAt") == nil).fetchAll(tx.db) {
                    try tx.delete(link)
                }
                try tx.delete(item)
            }
        }
    }

    // MARK: Duplicate

    /// Duplicates to-dos and projects (with their contents) right after the originals.
    @discardableResult
    public func duplicate(_ ids: [String]) async throws -> Committed<[String]> {
        try await perform("Duplicate") { tx in
            var newIDs: [String] = []
            for original in try tx.items(ids) {
                guard original.kind != .heading else { throw ModelError.ruleViolation("headings can't be duplicated") }
                guard original.repeatRule == nil else { throw ModelError.ruleViolation("repeating items can't be duplicated") }
                var copy = original
                copy.id = tx.newID()
                copy.createdAt = tx.now
                copy.sortKey = try tx.newKeys(1, in: Container.of(original), after: original.id)[0]
                if original.todaySortKey != nil {
                    copy.todaySortKey = try tx.newKeys(1, column: .todaySortKey, in: .today, after: original.id)[0]
                }
                try tx.save(copy)
                try Store.copyDetails(from: original.id, to: copy.id, in: tx)
                if original.kind == .project {
                    var headingMap: [String: String] = [:]
                    let children = try tx.liveItems(where: "projectID = ? AND trashedAt IS NULL", [original.id])
                    for child in children.sorted(by: { $0.kind.rawValue > $1.kind.rawValue }) {
                        var childCopy = child
                        childCopy.id = tx.newID()
                        childCopy.createdAt = tx.now
                        childCopy.projectID = copy.id
                        childCopy.headingID = child.headingID.flatMap { headingMap[$0] }
                        if child.kind == .heading { headingMap[child.id] = childCopy.id }
                        try tx.save(childCopy)
                        try Store.copyDetails(from: child.id, to: childCopy.id, in: tx)
                    }
                }
                newIDs.append(copy.id)
            }
            return newIDs
        }
    }

    /// Copies checklist items and tags.
    static func copyDetails(from sourceID: String, to targetID: String, in tx: Transaction) throws {
        for source in try ChecklistItem.filter(Column("itemID") == sourceID && Column("deletedAt") == nil).fetchAll(tx.db) {
            var copy = source
            copy.id = tx.newID()
            copy.itemID = targetID
            copy.createdAt = tx.now
            try tx.save(copy)
        }
        for link in try ItemTag.filter(Column("itemID") == sourceID && Column("deletedAt") == nil).fetchAll(tx.db) {
            try tx.save(ItemTag(itemID: targetID, tagID: link.tagID, createdAt: tx.now))
        }
    }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Commands/AreaTagChecklistCommands.swift`:

```swift
import Foundation
import GRDB

extension Store {
    // MARK: Areas

    @discardableResult
    public func createArea(title: String) async throws -> Committed<String> {
        try await perform("New Area") { tx in
            let last = try String.fetchOne(tx.db, sql: "SELECT MAX(sortKey) FROM area WHERE deletedAt IS NULL")
            let area = Area(id: tx.newID(), title: title, createdAt: tx.now, sortKey: SortKey.between(last, nil))
            try tx.save(area)
            return area.id
        }
    }

    @discardableResult
    public func updateArea(_ id: String, _ change: @escaping @Sendable (inout Area) -> Void) async throws -> Committed<Void> {
        try await perform("Edit Area") { tx in
            guard var area = try Area.fetchOne(tx.db, key: id), area.deletedAt == nil else { throw ModelError.notFound("area \(id)") }
            change(&area)
            try tx.save(area)
        }
    }

    /// Places an area between two neighbouring areas in the sidebar.
    @discardableResult
    public func reorderArea(_ id: String, after afterID: String?, before beforeID: String?) async throws -> Committed<Void> {
        try await perform("Move") { tx in
            func key(_ id: String?) throws -> String? {
                guard let id else { return nil }
                return try String.fetchOne(tx.db, sql: "SELECT sortKey FROM area WHERE id = ?", arguments: [id])
            }
            let lower = try key(afterID), upper = try key(beforeID)
            if let lower, let upper, lower >= upper { throw ModelError.invalidMove("neighbours out of order") }
            guard var area = try Area.fetchOne(tx.db, key: id) else { throw ModelError.notFound("area \(id)") }
            area.sortKey = SortKey.between(lower, upper)
            try tx.save(area)
        }
    }

    /// Deletes an area. Its projects and to-dos go to the Trash.
    @discardableResult
    public func deleteArea(_ id: String) async throws -> Committed<Void> {
        try await perform("Delete Area") { tx in
            guard let area = try Area.fetchOne(tx.db, key: id), area.deletedAt == nil else { throw ModelError.notFound("area \(id)") }
            for item in try tx.liveItems(where: "areaID = ? AND trashedAt IS NULL", [id]) {
                try Store.trash(item, in: tx)
            }
            for link in try AreaTag.filter(Column("areaID") == id && Column("deletedAt") == nil).fetchAll(tx.db) {
                try tx.delete(link)
            }
            try tx.delete(area)
        }
    }

    @discardableResult
    public func setAreaTags(_ areaID: String, _ tagIDs: Set<String>) async throws -> Committed<Void> {
        try await perform("Tags") { tx in
            let existing = try AreaTag.filter(Column("areaID") == areaID).fetchAll(tx.db)
            for link in existing where link.deletedAt == nil && !tagIDs.contains(link.tagID) {
                try tx.delete(link)
            }
            for tagID in tagIDs {
                var link = existing.first { $0.tagID == tagID } ?? AreaTag(areaID: areaID, tagID: tagID, createdAt: tx.now)
                link.deletedAt = nil
                try tx.save(link)
            }
        }
    }

    // MARK: Tags

    @discardableResult
    public func createTag(title: String, parentID: String? = nil) async throws -> Committed<String> {
        try await perform("New Tag") { tx in
            let last = try String.fetchOne(tx.db, sql: "SELECT MAX(sortKey) FROM tag WHERE deletedAt IS NULL AND parentID IS ?", arguments: [parentID])
            var tag = Tag(id: tx.newID(), title: title, createdAt: tx.now, sortKey: SortKey.between(last, nil))
            tag.parentID = parentID
            try tx.save(tag)
            return tag.id
        }
    }

    @discardableResult
    public func renameTag(_ id: String, to title: String) async throws -> Committed<Void> {
        try await perform("Rename Tag") { tx in
            var tag = try Store.tag(id, in: tx)
            tag.title = title
            try tx.save(tag)
        }
    }

    /// Sets the ⌃-shortcut key. Each key can belong to only one tag.
    @discardableResult
    public func setTagShortcut(_ id: String, _ shortcut: String?) async throws -> Committed<Void> {
        try await perform("Tag Shortcut") { tx in
            var tag = try Store.tag(id, in: tx)
            let normalized = shortcut.flatMap { $0.isEmpty ? nil : String($0.prefix(1)).lowercased() }
            if let normalized {
                let taken = try Tag.filter(Column("shortcut") == normalized && Column("deletedAt") == nil && Column("id") != id).fetchCount(tx.db)
                if taken > 0 { throw ModelError.duplicateShortcut(normalized) }
            }
            tag.shortcut = normalized
            try tx.save(tag)
        }
    }

    /// Nests a tag under another. Refuses to create a cycle.
    @discardableResult
    public func setTagParent(_ id: String, _ parentID: String?) async throws -> Committed<Void> {
        try await perform("Move Tag") { tx in
            var tag = try Store.tag(id, in: tx)
            var ancestor = parentID
            while let current = ancestor {
                if current == id { throw ModelError.ruleViolation("tag can't be nested inside itself") }
                ancestor = try Store.tag(current, in: tx).parentID
            }
            tag.parentID = parentID
            try tx.save(tag)
        }
    }

    /// Deletes a tag, its nested tags, and their links to items and areas.
    @discardableResult
    public func deleteTag(_ id: String) async throws -> Committed<Void> {
        try await perform("Delete Tag") { tx in
            var queue = [id]
            while let current = queue.popLast() {
                let tag = try Store.tag(current, in: tx)
                queue += try String.fetchAll(tx.db, sql: "SELECT id FROM tag WHERE parentID = ? AND deletedAt IS NULL", arguments: [current])
                for link in try ItemTag.filter(Column("tagID") == current && Column("deletedAt") == nil).fetchAll(tx.db) {
                    try tx.delete(link)
                }
                for link in try AreaTag.filter(Column("tagID") == current && Column("deletedAt") == nil).fetchAll(tx.db) {
                    try tx.delete(link)
                }
                try tx.delete(tag)
            }
        }
    }

    /// Replaces the tags on every item in `ids`.
    @discardableResult
    public func setTags(_ ids: [String], _ tagIDs: Set<String>) async throws -> Committed<Void> {
        try await perform("Tags") { tx in
            for itemID in ids {
                _ = try tx.item(itemID)
                let existing = try ItemTag.filter(Column("itemID") == itemID).fetchAll(tx.db)
                for link in existing where link.deletedAt == nil && !tagIDs.contains(link.tagID) {
                    try tx.delete(link)
                }
                for tagID in tagIDs {
                    var link = existing.first { $0.tagID == tagID } ?? ItemTag(itemID: itemID, tagID: tagID, createdAt: tx.now)
                    link.deletedAt = nil
                    try tx.save(link)
                }
            }
        }
    }

    /// ⌃ + shortcut: removes the tag if every item has it, otherwise adds it to all.
    @discardableResult
    public func toggleTag(_ ids: [String], _ tagID: String) async throws -> Committed<Void> {
        try await perform("Tags") { tx in
            let links = try ItemTag.filter(ids.contains(Column("itemID")) && Column("tagID") == tagID).fetchAll(tx.db)
            let tagged = Set(links.filter { $0.deletedAt == nil }.map(\.itemID))
            let removing = ids.allSatisfy(tagged.contains)
            for itemID in ids {
                var link = links.first { $0.itemID == itemID } ?? ItemTag(itemID: itemID, tagID: tagID, createdAt: tx.now)
                if removing {
                    try tx.delete(link)
                } else {
                    link.deletedAt = nil
                    try tx.save(link)
                }
            }
        }
    }

    static func tag(_ id: String, in tx: Transaction) throws -> Tag {
        guard let tag = try Tag.fetchOne(tx.db, key: id), tag.deletedAt == nil else { throw ModelError.notFound("tag \(id)") }
        return tag
    }

    // MARK: Checklist

    @discardableResult
    public func addChecklistItem(to itemID: String, title: String, after afterID: String? = nil) async throws -> Committed<String> {
        try await perform("Add Checklist Item") { tx in
            let siblings = try ChecklistItem
                .filter(Column("itemID") == itemID && Column("deletedAt") == nil)
                .order(Column("sortKey"))
                .fetchAll(tx.db)
            let lower: String?
            let upper: String?
            if let afterID, let index = siblings.firstIndex(where: { $0.id == afterID }) {
                lower = siblings[index].sortKey
                upper = index + 1 < siblings.count ? siblings[index + 1].sortKey : nil
            } else {
                lower = siblings.last?.sortKey
                upper = nil
            }
            let entry = ChecklistItem(id: tx.newID(), itemID: itemID, title: title, createdAt: tx.now, sortKey: SortKey.between(lower, upper))
            try tx.save(entry)
            return entry.id
        }
    }

    @discardableResult
    public func updateChecklistItem(_ id: String, _ change: @escaping @Sendable (inout ChecklistItem) -> Void) async throws -> Committed<Void> {
        try await perform("Edit Checklist") { tx in
            guard var entry = try ChecklistItem.fetchOne(tx.db, key: id), entry.deletedAt == nil else {
                throw ModelError.notFound("checklist item \(id)")
            }
            change(&entry)
            try tx.save(entry)
        }
    }

    /// Places a checklist item between two neighbours.
    @discardableResult
    public func reorderChecklistItem(_ id: String, after afterID: String?, before beforeID: String?) async throws -> Committed<Void> {
        try await perform("Move") { tx in
            func key(_ id: String?) throws -> String? {
                guard let id else { return nil }
                return try String.fetchOne(tx.db, sql: "SELECT sortKey FROM checklist_item WHERE id = ?", arguments: [id])
            }
            let lower = try key(afterID), upper = try key(beforeID)
            if let lower, let upper, lower >= upper { throw ModelError.invalidMove("neighbours out of order") }
            guard var entry = try ChecklistItem.fetchOne(tx.db, key: id) else { throw ModelError.notFound("checklist item \(id)") }
            entry.sortKey = SortKey.between(lower, upper)
            try tx.save(entry)
        }
    }

    @discardableResult
    public func deleteChecklistItem(_ id: String) async throws -> Committed<Void> {
        try await perform("Delete Checklist Item") { tx in
            guard let entry = try ChecklistItem.fetchOne(tx.db, key: id), entry.deletedAt == nil else {
                throw ModelError.notFound("checklist item \(id)")
            }
            try tx.delete(entry)
        }
    }

    // MARK: Settings

    /// The settings row, or defaults if none has been saved yet.
    public static func settings(in db: Database, now: Date) throws -> Settings {
        try Settings.fetchOne(db, key: Settings.singletonID) ?? Settings(createdAt: now)
    }

    /// Changes settings other than the log policy (use `setLogPolicy` for that).
    @discardableResult
    public func updateSettings(_ change: @escaping @Sendable (inout Settings) -> Void) async throws -> Committed<Void> {
        try await perform("Settings") { tx in
            var settings = try Store.settings(in: tx.db, now: tx.now)
            let policy = settings.logPolicy
            change(&settings)
            if settings.logPolicy != policy {
                throw ModelError.ruleViolation("use setLogPolicy to change the log policy")
            }
            try tx.save(settings)
        }
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd Packages/StillpointModel && swift test`
Expected: `✔ Test run with 51 tests … passed`, with no compiler warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/StillpointModel/Sources/StillpointModel/Commands/Destination.swift Packages/StillpointModel/Sources/StillpointModel/Commands/TransactionHelpers.swift Packages/StillpointModel/Sources/StillpointModel/Commands/ItemCommands.swift Packages/StillpointModel/Sources/StillpointModel/Commands/AreaTagChecklistCommands.swift Packages/StillpointModel/Tests/StillpointModelTests/ItemCommandTests.swift Packages/StillpointModel/Tests/StillpointModelTests/AreaTagChecklistTests.swift
git commit -m "feat(model): item, area, tag, checklist and settings commands"
```

### Task 7: Move, reorder, convert and Logbook commands

The Move popover and sidebar drops, drag-reordering (including Today's separate order), Convert to Project (for to-dos and headings), Log Completed, and `setLogPolicy`. When the policy changes, items already logged under the old policy stay logged.
**Files:**
- Create: `Packages/StillpointModel/Sources/StillpointModel/Commands/StructureCommands.swift`
- Test: `Packages/StillpointModel/Tests/StillpointModelTests/StructureCommandTests.swift`

**Interfaces:**
- Consumes: Task 6 helpers and commands
- Produces:
- `Store`: `move(_ ids:, to: Destination, after: String?, before: String?)` (rejects today/evening/someday: use `schedule`), `reorder(_:after:before:column:)`, `convertToProject(_ todoID:)`, `convertHeadingToProject(_:) -> Committed<String>`, `logCompleted()`, `setLogPolicy(_:)`

- [ ] **Step 1: Write the failing tests**

`Packages/StillpointModel/Tests/StillpointModelTests/StructureCommandTests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import StillpointModel

struct StructureCommandTests {
    @Test func moveTodoBetweenContainers() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Home").value
        let project = try await h.store.createProject(title: "P", areaID: area).value
        let heading = try await h.store.createHeading(title: "H", projectID: project).value
        let id = try await h.store.createTodo(title: "x", in: .inbox).value

        try await h.store.move([id], to: .heading(heading))
        var item = try await h.item(id)
        #expect(item.projectID == project && item.headingID == heading && item.areaID == nil && item.bucket == .anytime)

        try await h.store.move([id], to: .area(area))
        item = try await h.item(id)
        #expect(item.projectID == nil && item.headingID == nil && item.areaID == area)

        try await h.store.schedule([id], .today)
        try await h.store.move([id], to: .inbox)
        item = try await h.item(id)
        #expect(item.bucket == .inbox && item.areaID == nil && item.startDay == nil)
    }

    @Test func movingHeadingTakesItsTodos() async throws {
        let h = try TestHarness()
        let p1 = try await h.store.createProject(title: "P1").value
        let p2 = try await h.store.createProject(title: "P2").value
        let heading = try await h.store.createHeading(title: "H", projectID: p1).value
        let todo = try await h.store.createTodo(in: .heading(heading)).value
        try await h.store.move([heading], to: .project(p2))
        #expect(try await h.item(heading).projectID == p2)
        #expect(try await h.item(todo).projectID == p2)
        #expect(try await h.item(todo).headingID == heading)
    }

    @Test func invalidMovesAreRejected() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let other = try await h.store.createProject(title: "Q").value
        await #expect(throws: ModelError.self) { try await h.store.move([project], to: .project(other)) }
        await #expect(throws: ModelError.self) { try await h.store.move([project], to: .inbox) }
        let todo = try await h.store.createTodo(in: .inbox).value
        await #expect(throws: ModelError.self) { try await h.store.move([todo], to: .today) }
    }

    @Test func moveWithNeighboursPlacesBetweenThem() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let a = try await h.store.createTodo(title: "a", in: .project(project)).value
        let b = try await h.store.createTodo(title: "b", in: .project(project)).value
        let x = try await h.store.createTodo(title: "x", in: .inbox).value
        try await h.store.move([x], to: .project(project), after: a, before: b)
        #expect(try await h.titles(where: "projectID = ?", [project]) == ["a", "x", "b"])
    }

    @Test func reorderBetweenNeighboursAndRejectsOutOfOrder() async throws {
        let h = try TestHarness()
        let a = try await h.store.createTodo(title: "a", in: .inbox).value
        let b = try await h.store.createTodo(title: "b", in: .inbox).value
        let c = try await h.store.createTodo(title: "c", in: .inbox).value
        try await h.store.reorder([c], after: nil, before: a)
        #expect(try await h.titles(where: "bucket = 0") == ["c", "a", "b"])
        await #expect(throws: ModelError.invalidMove("neighbours out of order")) {
            try await h.store.reorder([a], after: b, before: c)
        }
    }

    @Test func reorderToday() async throws {
        let h = try TestHarness()
        let a = try await h.store.createTodo(title: "a", in: .today).value
        let b = try await h.store.createTodo(title: "b", in: .today).value
        try await h.store.reorder([b], after: nil, before: a, column: .todaySortKey)
        #expect(try await h.titles(where: "todaySortKey IS NOT NULL", order: "todaySortKey") == ["b", "a"])
    }

    @Test func convertTodoToProjectTurnsChecklistIntoTodos() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Home").value
        let parent = try await h.store.createProject(title: "Parent", areaID: area).value
        let id = try await h.store.createTodo(title: "Big", in: .project(parent)).value
        _ = try await h.store.addChecklistItem(to: id, title: "one")
        let two = try await h.store.addChecklistItem(to: id, title: "two").value
        try await h.store.updateChecklistItem(two) { $0.isDone = true }

        try await h.store.convertToProject(id)
        let project = try await h.item(id)
        #expect(project.kind == .project && project.projectID == nil && project.areaID == area)
        let todos = try await h.store.read { db in
            try Item.filter(Column("projectID") == id).order(Column("sortKey")).fetchAll(db)
        }
        #expect(todos.map(\.title) == ["one", "two"])
        #expect(todos.map(\.status) == [.open, .completed])
        let liveChecklist = try await h.store.read { db in try ChecklistItem.filter(Column("deletedAt") == nil).fetchCount(db) }
        #expect(liveChecklist == 0)
    }

    @Test func convertHeadingToProject() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Work").value
        let parent = try await h.store.createProject(title: "Parent", areaID: area).value
        let heading = try await h.store.createHeading(title: "Phase 2", projectID: parent).value
        let todo = try await h.store.createTodo(title: "x", in: .heading(heading)).value
        let newProject = try await h.store.convertHeadingToProject(heading).value
        #expect(try await h.item(newProject).title == "Phase 2")
        #expect(try await h.item(newProject).areaID == area)
        #expect(try await h.item(todo).projectID == newProject)
        #expect(try await h.item(todo).headingID == nil)
        #expect(try await h.item(heading).deletedAt != nil)
    }

    @Test func logPolicyCanOnlyChangeThroughSetLogPolicy() async throws {
        let h = try TestHarness()
        await #expect(throws: ModelError.self) {
            try await h.store.updateSettings { $0.logPolicy = .manually }
        }
        try await h.store.updateSettings { $0.groupTodayByProject = true }
        try await h.store.setLogPolicy(.manually)
        let settings = try await h.store.read { db in try Store.settings(in: db, now: Date()) }
        #expect(settings.logPolicy == .manually && settings.groupTodayByProject)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd Packages/StillpointModel && swift test`
Expected: the build fails with `error: value of type 'Store' has no member 'move'`.

- [ ] **Step 3: Implement**

`Packages/StillpointModel/Sources/StillpointModel/Commands/StructureCommands.swift`:

```swift
import Foundation
import GRDB

extension Store {
    // MARK: Move

    /// Moves items to another container (the Move popover, or a drop on the sidebar).
    /// Today / This Evening / Someday are scheduling, so use `schedule` for those.
    /// With `after`/`before` (neighbour IDs in the target list) the items are placed between them.
    @discardableResult
    public func move(_ ids: [String], to destination: Destination, after afterID: String? = nil, before beforeID: String? = nil) async throws -> Committed<Void> {
        try await perform("Move") { tx in
            let items = try tx.items(ids)
            var moved: [Item] = []
            for original in items {
                var item = original
                switch (item.kind, destination) {
                case (.todo, .inbox):
                    item.projectID = nil; item.headingID = nil; item.areaID = nil
                    item.bucket = .inbox; item.startDay = nil; item.isEvening = false; item.reminderTime = nil
                case (.todo, .anytime):
                    item.projectID = nil; item.headingID = nil; item.areaID = nil
                    if item.bucket == .inbox { item.bucket = .anytime }
                case (.todo, .area(let areaID)):
                    item.projectID = nil; item.headingID = nil; item.areaID = areaID
                    if item.bucket == .inbox { item.bucket = .anytime }
                case (.todo, .project(let projectID)):
                    item.projectID = projectID; item.headingID = nil; item.areaID = nil
                    if item.bucket == .inbox { item.bucket = .anytime }
                case (.todo, .heading(let headingID)):
                    let heading = try tx.item(headingID)
                    item.projectID = heading.projectID; item.headingID = headingID; item.areaID = nil
                    if item.bucket == .inbox { item.bucket = .anytime }
                case (.project, .area(let areaID)):
                    item.areaID = areaID
                case (.project, .anytime):
                    item.areaID = nil
                case (.heading, .project(let projectID)):
                    item.projectID = projectID
                default:
                    throw ModelError.invalidMove("can't move a \(item.kind) to \(destination)")
                }
                moved.append(item)
            }

            let keys: [String]
            if afterID != nil || beforeID != nil {
                keys = try tx.keysBetween(moved.count, column: .sortKey, after: afterID, before: beforeID)
            } else if let first = moved.first {
                keys = try tx.newKeys(moved.count, in: Container.of(first))
            } else {
                keys = []
            }
            // Headings move first so their to-dos can follow them into the new project.
            for (index, var item) in moved.enumerated() {
                item.sortKey = keys[index]
                try tx.save(item)
                if item.kind == .heading {
                    for var child in try tx.liveItems(where: "headingID = ?", [item.id]) {
                        child.projectID = item.projectID
                        try tx.save(child)
                    }
                }
            }
        }
    }

    /// Reorders items within the list they're displayed in, between two neighbours.
    @discardableResult
    public func reorder(_ ids: [String], after afterID: String?, before beforeID: String?, column: OrderColumn = .sortKey) async throws -> Committed<Void> {
        try await perform("Move") { tx in
            let keys = try tx.keysBetween(ids.count, column: column, after: afterID, before: beforeID)
            for (index, var item) in try tx.items(ids).enumerated() {
                switch column {
                case .sortKey: item.sortKey = keys[index]
                case .todaySortKey: item.todaySortKey = keys[index]
                }
                try tx.save(item)
            }
        }
    }

    // MARK: Convert

    /// Turns a to-do into a project. Its checklist becomes to-dos in the new project.
    @discardableResult
    public func convertToProject(_ todoID: String) async throws -> Committed<Void> {
        try await perform("Convert to Project") { tx in
            var item = try tx.item(todoID)
            guard item.kind == .todo else { throw ModelError.invalidMove("only to-dos can be converted") }
            if let projectID = item.projectID {
                item.areaID = try tx.item(projectID).areaID
            }
            item.kind = .project
            item.projectID = nil
            item.headingID = nil
            if item.bucket == .inbox { item.bucket = .anytime }
            item.sortKey = try tx.newKeys(1, in: .projects(inArea: item.areaID))[0]
            try tx.save(item)

            let checklist = try ChecklistItem
                .filter(Column("itemID") == todoID && Column("deletedAt") == nil)
                .order(Column("sortKey"))
                .fetchAll(tx.db)
            let keys = try tx.newKeys(checklist.count, in: .project(todoID))
            for (index, entry) in checklist.enumerated() {
                var todo = Item(id: tx.newID(), kind: .todo, title: entry.title, createdAt: tx.now, bucket: .anytime, sortKey: keys[index])
                todo.projectID = todoID
                if entry.isDone {
                    todo.status = .completed
                    todo.stopDate = tx.now
                }
                try tx.save(todo)
                try tx.delete(entry)
            }
        }
    }

    /// Turns a heading into its own project (in the same area); its to-dos move with it.
    @discardableResult
    public func convertHeadingToProject(_ headingID: String) async throws -> Committed<String> {
        try await perform("Convert to Project") { tx in
            let heading = try tx.item(headingID)
            guard heading.kind == .heading, let parentID = heading.projectID else {
                throw ModelError.invalidMove("not a heading")
            }
            let parent = try tx.item(parentID)
            var project = Item(id: tx.newID(), kind: .project, title: heading.title, createdAt: tx.now, bucket: .anytime, sortKey: "")
            project.areaID = parent.areaID
            project.sortKey = try tx.newKeys(1, in: .projects(inArea: parent.areaID), after: parentID)[0]
            try tx.save(project)
            for var todo in try tx.liveItems(where: "headingID = ?", [headingID]) {
                todo.projectID = project.id
                todo.headingID = nil
                try tx.save(todo)
            }
            try tx.delete(heading)
            return project.id
        }
    }

    // MARK: Logbook

    /// "Log Completed": logs every completed or canceled item now.
    @discardableResult
    public func logCompleted() async throws -> Committed<Void> {
        try await perform("Log Completed") { tx in
            var settings = try Store.settings(in: tx.db, now: tx.now)
            settings.manualLogCutoff = tx.now
            try tx.save(settings)
        }
    }

    /// Changes when completed items are logged. Items already logged under the
    /// old policy stay logged: the cutoff advances to cover them first.
    @discardableResult
    public func setLogPolicy(_ policy: LogPolicy) async throws -> Committed<Void> {
        try await perform("Settings") { tx in
            var settings = try Store.settings(in: tx.db, now: tx.now)
            let alreadyLogged: Date? = switch settings.logPolicy {
            case .immediately: tx.now
            case .daily: tx.today.startOfDay(in: tx.env.calendar)
            case .manually: nil
            }
            if let alreadyLogged, alreadyLogged > (settings.manualLogCutoff ?? .distantPast) {
                settings.manualLogCutoff = alreadyLogged
            }
            settings.logPolicy = policy
            try tx.save(settings)
        }
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd Packages/StillpointModel && swift test`
Expected: `✔ Test run with 60 tests … passed`, with no compiler warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/StillpointModel/Sources/StillpointModel/Commands/StructureCommands.swift Packages/StillpointModel/Tests/StillpointModelTests/StructureCommandTests.swift
git commit -m "feat(model): move, reorder, convert and logbook commands"
```

### Task 8: List queries and live observation

The exact rule behind every list (spec §4.2): Inbox, Today (+ This Evening, optional grouping), Upcoming (7 days, rest of month, months), Anytime, Someday, Deadlines, Logbook, Trash, All/Later Projects, project and area views with "later" and "logged" items, tag filtering (nested tags, inherited through projects and areas), and `observe` for live updates.
**Files:**
- Create: `Packages/StillpointModel/Sources/StillpointModel/Queries/ListContent.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Queries/ListQueries.swift`
- Test: `Packages/StillpointModel/Tests/StillpointModelTests/ListQueryTests.swift`

**Interfaces:**
- Consumes: Tasks 4–7
- Produces:
- `enum ListID` (`inbox`, `today`, `upcoming`, `anytime`, `someday`, `deadlines`, `logbook`, `trash`, `allProjects`, `laterProjects`, `project(id)`, `area(id)`)
- `struct ListContent` (`sections: [ListSection]`, `later: [Item]`, `logged: [Item]`, `tagIDsByItem: [String: [String]]`, `allItems`); `struct ListSection` (`id`, `kind: SectionKind`, `title`, `items`); `enum SectionKind` (`plain`, `evening`, `day(Day)`, `restOfMonth(from:through:)`, `month(Day)`, `area(id)`, `project(id)`, `heading(id)`)
- `Store.fetch(_ list:, tagFilter: String?) async throws -> ListContent`, `Store.observe(_:tagFilter:) -> AsyncValueObservation<ListContent>`

> The model can't know when midnight passes. Plan 2's app layer must re-subscribe to `observe` at local midnight, and rebuild `ModelEnvironment` when the system time zone changes (`NSSystemTimeZoneDidChange`).

- [ ] **Step 1: Write the failing tests**

`Packages/StillpointModel/Tests/StillpointModelTests/ListQueryTests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import StillpointModel

struct ListQueryTests {
    func titles(_ content: ListContent) -> [String] {
        content.allItems.map(\.title)
    }

    @Test func inboxShowsOnlyInboxTodos() async throws {
        let h = try TestHarness()
        try await h.store.createTodo(title: "in", in: .inbox)
        try await h.store.createTodo(title: "out", in: .anytime)
        #expect(titles(try await h.store.fetch(.inbox)) == ["in"])
    }

    @Test func todayHasMainThenEveningAndOverdueStarts() async throws {
        let h = try TestHarness()
        try await h.store.createTodo(title: "a", in: .today)
        try await h.store.createTodo(title: "e", in: .evening)
        let old = try await h.store.createTodo(title: "old", in: .anytime).value
        try await h.store.schedule([old], .day(h.today.adding(days: 1, calendar: .fixture())))
        h.advance(days: 3) // "old" started two days ago and rolls into Today
        let content = try await h.store.fetch(.today)
        #expect(content.sections.map(\.kind) == [.plain, .evening])
        #expect(content.sections[0].items.map(\.title).sorted() == ["a", "old"])
        #expect(content.sections[1].items.map(\.title) == ["e"])
    }

    @Test func todayIncludesDueDeadlines() async throws {
        let h = try TestHarness()
        let id = try await h.store.createTodo(title: "due", in: .someday).value
        try await h.store.setDeadline([id], h.today)
        #expect(titles(try await h.store.fetch(.today)) == ["due"])
    }

    @Test func todayRollsOverAtLocalMidnight() async throws {
        // 23:30 in Kolkata on Oct 15 (18:00 UTC).
        let h = try TestHarness(now: Date(timeIntervalSince1970: 1_792_087_200), timeZone: "Asia/Kolkata")
        let id = try await h.store.createTodo(title: "tomorrow", in: .anytime).value
        try await h.store.schedule([id], .day(h.today.adding(days: 1, calendar: .fixture(timeZone: "Asia/Kolkata"))))
        #expect(titles(try await h.store.fetch(.today)).isEmpty)
        h.advance(seconds: 45 * 60) // 00:15 local
        #expect(titles(try await h.store.fetch(.today)) == ["tomorrow"])
    }

    @Test func todayCanGroupByProject() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let inProject = try await h.store.createTodo(title: "p1", in: .project(project)).value
        try await h.store.schedule([inProject], .today)
        try await h.store.createTodo(title: "loose", in: .today)
        try await h.store.updateSettings { $0.groupTodayByProject = true }
        let content = try await h.store.fetch(.today)
        #expect(content.sections.map(\.kind) == [.plain, .project(project)])
        #expect(content.sections[1].title == "P")
    }

    @Test func upcomingHasSevenDaysThenRestOfMonthThenMonths() async throws {
        let h = try TestHarness() // Thursday 2026-10-15
        let cal = Calendar.fixture()
        let a = try await h.store.createTodo(title: "in2days", in: .anytime).value
        try await h.store.schedule([a], .day(h.today.adding(days: 2, calendar: cal)))
        let b = try await h.store.createTodo(title: "oct28", in: .anytime).value
        try await h.store.schedule([b], .day(Day(year: 2026, month: 10, day: 28)))
        let c = try await h.store.createTodo(title: "dec", in: .anytime).value
        try await h.store.setDeadline([c], Day(year: 2026, month: 12, day: 3))

        let content = try await h.store.fetch(.upcoming)
        #expect(content.sections.count == 9)
        #expect(content.sections[1].kind == .day(Day(year: 2026, month: 10, day: 17)))
        #expect(content.sections[1].items.map(\.title) == ["in2days"])
        #expect(content.sections[7].kind == .restOfMonth(from: Day(year: 2026, month: 10, day: 23), through: Day(year: 2026, month: 10, day: 31)))
        #expect(content.sections[7].items.map(\.title) == ["oct28"])
        #expect(content.sections[8].kind == .month(Day(year: 2026, month: 12, day: 1)))
        #expect(content.sections[8].items.map(\.title) == ["dec"])
    }

    @Test func anytimeGroupsAndHidesSomedayAndFutureProjects() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Work").value
        let active = try await h.store.createProject(title: "Active", areaID: area).value
        let parked = try await h.store.createProject(title: "Parked", someday: true).value
        try await h.store.createTodo(title: "loose", in: .anytime)
        try await h.store.createTodo(title: "areaTodo", in: .area(area))
        try await h.store.createTodo(title: "activeTodo", in: .project(active))
        try await h.store.createTodo(title: "parkedTodo", in: .project(parked))
        let future = try await h.store.createTodo(title: "future", in: .anytime).value
        try await h.store.schedule([future], .day(h.today.adding(days: 2, calendar: .fixture())))

        let content = try await h.store.fetch(.anytime)
        #expect(content.sections.map(\.kind) == [.plain, .area(area), .project(active)])
        #expect(titles(content) == ["loose", "areaTodo", "activeTodo"])
    }

    @Test func somedayShowsSomedayProjectsNotTheirTodos() async throws {
        let h = try TestHarness()
        let parked = try await h.store.createProject(title: "Parked", someday: true).value
        try await h.store.createTodo(title: "inside", in: .project(parked))
        try await h.store.createTodo(title: "loose", in: .someday)
        #expect(Set(titles(try await h.store.fetch(.someday))) == ["Parked", "loose"])
    }

    @Test func deadlinesSortedByDay() async throws {
        let h = try TestHarness()
        let cal = Calendar.fixture()
        let late = try await h.store.createTodo(title: "late", in: .anytime).value
        let soon = try await h.store.createTodo(title: "soon", in: .anytime).value
        try await h.store.setDeadline([late], h.today.adding(days: 9, calendar: cal))
        try await h.store.setDeadline([soon], h.today.adding(days: 1, calendar: cal))
        #expect(titles(try await h.store.fetch(.deadlines)) == ["soon", "late"])
    }

    @Test func logPolicies() async throws {
        let h = try TestHarness()
        let id = try await h.store.createTodo(title: "done", in: .anytime).value
        try await h.store.setStatus([id], .completed)

        // Daily (default): stays in Anytime today, logged tomorrow.
        #expect(titles(try await h.store.fetch(.anytime)) == ["done"])
        #expect(titles(try await h.store.fetch(.logbook)).isEmpty)
        h.advance(days: 1)
        #expect(titles(try await h.store.fetch(.anytime)).isEmpty)
        #expect(titles(try await h.store.fetch(.logbook)) == ["done"])

        // Manually: stays until Log Completed.
        try await h.store.setLogPolicy(.manually)
        let manual = try await h.store.createTodo(title: "manual", in: .anytime).value
        try await h.store.setStatus([manual], .completed)
        h.advance(days: 5)
        #expect(titles(try await h.store.fetch(.anytime)) == ["manual"]) // "done" stays logged
        #expect(titles(try await h.store.fetch(.logbook)) == ["done"])
        try await h.store.logCompleted()
        #expect(titles(try await h.store.fetch(.anytime)).isEmpty)

        // Immediately.
        try await h.store.setLogPolicy(.immediately)
        let instant = try await h.store.createTodo(title: "instant", in: .anytime).value
        try await h.store.setStatus([instant], .completed)
        #expect(titles(try await h.store.fetch(.anytime)).isEmpty)
    }

    @Test func logbookNestsTodosUnderLoggedProject() async throws {
        let h = try TestHarness()
        try await h.store.setLogPolicy(.immediately)
        let project = try await h.store.createProject(title: "P").value
        try await h.store.createTodo(title: "child", in: .project(project))
        try await h.store.setStatus([project], .completed, openItems: .complete)
        #expect(titles(try await h.store.fetch(.logbook)) == ["P"])
    }

    @Test func trashShowsParentsNotTheirChildren() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        try await h.store.createTodo(title: "child", in: .project(project))
        let loose = try await h.store.createTodo(title: "loose", in: .inbox).value
        try await h.store.trash([project, loose])
        #expect(Set(titles(try await h.store.fetch(.trash))) == ["P", "loose"])
        #expect(titles(try await h.store.fetch(.inbox)).isEmpty)
    }

    @Test func projectHasHeadingsLaterAndLogged() async throws {
        let h = try TestHarness()
        try await h.store.setLogPolicy(.immediately)
        let project = try await h.store.createProject(title: "P").value
        try await h.store.createTodo(title: "loose", in: .project(project))
        let heading = try await h.store.createHeading(title: "H", projectID: project).value
        try await h.store.createTodo(title: "under", in: .heading(heading))
        let emptyHeading = try await h.store.createHeading(title: "Empty", projectID: project).value
        let later = try await h.store.createTodo(title: "later", in: .project(project)).value
        try await h.store.schedule([later], .someday)
        let done = try await h.store.createTodo(title: "done", in: .project(project)).value
        try await h.store.setStatus([done], .completed)

        let content = try await h.store.fetch(.project(project))
        #expect(content.sections.map(\.kind) == [.plain, .heading(heading), .heading(emptyHeading)])
        #expect(content.sections.map { $0.items.map(\.title) } == [["loose"], ["under"], []])
        #expect(content.later.map(\.title) == ["later"])
        #expect(content.logged.map(\.title) == ["done"])
    }

    @Test func areaListsTodosThenProjects() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Home").value
        try await h.store.createProject(title: "Garden", areaID: area)
        try await h.store.createTodo(title: "Call plumber", in: .area(area))
        let content = try await h.store.fetch(.area(area))
        #expect(content.sections.map { $0.items.map(\.title) } == [["Call plumber"], ["Garden"]])
    }

    @Test func allProjectsAndLaterProjects() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Work").value
        try await h.store.createProject(title: "Now", areaID: area)
        try await h.store.createProject(title: "Loose")
        try await h.store.createProject(title: "Parked", someday: true)
        let all = try await h.store.fetch(.allProjects)
        #expect(all.sections.map(\.kind) == [.plain, .area(area)])
        #expect(titles(all) == ["Loose", "Now"])
        #expect(titles(try await h.store.fetch(.laterProjects)) == ["Parked"])
    }

    @Test func tagFilterIncludesNestedTagsAndInheritsFromProjectAndArea() async throws {
        let h = try TestHarness()
        let errands = try await h.store.createTag(title: "Errands").value
        let shops = try await h.store.createTag(title: "Shops", parentID: errands).value
        let area = try await h.store.createArea(title: "Home").value
        try await h.store.setAreaTags(area, [errands])
        let direct = try await h.store.createTodo(title: "direct", in: .anytime).value
        try await h.store.setTags([direct], [shops])
        try await h.store.createTodo(title: "viaArea", in: .area(area))
        try await h.store.createTodo(title: "untagged", in: .anytime)

        let content = try await h.store.fetch(.anytime, tagFilter: errands)
        #expect(Set(titles(content)) == ["direct", "viaArea"])
        #expect(content.tagIDsByItem[direct] == [shops])
    }

    @Test func observationEmitsOnChange() async throws {
        let h = try TestHarness()
        var iterator = h.store.observe(.inbox).makeAsyncIterator()
        #expect(try await iterator.next()?.allItems.isEmpty == true)
        try await h.store.createTodo(title: "new", in: .inbox)
        #expect(try await iterator.next()?.allItems.map(\.title) == ["new"])
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd Packages/StillpointModel && swift test`
Expected: the build fails with `error: cannot find 'ListID' in scope`.

- [ ] **Step 3: Implement**

`Packages/StillpointModel/Sources/StillpointModel/Queries/ListContent.swift`:

```swift
/// A list shown in the main pane.
public enum ListID: Hashable, Sendable {
    case inbox, today, upcoming, anytime, someday, deadlines, logbook, trash
    case allProjects, laterProjects
    case project(String)
    case area(String)
}

public enum SectionKind: Sendable, Equatable {
    case plain
    case evening
    case day(Day)
    case restOfMonth(from: Day, through: Day)
    /// Any day in the month; the section covers the whole month.
    case month(Day)
    case area(String)
    case project(String)
    case heading(String)
}

public struct ListSection: Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: SectionKind
    public var title: String?
    public var items: [Item]
}

public struct ListContent: Sendable, Equatable {
    public var sections: [ListSection]
    /// Projects and areas: items scheduled for later or Someday ("Show N later items").
    public var later: [Item]
    /// Projects and areas: logged items ("Show N logged items").
    public var logged: [Item]
    /// Live tag IDs for every item in this content.
    public var tagIDsByItem: [String: [String]]

    public var allItems: [Item] { sections.flatMap(\.items) }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Queries/ListQueries.swift`:

```swift
import Foundation
import GRDB

/// Builds `ListContent` for each list (spec §4.2).
struct ListQueries {
    let db: Database
    let env: ModelEnvironment
    let today: Day
    let settings: Settings
    /// Not tombstoned, not trashed, not logged. Bind `visibleArguments` after it.
    let visible: String
    let visibleArguments: StatementArguments
    let logged: String
    let loggedArguments: StatementArguments

    init(db: Database, env: ModelEnvironment) throws {
        self.db = db
        self.env = env
        let now = env.now()
        today = Day(now, calendar: env.calendar)
        settings = try Store.settings(in: db, now: now)

        let cutoff = settings.manualLogCutoff?.timeIntervalSince1970 ?? -Double.greatestFiniteMagnitude
        let policy: String
        var policyArguments: StatementArguments = []
        switch settings.logPolicy {
        case .immediately:
            policy = "1"
        case .daily:
            policy = "item.stopDate < ?"
            policyArguments = [today.startOfDay(in: env.calendar).timeIntervalSince1970]
        case .manually:
            policy = "0"
        }
        logged = "(item.status != 0 AND item.stopDate IS NOT NULL AND (item.stopDate <= ? OR \(policy)))"
        loggedArguments = [cutoff] + policyArguments
        visible = "(item.deletedAt IS NULL AND item.trashedAt IS NULL AND NOT \(logged))"
        visibleArguments = loggedArguments
    }

    func fetch(_ list: ListID, tagFilter: String?) throws -> ListContent {
        var content: ListContent
        switch list {
        case .inbox: content = try inbox()
        case .today: content = try todayList()
        case .upcoming: content = try upcoming()
        case .anytime: content = try anytime()
        case .someday: content = try someday()
        case .deadlines: content = try deadlines()
        case .logbook: content = try logbook()
        case .trash: content = try trash()
        case .allProjects: content = try projects(later: false)
        case .laterProjects: content = try projects(later: true)
        case .project(let id): content = try project(id)
        case .area(let id): content = try area(id)
        }
        if let tagFilter {
            content = try filter(content, byTag: tagFilter)
        }
        content.tagIDsByItem = try tagIDs(for: content.allItems + content.later + content.logged)
        return content
    }

    // MARK: Lists

    private func inbox() throws -> ListContent {
        let items = try select("item.kind = 0 AND item.bucket = 0 AND \(visible)", visibleArguments)
        return single(id: "inbox", items)
    }

    private func todayList() throws -> ListContent {
        let items = try select(
            """
            item.kind IN (0, 1) AND \(visible) AND (
              (item.bucket = 1 AND item.startDay <= ?) OR item.deadlineDay <= ?)
            """,
            visibleArguments + [today, today],
            order: "item.todaySortKey IS NULL, item.todaySortKey, item.startDay, item.sortKey"
        )
        let main = items.filter { !$0.isEvening }
        let evening = items.filter(\.isEvening)
        var sections: [ListSection] = []
        if settings.groupTodayByProject {
            sections += try groupedByParent(main, idPrefix: "today")
        } else if !main.isEmpty {
            sections.append(ListSection(id: "today", kind: .plain, title: nil, items: main))
        }
        if !evening.isEmpty {
            sections.append(ListSection(id: "evening", kind: .evening, title: "This Evening", items: evening))
        }
        return ListContent(sections: sections, later: [], logged: [], tagIDsByItem: [:])
    }

    private func upcoming() throws -> ListContent {
        let items = try select(
            """
            item.kind IN (0, 1) AND \(visible) AND (
              (item.bucket = 1 AND item.startDay > ?) OR item.deadlineDay > ?)
            """,
            visibleArguments + [today, today]
        )
        // Each item appears once: on its start day if that's in the future, else its deadline.
        let dated = items.map { item -> (Day, Item) in
            if let start = item.startDay, start > today { return (start, item) }
            return (item.deadlineDay!, item)
        }.sorted { ($0.0, $0.1.sortKey) < ($1.0, $1.1.sortKey) }

        let calendar = env.calendar
        var sections: [ListSection] = []
        // The next seven days always appear, even when empty.
        for offset in 1...7 {
            let day = today.adding(days: offset, calendar: calendar)
            sections.append(ListSection(id: "day.\(day.rawValue)", kind: .day(day), title: nil, items: dated.filter { $0.0 == day }.map(\.1)))
        }
        let weekEnd = today.adding(days: 7, calendar: calendar)
        let monthEnd = Day(year: weekEnd.year, month: weekEnd.month,
                           day: calendar.range(of: .day, in: .month, for: weekEnd.date(in: calendar))!.count)
        if weekEnd < monthEnd {
            let from = weekEnd.adding(days: 1, calendar: calendar)
            let rest = dated.filter { $0.0 >= from && $0.0 <= monthEnd }.map(\.1)
            sections.append(ListSection(id: "rest.\(from.rawValue)", kind: .restOfMonth(from: from, through: monthEnd), title: nil, items: rest))
        }
        let later = dated.filter { $0.0 > monthEnd }
        var months: [Int: [Item]] = [:]
        var monthOrder: [Int] = []
        for (day, item) in later {
            let key = day.year * 100 + day.month
            if months[key] == nil { monthOrder.append(key) }
            months[key, default: []].append(item)
        }
        for key in monthOrder {
            let first = Day(year: key / 100, month: key % 100, day: 1)
            sections.append(ListSection(id: "month.\(key)", kind: .month(first), title: nil, items: months[key]!))
        }
        return ListContent(sections: sections, later: [], logged: [], tagIDsByItem: [:])
    }

    private func anytime() throws -> ListContent {
        let todos = try select(
            """
            item.kind = 0 AND \(visible) AND item.bucket = 1 AND (item.startDay IS NULL OR item.startDay <= ?)
              AND (item.projectID IS NULL OR EXISTS (
                SELECT 1 FROM item p WHERE p.id = item.projectID AND p.bucket = 1
                  AND (p.startDay IS NULL OR p.startDay <= ?)))
            """,
            visibleArguments + [today, today]
        )
        return ListContent(sections: try groupedByAreaAndProject(todos), later: [], logged: [], tagIDsByItem: [:])
    }

    private func someday() throws -> ListContent {
        let items = try select(
            """
            item.kind IN (0, 1) AND \(visible) AND item.bucket = 2 AND item.startDay IS NULL
              AND (item.projectID IS NULL OR NOT EXISTS (
                SELECT 1 FROM item p WHERE p.id = item.projectID AND p.bucket = 2))
            """,
            visibleArguments
        )
        return ListContent(sections: try groupedByAreaAndProject(items), later: [], logged: [], tagIDsByItem: [:])
    }

    private func deadlines() throws -> ListContent {
        let items = try select(
            "item.kind IN (0, 1) AND \(visible) AND item.status = 0 AND item.deadlineDay IS NOT NULL",
            visibleArguments,
            order: "item.deadlineDay, item.sortKey"
        )
        var sections: [ListSection] = []
        for item in items {
            let day = item.deadlineDay!
            if sections.last?.kind == .day(day) {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(ListSection(id: "deadline.\(day.rawValue)", kind: .day(day), title: nil, items: [item]))
            }
        }
        return ListContent(sections: sections, later: [], logged: [], tagIDsByItem: [:])
    }

    private func logbook() throws -> ListContent {
        let items = try select(
            "item.kind IN (0, 1) AND item.deletedAt IS NULL AND item.trashedAt IS NULL AND \(logged)",
            loggedArguments,
            order: "item.stopDate DESC"
        )
        let loggedProjects = Set(items.filter { $0.kind == .project }.map(\.id))
        var sections: [ListSection] = []
        for item in items where !(item.projectID.map(loggedProjects.contains) ?? false) {
            let day = Day(item.stopDate!, calendar: env.calendar)
            if sections.last?.kind == .day(day) {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(ListSection(id: "logged.\(day.rawValue)", kind: .day(day), title: nil, items: [item]))
            }
        }
        return ListContent(sections: sections, later: [], logged: [], tagIDsByItem: [:])
    }

    private func trash() throws -> ListContent {
        let items = try select(
            """
            item.deletedAt IS NULL AND item.trashedAt IS NOT NULL AND NOT EXISTS (
              SELECT 1 FROM item p WHERE p.id IN (item.projectID, item.headingID) AND p.trashedAt IS NOT NULL)
            """,
            [],
            order: "item.trashedAt DESC, item.sortKey"
        )
        return single(id: "trash", items)
    }

    private func projects(later: Bool) throws -> ListContent {
        let condition = later
            ? "(item.bucket = 2 OR item.startDay > ?)"
            : "item.bucket = 1 AND (item.startDay IS NULL OR item.startDay <= ?)"
        let projects = try select("item.kind = 1 AND \(visible) AND \(condition)", visibleArguments + [today])
        var sections: [ListSection] = []
        let loose = projects.filter { $0.areaID == nil }
        if !loose.isEmpty {
            sections.append(ListSection(id: "projects.none", kind: .plain, title: nil, items: loose))
        }
        for area in try liveAreas() {
            let inArea = projects.filter { $0.areaID == area.id }
            if !inArea.isEmpty {
                sections.append(ListSection(id: "projects.\(area.id)", kind: .area(area.id), title: area.title, items: inArea))
            }
        }
        return ListContent(sections: sections, later: [], logged: [], tagIDsByItem: [:])
    }

    private func project(_ projectID: String) throws -> ListContent {
        let children = try select(
            "item.projectID = ? AND item.deletedAt IS NULL AND item.trashedAt IS NULL",
            [projectID]
        )
        let isLogged = try loggedIDs(children.map(\.id))
        let headings = children.filter { $0.kind == .heading }
        let archivedHeadings = Set(headings.filter { $0.status != .open }.map(\.id))
        let todos = children.filter { $0.kind == .todo }

        var logged: [Item] = []
        var later: [Item] = []
        var current: [Item] = []
        for todo in todos {
            if isLogged.contains(todo.id) || (todo.headingID.map(archivedHeadings.contains) ?? false) {
                logged.append(todo)
            } else if isLater(todo) {
                later.append(todo)
            } else {
                current.append(todo)
            }
        }

        var sections: [ListSection] = []
        let loose = current.filter { $0.headingID == nil }
        if !loose.isEmpty {
            sections.append(ListSection(id: "project.\(projectID)", kind: .plain, title: nil, items: loose))
        }
        for heading in headings where heading.status == .open {
            sections.append(ListSection(id: "heading.\(heading.id)", kind: .heading(heading.id), title: heading.title,
                                        items: current.filter { $0.headingID == heading.id }))
        }
        logged.sort { ($0.stopDate ?? .distantPast) > ($1.stopDate ?? .distantPast) }
        return ListContent(sections: sections, later: later, logged: logged, tagIDsByItem: [:])
    }

    private func area(_ areaID: String) throws -> ListContent {
        let children = try select(
            "item.areaID = ? AND item.projectID IS NULL AND item.kind IN (0, 1) AND item.deletedAt IS NULL AND item.trashedAt IS NULL",
            [areaID]
        )
        let isLogged = try loggedIDs(children.map(\.id))
        var logged: [Item] = []
        var later: [Item] = []
        var current: [Item] = []
        for item in children {
            if isLogged.contains(item.id) {
                logged.append(item)
            } else if isLater(item) {
                later.append(item)
            } else {
                current.append(item)
            }
        }
        var sections: [ListSection] = []
        let todos = current.filter { $0.kind == .todo }
        let projects = current.filter { $0.kind == .project }
        if !todos.isEmpty {
            sections.append(ListSection(id: "area.\(areaID).todos", kind: .plain, title: nil, items: todos))
        }
        if !projects.isEmpty {
            sections.append(ListSection(id: "area.\(areaID).projects", kind: .plain, title: nil, items: projects))
        }
        logged.sort { ($0.stopDate ?? .distantPast) > ($1.stopDate ?? .distantPast) }
        return ListContent(sections: sections, later: later, logged: logged, tagIDsByItem: [:])
    }

    // MARK: Grouping

    /// Loose items first, then each area's loose items and projects, then projects without an area.
    private func groupedByAreaAndProject(_ items: [Item]) throws -> [ListSection] {
        var loose: [Item] = []
        var byArea: [String: [Item]] = [:]
        var byProject: [String: [Item]] = [:]
        for item in items {
            if let projectID = item.projectID {
                byProject[projectID, default: []].append(item)
            } else if let areaID = item.areaID {
                byArea[areaID, default: []].append(item)
            } else {
                loose.append(item)
            }
        }
        let parents = try Item.fetchAll(db, keys: Set(byProject.keys)).sorted { $0.sortKey < $1.sortKey }
        let headingKeys = try headingSortKeys(projectIDs: Set(byProject.keys))

        func projectSections(areaID: String?) -> [ListSection] {
            parents.filter { $0.areaID == areaID }.map { project in
                // Within a project: no-heading items first, then by heading order, then by item order.
                let members = byProject[project.id]!
                    .map { (headingKeys[$0.headingID ?? ""] ?? "", $0) }
                    .sorted { ($0.0, $0.1.sortKey) < ($1.0, $1.1.sortKey) }
                    .map(\.1)
                return ListSection(id: "project.\(project.id)", kind: .project(project.id), title: project.title, items: members)
            }
        }

        var sections: [ListSection] = []
        if !loose.isEmpty {
            sections.append(ListSection(id: "none", kind: .plain, title: nil, items: loose))
        }
        for area in try liveAreas() {
            if let areaItems = byArea[area.id] {
                sections.append(ListSection(id: "area.\(area.id)", kind: .area(area.id), title: area.title, items: areaItems))
            }
            sections += projectSections(areaID: area.id)
        }
        sections += projectSections(areaID: nil)
        return sections
    }

    /// Today's "group by project" option: loose items first, then one section per project or area.
    private func groupedByParent(_ items: [Item], idPrefix: String) throws -> [ListSection] {
        var order: [String] = []
        var groups: [String: [Item]] = [:]
        for item in items {
            let key = item.projectID ?? item.areaID ?? ""
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        order.sort { $0.isEmpty && !$1.isEmpty }
        return try order.map { key in
            if key.isEmpty {
                return ListSection(id: idPrefix, kind: .plain, title: nil, items: groups[key]!)
            }
            if let area = try Area.fetchOne(db, key: key) {
                return ListSection(id: "\(idPrefix).\(key)", kind: .area(key), title: area.title, items: groups[key]!)
            }
            let project = try Item.fetchOne(db, key: key)
            return ListSection(id: "\(idPrefix).\(key)", kind: .project(key), title: project?.title, items: groups[key]!)
        }
    }

    // MARK: Tags

    /// Keeps items tagged with `tagID` or any tag nested under it, directly or
    /// through their project or area.
    private func filter(_ content: ListContent, byTag tagID: String) throws -> ListContent {
        var wanted: Set<String> = [tagID]
        var frontier = [tagID]
        while let current = frontier.popLast() {
            let children = try String.fetchAll(db, sql: "SELECT id FROM tag WHERE parentID = ? AND deletedAt IS NULL", arguments: [current])
            for child in children where wanted.insert(child).inserted {
                frontier.append(child)
            }
        }
        let tagged = Set(try String.fetchAll(
            db,
            sql: "SELECT itemID FROM item_tag WHERE deletedAt IS NULL AND tagID IN (SELECT value FROM json_each(?))",
            arguments: [jsonArray(wanted)]
        ))
        let taggedAreas = Set(try String.fetchAll(
            db,
            sql: "SELECT areaID FROM area_tag WHERE deletedAt IS NULL AND tagID IN (SELECT value FROM json_each(?))",
            arguments: [jsonArray(wanted)]
        ))
        var projectAreas: [String: String] = [:]
        for project in try Item.fetchAll(db, keys: Set((content.allItems + content.later + content.logged).compactMap(\.projectID))) {
            projectAreas[project.id] = project.areaID
        }
        func matches(_ item: Item) -> Bool {
            if tagged.contains(item.id) { return true }
            if let projectID = item.projectID {
                if tagged.contains(projectID) { return true }
                if let areaID = projectAreas[projectID], taggedAreas.contains(areaID) { return true }
            }
            if let areaID = item.areaID, taggedAreas.contains(areaID) { return true }
            return false
        }
        var result = content
        result.sections = content.sections.compactMap { section in
            var section = section
            section.items = section.items.filter(matches)
            // Day sections in Upcoming stay even when empty, like the unfiltered list.
            if case .day = section.kind { return section }
            return section.items.isEmpty ? nil : section
        }
        result.later = content.later.filter(matches)
        result.logged = content.logged.filter(matches)
        return result
    }

    private func tagIDs(for items: [Item]) throws -> [String: [String]] {
        guard !items.isEmpty else { return [:] }
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT item_tag.itemID, item_tag.tagID FROM item_tag JOIN tag ON tag.id = item_tag.tagID
            WHERE item_tag.deletedAt IS NULL AND tag.deletedAt IS NULL
              AND item_tag.itemID IN (SELECT value FROM json_each(?))
            ORDER BY tag.sortKey
            """,
            arguments: [jsonArray(Set(items.map(\.id)))]
        )
        var result: [String: [String]] = [:]
        for row in rows {
            result[row["itemID"], default: []].append(row["tagID"])
        }
        return result
    }

    // MARK: Helpers

    private func select(_ condition: String, _ arguments: StatementArguments, order: String = "item.sortKey") throws -> [Item] {
        try Item.fetchAll(db, sql: "SELECT item.* FROM item WHERE \(condition) ORDER BY \(order)", arguments: arguments)
    }

    private func single(id: String, _ items: [Item]) -> ListContent {
        ListContent(sections: items.isEmpty ? [] : [ListSection(id: id, kind: .plain, title: nil, items: items)],
                    later: [], logged: [], tagIDsByItem: [:])
    }

    private func isLater(_ item: Item) -> Bool {
        item.bucket == .someday || (item.startDay.map { $0 > today } ?? false)
    }

    private func loggedIDs(_ ids: [String]) throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        return Set(try String.fetchAll(
            db,
            sql: "SELECT item.id FROM item WHERE item.id IN (SELECT value FROM json_each(?)) AND \(logged)",
            arguments: [jsonArray(Set(ids))] + loggedArguments
        ))
    }

    private func liveAreas() throws -> [Area] {
        try Area.filter(Column("deletedAt") == nil).order(Column("sortKey")).fetchAll(db)
    }

    private func headingSortKeys(projectIDs: Set<String>) throws -> [String: String] {
        guard !projectIDs.isEmpty else { return [:] }
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT id, sortKey FROM item WHERE kind = 2 AND projectID IN (SELECT value FROM json_each(?))",
            arguments: [jsonArray(projectIDs)]
        )
        return Dictionary(uniqueKeysWithValues: rows.map { ($0["id"], $0["sortKey"]) })
    }

    private func jsonArray(_ ids: Set<String>) -> String {
        String(decoding: try! JSONEncoder().encode(ids.sorted()), as: UTF8.self)
    }
}

extension Store {
    /// One-shot fetch of a list.
    public func fetch(_ list: ListID, tagFilter: String? = nil) async throws -> ListContent {
        let env = self.env
        return try await read { db in try ListQueries(db: db, env: env).fetch(list, tagFilter: tagFilter) }
    }

    /// Live updates for a list: emits whenever any table it reads changes.
    /// The app re-subscribes at midnight so "today" moves forward.
    public func observe(_ list: ListID, tagFilter: String? = nil) -> AsyncValueObservation<ListContent> {
        let env = self.env
        return ValueObservation
            .tracking { db in try ListQueries(db: db, env: env).fetch(list, tagFilter: tagFilter) }
            .removeDuplicates()
            .values(in: writer)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd Packages/StillpointModel && swift test`
Expected: `✔ Test run with 77 tests … passed`, with no compiler warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/StillpointModel/Sources/StillpointModel/Queries/ListContent.swift Packages/StillpointModel/Sources/StillpointModel/Queries/ListQueries.swift Packages/StillpointModel/Tests/StillpointModelTests/ListQueryTests.swift
git commit -m "feat(model): list queries and observation"
```

### Task 9: Backups and safe database opening

Spec §7: rolling backups (newest 10), an integrity check on open (a corrupt file is moved aside and the newest backup offered), and a backup before every schema upgrade (restored if the upgrade fails).
**Files:**
- Create: `Packages/StillpointModel/Sources/StillpointModel/Database/BackupManager.swift`
- Create: `Packages/StillpointModel/Sources/StillpointModel/Database/AppDatabase.swift`
- Test: `Packages/StillpointModel/Tests/StillpointModelTests/DatabaseSafetyTests.swift`

**Interfaces:**
- Consumes: `Schema`, `Store` (Tasks 4–5)
- Produces:
- `struct BackupManager: Sendable` — `init(directory:keep:)`, `makeBackup(from: any DatabaseReader, at: Date) -> URL`, `backups() -> [URL]` (newest first), `isDue(now:) -> Bool`, `restore(_:to:)`
- `enum AppDatabase` — `inMemory() -> DatabaseQueue`, `open(at:backups:now:) -> DatabasePool`
- `enum DatabaseOpenError: Error, Equatable` — `corrupted(movedTo:newestBackup:)`, `migrationFailed(message:restoredFrom:)`

- [ ] **Step 1: Write the failing tests**

`Packages/StillpointModel/Tests/StillpointModelTests/DatabaseSafetyTests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import StillpointModel

struct DatabaseSafetyTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stillpoint-tests-\(UUID().uuidString)")
    var dbURL: URL { folder.appendingPathComponent("Stillpoint.sqlite") }
    var backups: BackupManager { BackupManager(directory: folder.appendingPathComponent("Backups"), keep: 3) }
    let now = TestHarness.defaultNow

    @Test func createsAndReopensDatabase() async throws {
        do {
            let pool = try AppDatabase.open(at: dbURL, backups: backups, now: now)
            let store = Store(writer: pool, env: ModelEnvironment(now: { TestHarness.defaultNow }, calendar: .fixture(), deviceID: "d"))
            try await store.createTodo(title: "kept", in: .inbox)
            try pool.close()
        }
        let reopened = try AppDatabase.open(at: dbURL, backups: backups, now: now)
        let count = try await reopened.read { db in try Item.fetchCount(db) }
        #expect(count == 1)
    }

    @Test func corruptFileIsMovedAsideAndNewestBackupOffered() throws {
        let pool = try AppDatabase.open(at: dbURL, backups: backups, now: now)
        let backup = try backups.makeBackup(from: pool, at: now)
        // Fold the WAL into the main file first: otherwise SQLite would rebuild
        // the pages from the WAL and the "corruption" would be recoverable.
        _ = try pool.writeWithoutTransaction { db in try db.checkpoint(.truncate) }
        try pool.close()
        // Overwrite the file's pages (header included) with garbage.
        try Data(repeating: 0xAB, count: 8192).write(to: dbURL)

        #expect {
            try AppDatabase.open(at: dbURL, backups: backups, now: now)
        } throws: { error in
            guard case .corrupted(let movedTo, let newest) = error as? DatabaseOpenError else { return false }
            return newest?.lastPathComponent == backup.lastPathComponent && FileManager.default.fileExists(atPath: movedTo.path)
        }
        #expect(!FileManager.default.fileExists(atPath: dbURL.path))
    }

    @Test func failedMigrationRestoresBackup() throws {
        do {
            let pool = try AppDatabase.open(at: dbURL, backups: backups, now: now)
            try pool.write { db in
                try Item(id: "x", kind: .todo, title: "survivor", createdAt: TestHarness.defaultNow, sortKey: "V").insert(db)
            }
            try pool.close()
        }
        var broken = Schema.migrator
        broken.registerMigration("v2-broken") { db in
            try db.execute(sql: "ALTER TABLE item ADD COLUMN extra TEXT")
            try db.execute(sql: "THIS IS NOT SQL")
        }
        #expect(throws: DatabaseOpenError.self) {
            try AppDatabase.open(at: dbURL, backups: backups, now: now, migrator: broken)
        }
        let restored = try AppDatabase.open(at: dbURL, backups: backups, now: now)
        let title = try restored.read { db in try String.fetchOne(db, sql: "SELECT title FROM item") }
        #expect(title == "survivor")
    }

    @Test func backupsArePrunedAndDueDaily() throws {
        let pool = try AppDatabase.open(at: dbURL, backups: backups, now: now)
        #expect(try backups.isDue(now: now))
        for hour in 0..<5 {
            try backups.makeBackup(from: pool, at: now.addingTimeInterval(Double(hour) * 3600))
        }
        #expect(try backups.backups().count == 3)
        let newest = now.addingTimeInterval(4 * 3600)
        #expect(try !backups.isDue(now: newest.addingTimeInterval(23 * 3600)))
        #expect(try backups.isDue(now: newest.addingTimeInterval(24 * 3600)))
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd Packages/StillpointModel && swift test`
Expected: the build fails with `error: cannot find 'BackupManager' in scope`.

- [ ] **Step 3: Implement**

`Packages/StillpointModel/Sources/StillpointModel/Database/BackupManager.swift`:

```swift
import Foundation
import GRDB

/// Rolling database backups: `Stillpoint-<UTC timestamp>.sqlite` files, newest kept.
public struct BackupManager: Sendable {
    public let directory: URL
    public let keep: Int

    public init(directory: URL, keep: Int = 10) {
        self.directory = directory
        self.keep = keep
    }

    /// Copies the live database using SQLite's online backup, then prunes old backups.
    @discardableResult
    public func makeBackup(from reader: any DatabaseReader, at date: Date) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Stillpoint-\(Self.stamp(date)).sqlite")
        let destination = try DatabaseQueue(path: url.path)
        try reader.backup(to: destination)
        try destination.close()
        try prune()
        return url
    }

    /// Backups, newest first.
    public func backups() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Stillpoint-") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// True when there is no backup from the last 24 hours.
    public func isDue(now: Date) throws -> Bool {
        guard let newest = try backups().first else { return true }
        let name = newest.deletingPathExtension().lastPathComponent.dropFirst("Stillpoint-".count)
        guard let date = Self.formatter.date(from: String(name)) else { return true }
        return now.timeIntervalSince(date) >= 24 * 60 * 60
    }

    /// Replaces the database file (and its WAL/SHM files) with a backup.
    /// The database must not be open.
    public func restore(_ backup: URL, to databaseURL: URL) throws {
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        try FileManager.default.copyItem(at: backup, to: databaseURL)
    }

    private func prune() throws {
        for old in try backups().dropFirst(keep) {
            try FileManager.default.removeItem(at: old)
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()

    static func stamp(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
```

`Packages/StillpointModel/Sources/StillpointModel/Database/AppDatabase.swift`:

```swift
import Foundation
import GRDB

public enum DatabaseOpenError: Error, Equatable {
    /// The file failed SQLite's integrity check. It was moved aside; offer `newestBackup`.
    case corrupted(movedTo: URL, newestBackup: URL?)
    /// A schema upgrade failed. The pre-upgrade backup was restored.
    case migrationFailed(message: String, restoredFrom: URL)
}

/// Opening the database safely (spec §7).
public enum AppDatabase {
    /// For tests and previews.
    public static func inMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        return queue
    }

    /// Opens (or creates) the database file:
    /// 1. an existing file must pass `PRAGMA quick_check`, else it's moved aside;
    /// 2. before any schema upgrade the current file is backed up;
    /// 3. if the upgrade fails, that backup is restored and the error reported.
    public static func open(at url: URL, backups: BackupManager, now: Date) throws -> DatabasePool {
        try open(at: url, backups: backups, now: now, migrator: Schema.migrator)
    }

    static func open(at url: URL, backups: BackupManager, now: Date, migrator: DatabaseMigrator) throws -> DatabasePool {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existed = FileManager.default.fileExists(atPath: url.path)
        if existed, !passesIntegrityCheck(url) {
            let movedTo = url.deletingLastPathComponent()
                .appendingPathComponent("corrupt-\(BackupManager.stamp(now))-\(url.lastPathComponent)")
            try FileManager.default.moveItem(at: url, to: movedTo)
            for suffix in ["-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
            throw DatabaseOpenError.corrupted(movedTo: movedTo, newestBackup: try backups.backups().first)
        }

        let pool = try DatabasePool(path: url.path)
        if existed, try !pool.read({ db in try migrator.hasCompletedMigrations(db) }) {
            let backup = try backups.makeBackup(from: pool, at: now)
            do {
                try migrator.migrate(pool)
            } catch {
                try pool.close()
                try backups.restore(backup, to: url)
                throw DatabaseOpenError.migrationFailed(message: "\(error)", restoredFrom: backup)
            }
        } else {
            try migrator.migrate(pool)
        }
        return pool
    }

    private static func passesIntegrityCheck(_ url: URL) -> Bool {
        do {
            let queue = try DatabaseQueue(path: url.path)
            defer { try? queue.close() }
            let result = try queue.read { db in try String.fetchOne(db, sql: "PRAGMA quick_check") }
            return result == "ok"
        } catch {
            return false
        }
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd Packages/StillpointModel && swift test`
Expected: `✔ Test run with 81 tests … passed`, with no compiler warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/StillpointModel/Sources/StillpointModel/Database/BackupManager.swift Packages/StillpointModel/Sources/StillpointModel/Database/AppDatabase.swift Packages/StillpointModel/Tests/StillpointModelTests/DatabaseSafetyTests.swift
git commit -m "feat(model): backups, integrity check and safe migrations"
```

### Task 10: Performance budget

Spec §8: with 10,000 items, every list loads in under 100 ms. Measured on the dev machine in a debug build: Anytime ≈ 63 ms (the heaviest), Today ≈ 33 ms, Inbox ≈ 26 ms, everything else < 15 ms. Seeding takes about 11 s, so this test is the slowest in the suite.
**Files:**
- Test: `Packages/StillpointModel/Tests/StillpointModelTests/PerformanceTests.swift`

**Interfaces:**
- Consumes: everything above
- Produces:
nothing new

- [ ] **Step 1: Write the failing tests**

`Packages/StillpointModel/Tests/StillpointModelTests/PerformanceTests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import StillpointModel

/// Spec §8: a 10,000-item database opens any list in under 100 ms.
struct PerformanceTests {
    @Test func tenThousandItemsListsUnder100ms() async throws {
        let h = try TestHarness()
        let areaIDs = try await (0..<5).asyncMap { try await h.store.createArea(title: "Area \($0)").value }
        let projectIDs = try await (0..<50).asyncMap { i in
            try await h.store.createProject(title: "Project \(i)", areaID: areaIDs[i % 5]).value
        }
        try await h.store.perform("seed") { tx in
            let keys = SortKey.sequence(count: 10_000, after: nil, before: nil)
            for i in 0..<10_000 {
                var item = Item(id: tx.newID(), kind: .todo, title: "Item \(i)", createdAt: tx.now, bucket: .anytime, sortKey: keys[i])
                switch i % 4 {
                case 0: item.projectID = projectIDs[i % 50]
                case 1: item.startDay = tx.today; item.todaySortKey = keys[i]
                case 2: item.bucket = .inbox
                default: item.bucket = .someday
                }
                if i % 10 == 0 { item.status = .completed; item.stopDate = tx.now.addingTimeInterval(-3 * 86_400) }
                try tx.save(item)
            }
        }
        for list: ListID in [.inbox, .today, .upcoming, .anytime, .someday, .logbook, .allProjects, .project(projectIDs[0])] {
            let start = ContinuousClock.now
            _ = try await h.store.fetch(list)
            let elapsed = ContinuousClock.now - start
            print("PERF \(list): \(elapsed)")
            #expect(elapsed < .milliseconds(100), "\(list) took \(elapsed)")
        }
    }
}

extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self { result.append(try await transform(element)) }
        return result
    }
}
```

- [ ] **Step 2: Run the tests and confirm they pass**

Run: `cd Packages/StillpointModel && swift test`
Expected: `✔ Test run with 82 tests … passed`, with no compiler warnings.

- [ ] **Step 3: Commit**

```bash
git add Packages/StillpointModel/Tests/StillpointModelTests/PerformanceTests.swift
git commit -m "test(model): 10k-item performance budget"
```

---

## Self-review against the spec

| Spec section | Covered by |
|---|---|
| §4.1 tables | Task 4 |
| §4.2 list definitions | Task 8 (all twelve lists plus the tag filter) |
| §4.3 rules 1–8 | Task 5 (`Rules`, rule 6 relaxed as noted); rule 7 in `setStatus` (Task 6) |
| §4.4 sync-ready properties | Tasks 1–5 (Day, SortKey, UUIDv7, change log with HLC, tombstones) |
| §6.4 undo | Task 5 (field-level), and every command returns `Committed.undo` |
| §7 backups, migrations, integrity | Task 9 |
| §7 typing debounce, write-failure banner, logging, diagnostics | Plans 2–4 (app layer) |
| §8 model tests and performance | Tasks 1–10; snapshot tests, XCUITest and CI are in Plans 2–4 |
