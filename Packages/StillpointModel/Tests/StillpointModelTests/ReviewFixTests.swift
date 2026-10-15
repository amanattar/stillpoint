import Foundation
import GRDB
import Testing
@testable import StillpointModel

/// Regression tests for the final branch review of plan 1.
struct ReviewFixTests {
    // Finding 1: Put Back of a project with a heading.
    @Test func putBackProjectWithHeadingRestoresWholeStructure() async throws {
        let h = try TestHarness()
        let project = try await h.store.createProject(title: "P").value
        let heading = try await h.store.createHeading(title: "H", projectID: project).value
        let todo = try await h.store.createTodo(in: .heading(heading)).value
        try await h.store.trash([project])
        try await h.store.putBack([project])
        #expect(try await h.item(project).trashedAt == nil)
        #expect(try await h.item(heading).trashedAt == nil)
        #expect(try await h.item(heading).projectID == project)
        #expect(try await h.item(todo).headingID == heading)
        #expect(try await h.item(todo).trashedAt == nil)
    }

    // Finding 2: undoing an older step must never leave a row that breaks the rules.
    @Test func undoingScheduleAfterReminderKeepsItemValid() async throws {
        let h = try TestHarness()
        let id = try await h.store.createTodo(title: "x", in: .inbox).value
        let schedule = try await h.store.schedule([id], .today)
        try await h.store.setReminder(id, minutes: 540)
        try await h.store.undo(schedule.undo)
        let item = try await h.item(id)
        #expect(item.startDay == nil && item.reminderTime == nil && item.bucket == .inbox)
        try await h.store.rename(id, to: "still editable")
    }

