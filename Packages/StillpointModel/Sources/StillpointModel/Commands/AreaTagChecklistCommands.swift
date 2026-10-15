import Foundation
import GRDB

extension Store {
    // MARK: Areas

    @discardableResult
    public func createArea(title: String) async throws -> Committed<String> {
        try await perform("New Area") { tx in
            let last = try String.fetchOne(tx.db, sql: "SELECT MAX(sortKey) FROM area WHERE deletedAt IS NULL")
            let area = Area(id: tx.newID(), title: title, createdAt: tx.now, sortKey: SortKey.between(last, nil))
            try tx.save(area)
            return area.id
        }
    }

    @discardableResult
    public func updateArea(_ id: String, _ change: @escaping @Sendable (inout Area) -> Void) async throws -> Committed<Void> {
        try await perform("Edit Area") { tx in
            guard var area = try Area.fetchOne(tx.db, key: id), area.deletedAt == nil else { throw ModelError.notFound("area \(id)") }
            change(&area)
            try tx.save(area)
        }
    }

    /// Places an area between two neighbouring areas in the sidebar.
    @discardableResult
    public func reorderArea(_ id: String, after afterID: String?, before beforeID: String?) async throws -> Committed<Void> {
        try await perform("Move") { tx in
            func key(_ id: String?) throws -> String? {
                guard let id else { return nil }
                return try String.fetchOne(tx.db, sql: "SELECT sortKey FROM area WHERE id = ?", arguments: [id])
            }
            let lower = try key(afterID), upper = try key(beforeID)
            if let lower, let upper, lower >= upper { throw ModelError.invalidMove("neighbours out of order") }
            guard var area = try Area.fetchOne(tx.db, key: id) else { throw ModelError.notFound("area \(id)") }
            area.sortKey = SortKey.between(lower, upper)
            try tx.save(area)
        }
    }

    /// Deletes an area. Its projects and to-dos go to the Trash.
    @discardableResult
    public func deleteArea(_ id: String) async throws -> Committed<Void> {
        try await perform("Delete Area") { tx in
            guard let area = try Area.fetchOne(tx.db, key: id), area.deletedAt == nil else { throw ModelError.notFound("area \(id)") }
            for item in try tx.liveItems(where: "areaID = ? AND trashedAt IS NULL", [id]) {
                try Store.trash(item, in: tx)
            }
            for link in try AreaTag.filter(Column("areaID") == id && Column("deletedAt") == nil).fetchAll(tx.db) {
                try tx.delete(link)
            }
            try tx.delete(area)
        }
    }

    @discardableResult
    public func setAreaTags(_ areaID: String, _ tagIDs: Set<String>) async throws -> Committed<Void> {
        try await perform("Tags") { tx in
            let existing = try AreaTag.filter(Column("areaID") == areaID).fetchAll(tx.db)
            for link in existing where link.deletedAt == nil && !tagIDs.contains(link.tagID) {
                try tx.delete(link)
            }
            for tagID in tagIDs {
                var link = existing.first { $0.tagID == tagID } ?? AreaTag(areaID: areaID, tagID: tagID, createdAt: tx.now)
                link.deletedAt = nil
                try tx.save(link)
            }
        }
    }

    // MARK: Tags

    @discardableResult
    public func createTag(title: String, parentID: String? = nil) async throws -> Committed<String> {
        try await perform("New Tag") { tx in
            let last = try String.fetchOne(tx.db, sql: "SELECT MAX(sortKey) FROM tag WHERE deletedAt IS NULL AND parentID IS ?", arguments: [parentID])
            var tag = Tag(id: tx.newID(), title: title, createdAt: tx.now, sortKey: SortKey.between(last, nil))
            tag.parentID = parentID
            try tx.save(tag)
            return tag.id
        }
    }

    @discardableResult
    public func renameTag(_ id: String, to title: String) async throws -> Committed<Void> {
        try await perform("Rename Tag") { tx in
            var tag = try Store.tag(id, in: tx)
            tag.title = title
            try tx.save(tag)
        }
    }

    /// Sets the ⌃-shortcut key. Each key can belong to only one tag.
    @discardableResult
    public func setTagShortcut(_ id: String, _ shortcut: String?) async throws -> Committed<Void> {
        try await perform("Tag Shortcut") { tx in
            var tag = try Store.tag(id, in: tx)
            let normalized = shortcut.flatMap { $0.isEmpty ? nil : String($0.prefix(1)).lowercased() }
            if let normalized {
                let taken = try Tag.filter(Column("shortcut") == normalized && Column("deletedAt") == nil && Column("id") != id).fetchCount(tx.db)
                if taken > 0 { throw ModelError.duplicateShortcut(normalized) }
            }
            tag.shortcut = normalized
            try tx.save(tag)
        }
    }

    /// Nests a tag under another. Refuses to create a cycle.
    @discardableResult
    public func setTagParent(_ id: String, _ parentID: String?) async throws -> Committed<Void> {
        try await perform("Move Tag") { tx in
            var tag = try Store.tag(id, in: tx)
            var ancestor = parentID
            while let current = ancestor {
                if current == id { throw ModelError.ruleViolation("tag can't be nested inside itself") }
                ancestor = try Store.tag(current, in: tx).parentID
            }
            tag.parentID = parentID
            try tx.save(tag)
        }
    }

