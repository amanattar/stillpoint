import Foundation
import GRDB

/// A set of items that share one ordering ("key space").
struct Container {
    let sql: String
    let arguments: StatementArguments

    static let inbox = Container(sql: "kind = 0 AND bucket = 0", arguments: [])
    static let today = Container(sql: "todaySortKey IS NOT NULL", arguments: [])
    static func noParent(_ bucket: Bucket) -> Container {
        Container(sql: "kind = 0 AND projectID IS NULL AND areaID IS NULL AND bucket = ?", arguments: [bucket.rawValue])
    }
    static func areaTodos(_ areaID: String) -> Container {
        Container(sql: "kind = 0 AND projectID IS NULL AND areaID = ?", arguments: [areaID])
    }
    static func projects(inArea areaID: String?) -> Container {
        Container(sql: "kind = 1 AND areaID IS ?", arguments: [areaID])
    }
    static func project(_ projectID: String) -> Container {
        Container(sql: "projectID = ?", arguments: [projectID])
    }

    /// The container an item currently belongs to.
    static func of(_ item: Item) -> Container {
        if item.kind == .project { return .projects(inArea: item.areaID) }
        if let projectID = item.projectID { return .project(projectID) }
        if let areaID = item.areaID { return .areaTodos(areaID) }
        if item.bucket == .inbox { return .inbox }
        return .noParent(item.bucket)
    }
}

extension Transaction {
    /// A live (not tombstoned) item.
    func item(_ id: String) throws -> Item {
        guard let item = try Item.fetchOne(db, key: id), item.deletedAt == nil else {
            throw ModelError.notFound("item \(id)")
        }
        return item
    }

    func items(_ ids: [String]) throws -> [Item] {
        try ids.map(item)
    }

    /// Live, untrashed items matching `sql`.
    func liveItems(where sql: String, _ arguments: StatementArguments = []) throws -> [Item] {
        try Item.fetchAll(db, sql: "SELECT * FROM item WHERE deletedAt IS NULL AND (\(sql)) ORDER BY sortKey", arguments: arguments)
    }

    /// `count` new keys for `column` in `container`: after `afterID` (before its
    /// next sibling) or, with no `afterID`, at the end.
    func newKeys(_ count: Int, column: OrderColumn = .sortKey, in container: Container, after afterID: String? = nil) throws -> [String] {
        let col = column.rawValue
        if let afterID,
           let lower = try String.fetchOne(db, sql: "SELECT \(col) FROM item WHERE id = ?", arguments: [afterID]) {
            let upper = try String.fetchOne(
                db,
                sql: "SELECT MIN(\(col)) FROM item WHERE deletedAt IS NULL AND (\(container.sql)) AND \(col) > ?",
                arguments: container.arguments + [lower]
            )
            return SortKey.sequence(count: count, after: lower, before: upper)
        }
        let last = try String.fetchOne(
            db,
            sql: "SELECT MAX(\(col)) FROM item WHERE deletedAt IS NULL AND (\(container.sql))",
            arguments: container.arguments
        )
        return SortKey.sequence(count: count, after: last, before: nil)
    }

    /// Keys for items placed between two neighbours from a displayed list.
    /// Throws if the neighbours are out of order. The neighbours needn't be
    /// adjacent in storage (hidden items may sit between them): the new keys
    /// go directly after `afterID` and never collide with an existing key.
    func keysBetween(_ count: Int, column: OrderColumn, after afterID: String?, before beforeID: String?, moving ids: [String] = []) throws -> [String] {
        let col = column.rawValue
        func key(_ id: String?) throws -> String? {
            guard let id else { return nil }
            return try String.fetchOne(db, sql: "SELECT \(col) FROM item WHERE id = ?", arguments: [id])
        }
        let container: Container
        if column == .todaySortKey {
            container = .today
        } else if let neighbourID = afterID ?? beforeID ?? ids.first {
            container = Container.of(try item(neighbourID))
        } else {
            return SortKey.sequence(count: count, after: nil, before: nil)
        }
        return try boundedKeys(
            count, table: "item", column: col, scope: container.sql, container.arguments,
            excluding: ids, lower: try key(afterID), upper: try key(beforeID)
        )
    }

    /// `count` keys in (lower, upper) for `table.column` within `scope`, tightened
    /// so they can't equal any other row's key: with a lower bound they go
    /// directly after it; with only an upper bound, directly before it; with
    /// neither, at the end.
    func boundedKeys(
        _ count: Int, table: String, column: String, scope: String, _ arguments: StatementArguments,
        excluding ids: [String], lower: String?, upper: String?
    ) throws -> [String] {
        if let lower, let upper, lower >= upper {
            throw ModelError.invalidMove("neighbours out of order")
        }
        let excluded = String(decoding: try JSONEncoder().encode(ids), as: UTF8.self)
        let base = "deletedAt IS NULL AND (\(scope)) AND id NOT IN (SELECT value FROM json_each(?))"
        var low = lower
        var high = upper
        if let lower {
            let next = try String.fetchOne(
                db, sql: "SELECT MIN(\(column)) FROM \(table) WHERE \(base) AND \(column) > ?",
                arguments: arguments + [excluded, lower]
            )
            if let next, high.map({ next < $0 }) ?? true {
                high = next
            }
        } else if let upper {
            low = try String.fetchOne(
                db, sql: "SELECT MAX(\(column)) FROM \(table) WHERE \(base) AND \(column) < ?",
                arguments: arguments + [excluded, upper]
            )
        } else {
            low = try String.fetchOne(
                db, sql: "SELECT MAX(\(column)) FROM \(table) WHERE \(base)",
                arguments: arguments + [excluded]
            )
        }
        return SortKey.sequence(count: count, after: low, before: high)
    }

    /// Open, untrashed to-dos directly under a project or heading.
    func openTodos(under parentID: String) throws -> [Item] {
        try liveItems(where: "kind = 0 AND status = 0 AND trashedAt IS NULL AND (projectID = ? OR headingID = ?)", [parentID, parentID])
    }
}
