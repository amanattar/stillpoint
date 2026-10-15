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

    /// The newest backup that passes SQLite's integrity check, so a damaged
    /// backup is never offered for restore. Unreadable backups count as damaged.
    public func newestHealthyBackup() throws -> URL? {
        try backups().first { (try? AppDatabase.passesIntegrityCheck($0)) == true }
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
