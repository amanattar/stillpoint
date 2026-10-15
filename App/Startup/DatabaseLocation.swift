import Foundation
import StillpointModel

/// Where the database and its backups live. Inside the app sandbox,
/// Application Support resolves to the app's container.
struct DatabaseLocation {
    let folder: URL

    var database: URL { folder.appendingPathComponent("Stillpoint.sqlite") }
    var backups: BackupManager { BackupManager(directory: folder.appendingPathComponent("Backups")) }

    /// `~/Library/Application Support/Stillpoint`, or a sibling folder named by the
    /// `-dataFolderName` launch argument (used for demo data and manual testing).
    static func resolve(_ defaults: UserDefaults = .standard) -> DatabaseLocation {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let name = defaults.string(forKey: "dataFolderName").map { "Stillpoint-\($0)" } ?? "Stillpoint"
        return DatabaseLocation(folder: support.appendingPathComponent(name, isDirectory: true))
    }

    /// A throwaway folder, used when the app is hosting unit tests.
    static func temporary() -> DatabaseLocation {
        DatabaseLocation(folder: FileManager.default.temporaryDirectory
            .appendingPathComponent("Stillpoint-TestHost-\(UUID().uuidString)", isDirectory: true))
    }
}
