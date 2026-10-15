import Testing
@testable import StillpointFeatures
import StillpointModel
import StillpointUI

struct StorageKeyTests {
    @Test(arguments: [ListID.inbox, .today, .upcoming, .anytime, .someday, .deadlines, .logbook, .trash,
                      .allProjects, .laterProjects, .project("0193-a"), .area("0193-b")])
    func storageKeyRoundTrips(_ list: ListID) {
        #expect(ListID(storageKey: list.storageKey) == list)
    }

    @Test func unknownKeysAreRejected() {
        #expect(ListID(storageKey: "") == nil)
        #expect(ListID(storageKey: "project:") == nil)
        #expect(ListID(storageKey: "bogus") == nil)
    }
}