    @Test func undoingOlderMoveKeepsItemValid() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "A").value
        let project = try await h.store.createProject(title: "P").value
        let id = try await h.store.createTodo(title: "x", in: .inbox).value
        let first = try await h.store.move([id], to: .project(project))
        try await h.store.move([id], to: .area(area))
        try await h.store.undo(first.undo)
        let item = try await h.item(id)
        #expect(item.bucket == .inbox && item.projectID == nil && item.areaID == nil)
        try await h.store.rename(id, to: "still editable")
    }

    @Test func undoThatWouldOrphanLaterChildrenIsRefused() async throws {
        let h = try TestHarness()
        let id = try await h.store.createTodo(title: "x", in: .anytime).value
        let convert = try await h.store.convertToProject(id)
        let child = try await h.store.createTodo(title: "child", in: .project(id)).value
        await #expect(throws: ModelError.undoConflict) {
            try await h.store.undo(convert.undo)
        }
        #expect(try await h.item(id).kind == .project)
        try await h.store.rename(child, to: "still editable")
    }

    // Finding 3: checklist keys.
    @Test func checklistReorderWithLooseNeighboursNeverDuplicatesKeys() async throws {
        let h = try TestHarness()
        let todo = try await h.store.createTodo(in: .inbox).value
        let a = try await h.store.addChecklistItem(to: todo, title: "a").value
        _ = try await h.store.addChecklistItem(to: todo, title: "b")
        _ = try await h.store.addChecklistItem(to: todo, title: "c")
        let d = try await h.store.addChecklistItem(to: todo, title: "d").value
        // "b" and "c" lie between the given neighbours: "d" goes directly after "a".
        try await h.store.reorderChecklistItem(d, after: a, before: nil)
        let rows = try await h.store.read { db in
            try ChecklistItem.filter(Column("itemID") == todo).order(Column("sortKey")).fetchAll(db)
        }
        #expect(rows.map(\.title) == ["a", "d", "b", "c"])
        #expect(Set(rows.map(\.sortKey)).count == rows.count)
    }

    @Test func addingAfterDuplicateChecklistKeysDoesNotCrash() async throws {
        let h = try TestHarness()
        let todo = try await h.store.createTodo(in: .inbox).value
        _ = try await h.store.perform("legacy data") { tx in
            try tx.save(ChecklistItem(id: "x", itemID: todo, title: "x", createdAt: tx.now, sortKey: "W"))
            try tx.save(ChecklistItem(id: "y", itemID: todo, title: "y", createdAt: tx.now, sortKey: "W"))
        }
        let new = try await h.store.addChecklistItem(to: todo, title: "new", after: "x").value
        let key = try await h.store.read { db in try ChecklistItem.fetchOne(db, key: new)!.sortKey }
        #expect(key > "W")
    }

    @Test func itemReorderWithLooseNeighboursNeverDuplicatesKeys() async throws {
        let h = try TestHarness()
        let a = try await h.store.createTodo(title: "a", in: .inbox).value
        _ = try await h.store.createTodo(title: "b", in: .inbox)
        let c = try await h.store.createTodo(title: "c", in: .inbox).value
        try await h.store.reorder([c], after: a, before: nil)
        #expect(try await h.titles(where: "bucket = 0") == ["a", "c", "b"])
        let keys = try await h.store.read { db in try String.fetchAll(db, sql: "SELECT sortKey FROM item") }
        #expect(Set(keys).count == keys.count)
    }

    @Test func areaReorderWithLooseNeighboursNeverDuplicatesKeys() async throws {
        let h = try TestHarness()
        let a = try await h.store.createArea(title: "a").value
        _ = try await h.store.createArea(title: "b")
        let c = try await h.store.createArea(title: "c").value
        try await h.store.reorderArea(c, after: a, before: nil)
        let areas = try await h.store.read { db in try Area.order(Column("sortKey")).fetchAll(db) }
        #expect(areas.map(\.title) == ["a", "c", "b"])
        #expect(Set(areas.map(\.sortKey)).count == areas.count)
    }

    @Test func todayReorderWorksNextToItemsThatArrivedByDate() async throws {
        let h = try TestHarness()
        let a = try await h.store.createTodo(title: "a", in: .today).value
        _ = try await h.store.createTodo(title: "b", in: .today)
        let c = try await h.store.createTodo(title: "c", in: .anytime).value
        let d = try await h.store.createTodo(title: "d", in: .anytime).value
        try await h.store.schedule([c, d], .day(h.today.adding(days: 1, calendar: .fixture())))
        h.advance(days: 1)
        // c and d rolled into Today by date and have no Today order yet.
        #expect(try await h.store.fetch(.today).allItems.map(\.title) == ["a", "b", "c", "d"])
        try await h.store.reorder([a], after: c, before: d, column: .todaySortKey)
        #expect(try await h.store.fetch(.today).allItems.map(\.title) == ["b", "c", "a", "d"])
    }

    // Finding 10: only real corruption moves the file aside, and its WAL moves with it.
    @Test func unreadableFileIsNotTreatedAsCorrupt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sp-\(UUID().uuidString)")
        let url = folder.appendingPathComponent("Stillpoint.sqlite")
        let backups = BackupManager(directory: folder.appendingPathComponent("Backups"))
        try AppDatabase.open(at: url, backups: backups, now: TestHarness.defaultNow).close()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        #expect {
            try AppDatabase.open(at: url, backups: backups, now: TestHarness.defaultNow)
        } throws: { error in
            !(error is DatabaseOpenError)
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func corruptFileKeepsItsWALAlongside() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Stillpoint.sqlite")
        try Data(repeating: 0xAB, count: 8192).write(to: url)
        try Data("wal contents".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))
        let backups = BackupManager(directory: folder.appendingPathComponent("Backups"))
        #expect {
            try AppDatabase.open(at: url, backups: backups, now: TestHarness.defaultNow)
        } throws: { error in
            guard case .corrupted(let movedTo, _) = error as? DatabaseOpenError else { return false }
            return FileManager.default.fileExists(atPath: movedTo.path + "-wal")
        }
    }
}
