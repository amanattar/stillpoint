import Foundation
import GRDB

public struct SidebarProject: Sendable, Equatable, Identifiable {
    public var item: Item
    /// Closed to-dos ÷ all to-dos (0 when empty), for the progress pie.
    public var progress: Double

    public var id: String { item.id }
}

public struct SidebarArea: Sendable, Equatable, Identifiable {
    public var area: Area
    public var projects: [SidebarProject]

    public var id: String { area.id }
}

/// Everything the sidebar shows below the fixed lists.
public struct SidebarContent: Sendable, Equatable {
    /// Open to-dos in the Inbox.
    public var inboxCount: Int
    /// Open to-dos and projects in Today.
    public var todayCount: Int
    /// Open Today items whose deadline is today or earlier (shown as a red badge).
    public var dueCount: Int
    /// Active projects that aren't in an area.
    public var looseProjects: [SidebarProject]
    public var areas: [SidebarArea]
}

extension ListQueries {
    func sidebar() throws -> SidebarContent {
        let inboxCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM item WHERE item.kind = 0 AND item.bucket = 0 AND item.status = 0 AND \(visible)",
            arguments: visibleArguments
        ) ?? 0
        let todayCondition = """
            item.kind IN (0, 1) AND item.status = 0 AND \(visible)
              AND ((item.bucket = 1 AND item.startDay <= ?) OR item.deadlineDay <= ?)
            """
        let todayCount = try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM item WHERE \(todayCondition)",
            arguments: visibleArguments + [today, today]
        ) ?? 0
        let dueCount = try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM item WHERE \(todayCondition) AND item.deadlineDay <= ?",
            arguments: visibleArguments + [today, today, today]
        ) ?? 0

        let projects = try Item.fetchAll(
            db,
            sql: """
            SELECT item.* FROM item WHERE item.kind = 1 AND \(visible)
              AND item.bucket = 1 AND (item.startDay IS NULL OR item.startDay <= ?)
            ORDER BY item.sortKey
            """,
            arguments: visibleArguments + [today]
        )
        let progress = try projectProgress(for: projects.map(\.id))
        let rows = projects.map { SidebarProject(item: $0, progress: progress[$0.id] ?? 0) }
        let areas = try Area.filter(Column("deletedAt") == nil).order(Column("sortKey")).fetchAll(db)
        return SidebarContent(
            inboxCount: inboxCount,
            todayCount: todayCount,
            dueCount: dueCount,
            looseProjects: rows.filter { $0.item.areaID == nil },
            areas: areas.map { area in SidebarArea(area: area, projects: rows.filter { $0.item.areaID == area.id }) }
        )
    }

    /// Closed ÷ total live to-dos for each project.
    func projectProgress(for projectIDs: [String]) throws -> [String: Double] {
        guard !projectIDs.isEmpty else { return [:] }
        let ids = String(decoding: try JSONEncoder().encode(projectIDs), as: UTF8.self)
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT projectID, COUNT(*) AS total, SUM(status != 0) AS closed FROM item
            WHERE kind = 0 AND deletedAt IS NULL AND trashedAt IS NULL
              AND projectID IN (SELECT value FROM json_each(?))
            GROUP BY projectID
            """,
            arguments: [ids]
        )
        var result: [String: Double] = [:]
        for row in rows {
            let total: Int = row["total"]
            let closed: Int = row["closed"]
            result[row["projectID"]] = total == 0 ? 0 : Double(closed) / Double(total)
        }
        return result
    }
}

extension Store {
    public func fetchSidebar() async throws -> SidebarContent {
        let env = self.env
        return try await read { db in try ListQueries(db: db, env: env).sidebar() }
    }

    public func observeSidebar() -> AsyncValueObservation<SidebarContent> {
        let env = self.env
        return ValueObservation
            .tracking { db in try ListQueries(db: db, env: env).sidebar() }
            .removeDuplicates()
            .values(in: writer)
    }

    /// Live settings (defaults until the first change is saved).
    public func observeSettings() -> AsyncValueObservation<Settings> {
        let env = self.env
        return ValueObservation
            .tracking { db in try Store.settings(in: db, now: env.now()) }
            .removeDuplicates()
            .values(in: writer)
    }
}
