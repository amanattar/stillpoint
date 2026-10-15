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
