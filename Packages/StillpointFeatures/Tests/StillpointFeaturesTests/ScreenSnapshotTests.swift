import AppKit
import SnapshotTesting
import StillpointModel
import StillpointUI
import SwiftUI
import Testing
@testable import StillpointFeatures

/// Renders whole screens with demo data. The first run records references in `__Snapshots__`.
@MainActor
struct ScreenSnapshotTests {
    func render(_ variant: PaletteVariant, size: CGSize, @ViewBuilder _ content: () -> some View) -> NSView {
        let palette = Palette.variant(variant)
        let view = NSHostingView(rootView: content()
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(palette.background.color)
            .environment(\.palette, palette)
            .environment(\.colorScheme, variant == .light ? .light : .dark))
        view.frame.size = size
        return view
    }

    /// AppKit-backed views (the sidebar `List` is an outline view) only draw inside a
    /// window after a layout pass, so host them offscreen and let the run loop settle.
    func renderInWindow(_ variant: PaletteVariant, size: CGSize, @ViewBuilder _ content: () -> some View) -> NSView {
        let view = render(variant, size: size, content)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: variant == .light ? .aqua : .darkAqua)
        window.contentView = view
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        view.layoutSubtreeIfNeeded()
        return view
    }

    func listBody(_ list: ListID, store: Store, title: String) async throws -> some View {
        let content = try await store.fetch(list)
        return ListBody(list: list, title: title, notes: "", content: content, dates: dates(),
                        showsLater: .constant(true), showsLogged: .constant(false))
            .padding(.horizontal, 24)
    }

    @Test(arguments: [PaletteVariant.light, .dark])
    func today(_ variant: PaletteVariant) async throws {
        let store = try await makeStore(demo: true)
        let body = try await listBody(.today, store: store, title: "Today")
        assertSnapshot(of: render(variant, size: CGSize(width: 620, height: 420)) { body },
                       as: .image(precision: 0.99, perceptualPrecision: 0.98), named: variant.rawValue)
    }

    @Test func upcoming() async throws {
        let store = try await makeStore(demo: true)
        let body = try await listBody(.upcoming, store: store, title: "Upcoming")
        assertSnapshot(of: render(.light, size: CGSize(width: 620, height: 760)) { body },
                       as: .image(precision: 0.99, perceptualPrecision: 0.98))
    }

    @Test func project() async throws {
        let store = try await makeStore(demo: true)
        let projectID = try await store.fetch(.allProjects).allItems.first { $0.title == "Website relaunch" }!.id
        let body = try await listBody(.project(projectID), store: store, title: "Website relaunch")
        assertSnapshot(of: render(.light, size: CGSize(width: 620, height: 360)) { body },
                       as: .image(precision: 0.99, perceptualPrecision: 0.98))
    }

    @Test func sidebar() async throws {
        let store = try await makeStore(demo: true)
        let content = try await store.fetchSidebar()
        assertSnapshot(of: renderInWindow(.light, size: CGSize(width: 240, height: 520)) {
            SidebarList(content: content, selection: .constant(nil))
        }, as: .image(precision: 0.99, perceptualPrecision: 0.98))
    }
}
