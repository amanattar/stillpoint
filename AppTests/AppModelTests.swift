import Foundation
import GRDB
import Testing
@testable import Stillpoint
import StillpointModel

@MainActor
struct AppModelTests {
    func makeModel(folder: URL) -> AppModel {
        AppModel(
            location: DatabaseLocation(folder: folder), deviceID: "test", now: { fixedNow },
            clock: DayClock(calendar: utcCalendar(), now: { fixedNow }, center: NotificationCenter())
        )
    }

    @Test func opensNewDatabaseAndBacksUp() throws {
        let folder = temporaryFolder()
        let model = makeModel(folder: folder)
        model.start()
        #expect(model.phase == .ready)
        #expect(model.store != nil)
        #expect(try model.location.backups.backups().count == 1)
        model.start() // a second window doesn't reopen
        #expect(try model.location.backups.backups().count == 1)
    }

    @Test func damagedDatabaseOffersBackupAndRestores() async throws {
        let folder = temporaryFolder()
        do {
            let model = makeModel(folder: folder)
            model.start()
            try await model.store!.createTodo(title: "Keep me", in: .inbox)
            // Back up the current state, then flush and corrupt the file.
            let backup = try model.location.backups.makeBackup(from: model.store!.writer, at: fixedNow.addingTimeInterval(60))
            _ = backup
            _ = try await model.store!.writer.writeWithoutTransaction { db in try db.checkpoint(.truncate) }
        }
        try Data(repeating: 0xAB, count: 8192).write(to: folder.appendingPathComponent("Stillpoint.sqlite"))

        let reopened = makeModel(folder: folder)
        reopened.start()
        guard case .failed(let problem) = reopened.phase, let backup = problem.backup else {
            Issue.record("expected a damaged-database problem with a backup, got \(reopened.phase)")
            return
        }
        #expect(problem.canStartFresh)
        reopened.restoreBackup(backup)
        #expect(reopened.phase == .ready)
        #expect(try await reopened.store!.fetch(.inbox).allItems.map(\.title) == ["Keep me"])
    }

    @Test func startFreshAfterDamage() throws {
        let folder = temporaryFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 8192).write(to: folder.appendingPathComponent("Stillpoint.sqlite"))
        let model = makeModel(folder: folder)
        model.start()
        guard case .failed(let problem) = model.phase else {
            Issue.record("expected failure")
            return
        }
        #expect(problem.backup == nil && problem.canStartFresh)
        model.startFresh()
        #expect(model.phase == .ready)
    }
}

extension AppModelTests {
    @Test func testHostNeverUsesTheRealDatabase() {
        #expect(AppModel.isTestHost)
        let live = AppModel.live()
        #expect(live.location.folder.path.contains("Stillpoint-TestHost-"))
        #expect(!live.location.folder.path.hasSuffix("Application Support/Stillpoint"))
    }
}

extension AppModelTests {
    /// Plan 2 final review: a Mac left running must back up every 24 hours,
    /// not only at launch and at midnight (which gave ~39-hour gaps).
    @Test func backsUpEvery24HoursWhileRunning() throws {
        let clock = MovableNow()
        let model = AppModel(
            location: DatabaseLocation(folder: temporaryFolder()), deviceID: "test", now: { clock.now },
            clock: DayClock(calendar: utcCalendar(), now: { clock.now }, center: NotificationCenter())
        )
        model.start()
        #expect(try model.location.backups.backups().count == 1)
        let timer = try #require(model.backupTimer)
        #expect(timer.isValid && timer.timeInterval == AppModel.backupCheckInterval)
        #expect(AppModel.backupCheckInterval <= 3600)

        clock.advance(hours: 23)
        timer.fire()
        #expect(try model.location.backups.backups().count == 1)
        clock.advance(hours: 2)
        timer.fire()
        #expect(try model.location.backups.backups().count == 2)
    }
}
