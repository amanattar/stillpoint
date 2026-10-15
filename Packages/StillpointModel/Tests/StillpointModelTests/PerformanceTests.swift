import Foundation
import GRDB
import Testing
@testable import StillpointModel

/// Spec §8: a 10,000-item database opens any list in under 100 ms.
struct PerformanceTests {
    @Test func tenThousandItemsListsUnder100ms() async throws {
        let h = try TestHarness()
        let areaIDs = try await (0..<5).asyncMap { try await h.store.createArea(title: "Area \($0)").value }
        let projectIDs = try await (0..<50).asyncMap { i in
            try await h.store.createProject(title: "Project \(i)", areaID: areaIDs[i % 5]).value
        }
        _ = try await h.store.perform("seed") { tx in
            let keys = SortKey.sequence(count: 10_000, after: nil, before: nil)
            for i in 0..<10_000 {
                var item = Item(id: tx.newID(), kind: .todo, title: "Item \(i)", createdAt: tx.now, bucket: .anytime, sortKey: keys[i])
                switch i % 4 {
                case 0: item.projectID = projectIDs[i % 50]
                case 1: item.startDay = tx.today; item.todaySortKey = keys[i]
                case 2: item.bucket = .inbox
                default: item.bucket = .someday
                }
                if i % 10 == 0 { item.status = .completed; item.stopDate = tx.now.addingTimeInterval(-3 * 86_400) }
                try tx.save(item)
            }
        }
        for list: ListID in [.inbox, .today, .upcoming, .anytime, .someday, .logbook, .allProjects, .project(projectIDs[0])] {
            let start = ContinuousClock.now
            _ = try await h.store.fetch(list)
            let elapsed = ContinuousClock.now - start
            print("PERF \(list): \(elapsed)")
            #expect(elapsed < .milliseconds(100), "\(list) took \(elapsed)")
        }
    }
}

extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self { result.append(try await transform(element)) }
        return result
    }
}
