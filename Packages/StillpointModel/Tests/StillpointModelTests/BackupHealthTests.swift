import Foundation
import GRDB
import Testing
@testable import StillpointModel

/// Plan 2 final review: a damaged newest backup must not be offered forever.
struct BackupHealthTests {
    @Test func damagedDatabaseOffersNewestHealthyBackup() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stillpoint-tests-\(UUID().uuidString)")
        let dbURL = folder.appendingPathComponent("Stillpoint.sqlite")
        let backups = BackupManager(directory: folder.appendingPathComponent("Backups"))
        let now = TestHarness.defaultNow

        let pool = try AppDatabase.open(at: dbURL, backups: backups, now: now)
        let older = try backups.makeBackup(from: pool, at: now)
        let newer = try backups.makeBackup(from: pool, at: now.addingTimeInterval(3600))
        _ = try pool.writeWithoutTransaction { db in try db.checkpoint(.truncate) }
        try pool.close()
        // Both the database and the newest backup are damaged.
        try Data(repeating: 0xAB, count: 8192).write(to: newer)
        try Data(repeating: 0xAB, count: 8192).write(to: dbURL)

        #expect {
            try AppDatabase.open(at: dbURL, backups: backups, now: now)
        } throws: { error in
            guard case .corrupted(_, let offered) = error as? DatabaseOpenError else { return false }
            return offered?.lastPathComponent == older.lastPathComponent
        }
    }

    @Test func noHealthyBackupOffersNone() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stillpoint-tests-\(UUID().uuidString)")
        let backups = BackupManager(directory: folder.appendingPathComponent("Backups"))
        try FileManager.default.createDirectory(at: backups.directory, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 8192).write(to: backups.directory.appendingPathComponent("Stillpoint-20261015-100000-000.sqlite"))
        #expect(try backups.newestHealthyBackup() == nil)
    }
}
