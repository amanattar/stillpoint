import SwiftUI
import Testing
@testable import Stillpoint
import StillpointModel
import StillpointUI

struct AppearanceTests {
    @Test func appearanceMapping() {
        #expect(AppearanceMapping.colorScheme(for: .automatic) == nil)
        #expect(AppearanceMapping.colorScheme(for: .black) == .dark)
        #expect(AppearanceMapping.variant(for: .black, effective: .dark) == .black)
        #expect(AppearanceMapping.variant(for: .automatic, effective: .dark) == .dark)
        #expect(AppearanceMapping.variant(for: .light, effective: .light) == .light)
    }
}
