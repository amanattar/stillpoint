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

    /// Keys strictly between two neighbouring items' keys. Throws if the
    /// neighbours are out of order (they must come from the same displayed list).
    func keysBetween(_ count: Int, column: OrderColumn, after afterID: String?, before beforeID: String?) throws -> [String] {
        let col = column.rawValue
        func key(_ id: String?) throws -> String? {
            guard let id else { return nil }
            return try String.fetchOne(db, sql: "SELECT \(col) FROM item WHERE id = ?", arguments: [id])
        }
        let lower = try key(afterID)
        let upper = try key(beforeID)
        if let lower, let upper, lower >= upper {
            throw ModelError.invalidMove("neighbours out of order")
        }
        return SortKey.sequence(count: count, after: lower, before: upper)
    }

    /// Open, untrashed to-dos directly under a project or heading.
    func openTodos(under parentID: String) throws -> [Item] {
        try liveItems(where: "kind = 0 AND status = 0 AND trashedAt IS NULL AND (projectID = ? OR headingID = ?)", [parentID, parentID])
    }
}
