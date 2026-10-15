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
