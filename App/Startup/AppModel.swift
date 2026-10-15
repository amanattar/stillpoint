import Foundation
import GRDB
import Observation
import StillpointModel

/// Opens the database and owns the `Store` for every window.
@MainActor
@Observable
final class AppModel {
    struct DatabaseProblem: Equatable {
        var message: String
        /// The newest backup, offered for restore when the database was damaged.
        var backup: URL?
        /// True when a damaged file was moved aside, so starting with an empty database is safe.
        var canStartFresh: Bool
    }

    enum Phase: Equatable {
        case loading
        case ready
        case failed(DatabaseProblem)
    }

    private(set) var phase: Phase = .loading
    private(set) var store: Store?
    private(set) var settings: Settings
    let clock: DayClock
    let location: DatabaseLocation

    @ObservationIgnored private let deviceID: String
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var pool: DatabasePool?
    @ObservationIgnored private var settingsTask: Task<Void, Never>?

    init(location: DatabaseLocation, deviceID: String, now: @escaping @Sendable () -> Date = { Date() }, clock: DayClock) {
        self.location = location
        self.deviceID = deviceID
        self.now = now
        self.clock = clock
        settings = Settings(createdAt: now())
        clock.onDayChange = { [weak self] in self?.backUpIfDue() }
    }

    static func live() -> AppModel {
        let defaults = UserDefaults.standard
        let deviceID: String
        if let saved = defaults.string(forKey: "deviceID") {
            deviceID = saved
        } else {
            deviceID = UUID().uuidString.lowercased()
            defaults.set(deviceID, forKey: "deviceID")
        }
        return AppModel(location: isTestHost ? .temporary() : .resolve(defaults), deviceID: deviceID, clock: DayClock())
    }

    /// When the app is only hosting unit tests, it must never open the real database.
    static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Opens the database once; later calls (from extra windows) do nothing.
    func start() {
        guard phase == .loading, store == nil else { return }
        open()
    }

    func restoreBackup(_ backup: URL) {
        do {
            try location.backups.restore(backup, to: location.database)
            phase = .loading
            open()
        } catch {
            phase = .failed(DatabaseProblem(message: "The backup couldn't be restored: \(error.localizedDescription)", backup: nil, canStartFresh: true))
        }
    }

    /// After a damaged file was moved aside: start with an empty database.
    func startFresh() {
        phase = .loading
        open()
    }

    private func open() {
        do {
            let pool = try AppDatabase.open(at: location.database, backups: location.backups, now: now())
            self.pool = pool
            #if DEBUG
            let assertOnRuleViolation = true
            #else
            let assertOnRuleViolation = false
            #endif
            let env = ModelEnvironment(now: now, calendar: clock.calendar, deviceID: deviceID, assertOnRuleViolation: assertOnRuleViolation)
            store = Store(writer: pool, env: env)
            phase = .ready
            backUpIfDue()
            observeSettings()
        } catch DatabaseOpenError.corrupted(_, let newestBackup) {
            phase = .failed(DatabaseProblem(
                message: "Your Stillpoint database is damaged. It has been moved aside so nothing is lost.",
                backup: newestBackup, canStartFresh: true
            ))
        } catch DatabaseOpenError.migrationFailed(let message, _) {
            phase = .failed(DatabaseProblem(
                message: "Stillpoint couldn't update your database (\(message)). Your data was restored from the backup made just before the update.",
                backup: nil, canStartFresh: false
            ))
        } catch {
            phase = .failed(DatabaseProblem(message: error.localizedDescription, backup: nil, canStartFresh: false))
        }
    }

    /// Daily backup: at launch and whenever the day changes while running.
    private func backUpIfDue() {
        guard let pool else { return }
        do {
            if try location.backups.isDue(now: now()) {
                try location.backups.makeBackup(from: pool, at: now())
            }
        } catch {
            // A failed backup must never stop the app; the next day change retries.
        }
    }

    private func observeSettings() {
        guard let store else { return }
        settingsTask?.cancel()
        settingsTask = Task { [weak self] in
            do {
                for try await settings in store.observeSettings() {
                    self?.settings = settings
                }
            } catch {}
        }
    }
}
