import Foundation
import GRDB
import Testing
@testable import StillpointModel

/// Each test writes a deliberately broken item directly through a transaction.
struct RulesTests {
    /// Seeds project "P", project "Q" and heading "H" (in Q), then expects `build` to be rejected.
    func expectViolation(_ build: @escaping @Sendable (Transaction) throws -> Item) async throws {
        let h = try TestHarness()
        _ = try await h.store.perform("seed") { tx in
            let p = Item(id: "P", kind: .project, title: "P", createdAt: tx.now, bucket: .anytime, sortKey: "V")
            let q = Item(id: "Q", kind: .project, title: "Q", createdAt: tx.now, bucket: .anytime, sortKey: "W")
            var heading = Item(id: "H", kind: .heading, title: "H", createdAt: tx.now, bucket: .anytime, sortKey: "X")
            heading.projectID = "Q"
            try tx.save(p)
            try tx.save(q)
            try tx.save(heading)
        }
        await #expect(throws: ModelError.self) {
            try await h.store.perform("test") { tx in
                try tx.save(try build(tx))
            }
        }
    }

    static func todo(_ tx: Transaction) -> Item {
        Item(id: tx.newID(), kind: .todo, createdAt: tx.now, bucket: .anytime, sortKey: "V")
    }

    static func id(_ tx: Transaction, titled title: String) throws -> String {
        try String.fetchOne(tx.db, sql: "SELECT id FROM item WHERE title = ?", arguments: [title])!
    }

    @Test func headingNeedsProject() async throws {
        try await expectViolation { tx in
            Item(id: tx.newID(), kind: .heading, createdAt: tx.now, bucket: .anytime, sortKey: "V")
        }
    }

    @Test func projectsCantNest() async throws {
        try await expectViolation { tx in
            var p = Item(id: tx.newID(), kind: .project, createdAt: tx.now, bucket: .anytime, sortKey: "V")
            p.projectID = try Self.id(tx, titled: "P")
            return p
        }
    }

    @Test func todoMustBeInItsHeadingsProject() async throws {
        try await expectViolation { tx in
            var t = Self.todo(tx)
            t.projectID = try Self.id(tx, titled: "P")
            t.headingID = try Self.id(tx, titled: "H") // H belongs to Q
            return t
        }
    }

    @Test func todoInProjectHasNoArea() async throws {
        try await expectViolation { tx in
            let area = Area(id: tx.newID(), title: "A", createdAt: tx.now, sortKey: "V")
            try tx.save(area)
            var t = Self.todo(tx)
            t.projectID = try Self.id(tx, titled: "P")
            t.areaID = area.id
            return t
        }
    }

    @Test func startDayRequiresAnytime() async throws {
        try await expectViolation { tx in
            var t = Self.todo(tx)
            t.bucket = .someday
            t.startDay = tx.today
            return t
        }
    }

    @Test func eveningRequiresStartDay() async throws {
        try await expectViolation { tx in
            var t = Self.todo(tx)
            t.isEvening = true
            return t
        }
    }

    @Test func inboxItemsHaveNoParentOrDate() async throws {
        try await expectViolation { tx in
            var t = Self.todo(tx)
            t.bucket = .inbox
            t.projectID = try Self.id(tx, titled: "P")
            return t
        }
    }

    @Test func checklistParentMustBeTodo() async throws {
        let h = try TestHarness()
        await #expect(throws: ModelError.self) {
            try await h.store.perform("test") { tx in
                try tx.save(Item(id: "P", kind: .project, createdAt: tx.now, bucket: .anytime, sortKey: "V"))
                try tx.save(ChecklistItem(id: "c", itemID: "P", title: "x", createdAt: tx.now, sortKey: "V"))
            }
        }
    }

    @Test func validWritesPass() async throws {
        let h = try TestHarness()
        _ = try await h.store.perform("valid") { tx in
            let project = Item(id: "P", kind: .project, createdAt: tx.now, bucket: .anytime, sortKey: "V")
            var heading = Item(id: "H", kind: .heading, createdAt: tx.now, bucket: .anytime, sortKey: "W")
            heading.projectID = "P"
            var todo = Item(id: "T", kind: .todo, createdAt: tx.now, bucket: .anytime, sortKey: "X")
            todo.projectID = "P"
            todo.headingID = "H"
            todo.startDay = tx.today
            todo.isEvening = true
            try tx.save(project)
            try tx.save(heading)
            try tx.save(todo)
        }
    }
}
