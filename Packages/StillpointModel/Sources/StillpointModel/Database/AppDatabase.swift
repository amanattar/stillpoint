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