    /// Deletes a tag, its nested tags, and their links to items and areas.
    @discardableResult
    public func deleteTag(_ id: String) async throws -> Committed<Void> {
        try await perform("Delete Tag") { tx in
            var queue = [id]
            while let current = queue.popLast() {
                let tag = try Store.tag(current, in: tx)
                queue += try String.fetchAll(tx.db, sql: "SELECT id FROM tag WHERE parentID = ? AND deletedAt IS NULL", arguments: [current])
                for link in try ItemTag.filter(Column("tagID") == current && Column("deletedAt") == nil).fetchAll(tx.db) {
                    try tx.delete(link)
                }
                for link in try AreaTag.filter(Column("tagID") == current && Column("deletedAt") == nil).fetchAll(tx.db) {
                    try tx.delete(link)
                }
                try tx.delete(tag)
            }
        }
    }

    /// Replaces the tags on every item in `ids`.
    @discardableResult
    public func setTags(_ ids: [String], _ tagIDs: Set<String>) async throws -> Committed<Void> {
        try await perform("Tags") { tx in
            for itemID in ids {
                _ = try tx.item(itemID)
                let existing = try ItemTag.filter(Column("itemID") == itemID).fetchAll(tx.db)
                for link in existing where link.deletedAt == nil && !tagIDs.contains(link.tagID) {
                    try tx.delete(link)
                }
                for tagID in tagIDs {
                    var link = existing.first { $0.tagID == tagID } ?? ItemTag(itemID: itemID, tagID: tagID, createdAt: tx.now)
                    link.deletedAt = nil
                    try tx.save(link)
                }
            }
        }
    }

    /// ⌃ + shortcut: removes the tag if every item has it, otherwise adds it to all.
    @discardableResult
    public func toggleTag(_ ids: [String], _ tagID: String) async throws -> Committed<Void> {
        try await perform("Tags") { tx in
            let links = try ItemTag.filter(ids.contains(Column("itemID")) && Column("tagID") == tagID).fetchAll(tx.db)
            let tagged = Set(links.filter { $0.deletedAt == nil }.map(\.itemID))
            let removing = ids.allSatisfy(tagged.contains)
            for itemID in ids {
                var link = links.first { $0.itemID == itemID } ?? ItemTag(itemID: itemID, tagID: tagID, createdAt: tx.now)
                if removing {
                    try tx.delete(link)
                } else {
                    link.deletedAt = nil
                    try tx.save(link)
                }
            }
        }
    }

    static func tag(_ id: String, in tx: Transaction) throws -> Tag {
        guard let tag = try Tag.fetchOne(tx.db, key: id), tag.deletedAt == nil else { throw ModelError.notFound("tag \(id)") }
        return tag
    }

    // MARK: Checklist

    @discardableResult
    public func addChecklistItem(to itemID: String, title: String, after afterID: String? = nil) async throws -> Committed<String> {
        try await perform("Add Checklist Item") { tx in
            let siblings = try ChecklistItem
                .filter(Column("itemID") == itemID && Column("deletedAt") == nil)
                .order(Column("sortKey"))
                .fetchAll(tx.db)
            let lower: String?
            let upper: String?
            if let afterID, let index = siblings.firstIndex(where: { $0.id == afterID }) {
                lower = siblings[index].sortKey
                upper = index + 1 < siblings.count ? siblings[index + 1].sortKey : nil
            } else {
                lower = siblings.last?.sortKey
                upper = nil
            }
            let entry = ChecklistItem(id: tx.newID(), itemID: itemID, title: title, createdAt: tx.now, sortKey: SortKey.between(lower, upper))
            try tx.save(entry)
            return entry.id
        }
    }

    @discardableResult
    public func updateChecklistItem(_ id: String, _ change: @escaping @Sendable (inout ChecklistItem) -> Void) async throws -> Committed<Void> {
        try await perform("Edit Checklist") { tx in
            guard var entry = try ChecklistItem.fetchOne(tx.db, key: id), entry.deletedAt == nil else {
                throw ModelError.notFound("checklist item \(id)")
            }
            change(&entry)
            try tx.save(entry)
        }
    }

    /// Places a checklist item between two neighbours.
    @discardableResult
    public func reorderChecklistItem(_ id: String, after afterID: String?, before beforeID: String?) async throws -> Committed<Void> {
        try await perform("Move") { tx in
            func key(_ id: String?) throws -> String? {
                guard let id else { return nil }
                return try String.fetchOne(tx.db, sql: "SELECT sortKey FROM checklist_item WHERE id = ?", arguments: [id])
            }
            let lower = try key(afterID), upper = try key(beforeID)
            if let lower, let upper, lower >= upper { throw ModelError.invalidMove("neighbours out of order") }
            guard var entry = try ChecklistItem.fetchOne(tx.db, key: id) else { throw ModelError.notFound("checklist item \(id)") }
            entry.sortKey = SortKey.between(lower, upper)
            try tx.save(entry)
        }
    }

    @discardableResult
    public func deleteChecklistItem(_ id: String) async throws -> Committed<Void> {
        try await perform("Delete Checklist Item") { tx in
            guard let entry = try ChecklistItem.fetchOne(tx.db, key: id), entry.deletedAt == nil else {
                throw ModelError.notFound("checklist item \(id)")
            }
            try tx.delete(entry)
        }
    }

    // MARK: Settings

    /// The settings row, or defaults if none has been saved yet.
    public static func settings(in db: Database, now: Date) throws -> Settings {
        try Settings.fetchOne(db, key: Settings.singletonID) ?? Settings(createdAt: now)
    }

    /// Changes settings other than the log policy (use `setLogPolicy` for that).
    @discardableResult
    public func updateSettings(_ change: @escaping @Sendable (inout Settings) -> Void) async throws -> Committed<Void> {
        try await perform("Settings") { tx in
            var settings = try Store.settings(in: tx.db, now: tx.now)
            let policy = settings.logPolicy
            change(&settings)
            if settings.logPolicy != policy {
                throw ModelError.ruleViolation("use setLogPolicy to change the log policy")
            }
            try tx.save(settings)
        }
    }
}
