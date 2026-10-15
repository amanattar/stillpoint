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
