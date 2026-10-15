import Foundation
import GRDB
import Testing
@testable import StillpointModel

/// Tests the write pipeline directly through `perform`, without commands.
struct PipelineTests {
    static func save(_ h: TestHarness, _ change: @escaping @Sendable (inout Item) -> Void, id: String = "a") async throws -> UndoStep {
        try await h.store.perform("edit") { tx in
            var item = try Item.fetchOne(tx.db, key: id)
                ?? Item(id: id, kind: .todo, createdAt: tx.now, sortKey: "V")
            change(&item)
            try tx.save(item)
        }.undo
    }

    @Test func everyWriteAppendsChangeWithChangedFieldsOnly() async throws {
        let h = try TestHarness()
        _ = try await Self.save(h) { $0.title = "A" }
        _ = try await Self.save(h) { $0.title = "B" }
        let changes = try await h.changes()
        #expect(changes.count == 2)
        #expect(changes[1].entity == "item" && changes[1].entityID == "a")
        #expect(changes[1].fieldList == ["title"])
        #expect(changes[0].hlc < changes[1].hlc)
        #expect(changes.allSatisfy { $0.deviceID == "test-device" && $0.pushedAt == nil })
    }

    @Test func noOpWriteIsSkipped() async throws {
        let h = try TestHarness()
        _ = try await Self.save(h) { $0.title = "A" }
        let step = try await Self.save(h) { $0.title = "A" }
        #expect(step.isEmpty)
        #expect(try await h.changes().count == 1)
    }

    @Test func undoAndRedoRoundTrip() async throws {
        let h = try TestHarness()
        _ = try await Self.save(h) { $0.title = "A" }
        let rename = try await Self.save(h) { $0.title = "B" }
        let redo = try await h.store.undo(rename)
        #expect(try await h.item("a").title == "A")
        try await h.store.undo(redo)
        #expect(try await h.item("a").title == "B")
    }

    @Test func undoingCreateTombstonesAndRedoRestores() async throws {
        let h = try TestHarness()
        let created = try await Self.save(h) { $0.title = "A" }
        let redo = try await h.store.undo(created)
        #expect(try await h.item("a").deletedAt != nil)
        try await h.store.undo(redo)
        #expect(try await h.item("a").deletedAt == nil)
    }

    @Test func undoingAnOlderStepKeepsLaterEditsToOtherFields() async throws {
        let h = try TestHarness()
        _ = try await Self.save(h) { $0.title = "A" }
        let rename = try await Self.save(h) { $0.title = "B" }
        _ = try await Self.save(h) { $0.notes = "later note" }
        try await h.store.undo(rename)
        let item = try await h.item("a")
        #expect(item.title == "A")
        #expect(item.notes == "later note")
    }

    @Test func manyRowsInOneStepUndoTogether() async throws {
        let h = try TestHarness()
        _ = try await Self.save(h, { $0.title = "A" }, id: "a")
        _ = try await Self.save(h, { $0.title = "B" }, id: "b")
        let step = try await h.store.perform("bulk") { tx in
            for id in ["a", "b"] {
                var item = try Item.fetchOne(tx.db, key: id)!
                item.bucket = .someday
                try tx.save(item)
            }
        }.undo
        try await h.store.undo(step)
        #expect(try await h.item("a").bucket == .inbox)
        #expect(try await h.item("b").bucket == .inbox)
    }

    @Test func failedTransactionWritesNothing() async throws {
        let h = try TestHarness()
        await #expect(throws: ModelError.self) {
            try await h.store.perform("broken") { tx in
                try tx.save(Item(id: "ok", kind: .todo, createdAt: tx.now, sortKey: "V"))
                var bad = Item(id: "bad", kind: .todo, createdAt: tx.now, sortKey: "W")
                bad.isEvening = true // violates "This Evening requires a start date"
                try tx.save(bad)
            }
        }
        #expect(try await h.changes().isEmpty)
        #expect(try await h.store.read { db in try Item.fetchCount(db) } == 0)
    }
}
