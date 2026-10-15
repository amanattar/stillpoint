import Foundation
import GRDB
import Testing
@testable import StillpointModel

struct AreaTagChecklistTests {
    @Test func deletingAreaTrashesContentAndPutBackDetachesIt() async throws {
        let h = try TestHarness()
        let area = try await h.store.createArea(title: "Old").value
        let project = try await h.store.createProject(title: "P", areaID: area).value
        let todo = try await h.store.createTodo(title: "t", in: .area(area)).value
        try await h.store.deleteArea(area)
        #expect(try await h.item(project).trashedAt != nil)
        #expect(try await h.item(todo).trashedAt != nil)
        try await h.store.putBack([todo, project])
        #expect(try await h.item(todo).areaID == nil)
        #expect(try await h.item(todo).bucket == .anytime)
        #expect(try await h.item(project).areaID == nil)
    }

    @Test func areaReorderAndUpdate() async throws {
        let h = try TestHarness()
        let a = try await h.store.createArea(title: "A").value
        let b = try await h.store.createArea(title: "B").value
        try await h.store.reorderArea(b, after: nil, before: a)
        try await h.store.updateArea(a) { $0.isCollapsed = true }
        let areas = try await h.store.read { db in try Area.order(Column("sortKey")).fetchAll(db) }
        #expect(areas.map(\.title) == ["B", "A"])
        #expect(areas[1].isCollapsed)
    }

    @Test func tagShortcutsAreUniqueCaseInsensitively() async throws {
        let h = try TestHarness()
        let home = try await h.store.createTag(title: "Home").value
        let work = try await h.store.createTag(title: "Work").value
        try await h.store.setTagShortcut(home, "H")
        await #expect(throws: ModelError.duplicateShortcut("h")) {
            try await h.store.setTagShortcut(work, "h")
        }
        try await h.store.setTagShortcut(home, nil)
        try await h.store.setTagShortcut(work, "h")
    }

    @Test func tagNestingRefusesCycles() async throws {
        let h = try TestHarness()
        let a = try await h.store.createTag(title: "A").value
        let b = try await h.store.createTag(title: "B", parentID: a).value
        await #expect(throws: ModelError.self) { try await h.store.setTagParent(a, b) }
        await #expect(throws: ModelError.self) { try await h.store.setTagParent(a, a) }
    }

    @Test func deletingTagRemovesNestedTagsAndLinks() async throws {
        let h = try TestHarness()
        let parent = try await h.store.createTag(title: "P").value
        let child = try await h.store.createTag(title: "C", parentID: parent).value
        let todo = try await h.store.createTodo(in: .inbox).value
        try await h.store.setTags([todo], [child])
        try await h.store.deleteTag(parent)
        let live = try await h.store.read { db in
            (try Tag.filter(Column("deletedAt") == nil).fetchCount(db),
             try ItemTag.filter(Column("deletedAt") == nil).fetchCount(db))
        }
        #expect(live == (0, 0))
        #expect(try await h.tagIDs(todo).isEmpty)
    }

    @Test func toggleTagAddsToAllUnlessAllHaveIt() async throws {
        let h = try TestHarness()
        let tag = try await h.store.createTag(title: "T").value
        let a = try await h.store.createTodo(in: .inbox).value
        let b = try await h.store.createTodo(in: .inbox).value
        try await h.store.setTags([a], [tag])
        try await h.store.toggleTag([a, b], tag)
        #expect(try await h.tagIDs(a) == [tag])
        #expect(try await h.tagIDs(b) == [tag])
        try await h.store.toggleTag([a, b], tag)
        #expect(try await h.tagIDs(a).isEmpty)
        #expect(try await h.tagIDs(b).isEmpty)
        try await h.store.toggleTag([a], tag) // re-adding revives the tombstoned link
        #expect(try await h.tagIDs(a) == [tag])
    }

    @Test func checklistInsertAfterAndReorder() async throws {
        let h = try TestHarness()
        let todo = try await h.store.createTodo(in: .inbox).value
        let one = try await h.store.addChecklistItem(to: todo, title: "one").value
        let three = try await h.store.addChecklistItem(to: todo, title: "three").value
        _ = try await h.store.addChecklistItem(to: todo, title: "two", after: one)
        func titles() async throws -> [String] {
            try await h.store.read { db in
                try ChecklistItem.filter(Column("itemID") == todo && Column("deletedAt") == nil).order(Column("sortKey")).fetchAll(db).map(\.title)
            }
        }
        #expect(try await titles() == ["one", "two", "three"])
        try await h.store.reorderChecklistItem(three, after: nil, before: one)
        #expect(try await titles() == ["three", "one", "two"])
        try await h.store.deleteChecklistItem(three)
        #expect(try await titles() == ["one", "two"])
    }

}
