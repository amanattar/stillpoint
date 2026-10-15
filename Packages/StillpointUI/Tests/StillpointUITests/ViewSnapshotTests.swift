import AppKit
import SnapshotTesting
import SwiftUI
import Testing
@testable import StillpointUI

/// Renders each leaf view in every palette. The first run records reference
/// images into `__Snapshots__`; later runs compare against them.
@MainActor
struct ViewSnapshotTests {
    func render(_ variant: PaletteVariant, scale: TextScale = .medium, @ViewBuilder _ content: () -> some View) -> NSView {
        let palette = Palette.variant(variant)
        let root = content()
            .padding(12)
            .background(palette.background.color)
            .environment(\.palette, palette)
            .environment(\.textScale, scale)
            .environment(\.colorScheme, variant == .light ? .light : .dark)
        let view = NSHostingView(rootView: root)
        view.frame.size = view.fittingSize
        return view
    }

    func check(
        _ view: NSView, named name: String,
        fileID: StaticString = #fileID, file: StaticString = #filePath,
        testName: String = #function, line: UInt = #line, column: UInt = #column
    ) {
        assertSnapshot(
            of: view, as: .image(precision: 0.99, perceptualPrecision: 0.98), named: name,
            fileID: fileID, file: file, testName: testName, line: line, column: column
        )
    }

    @Test(arguments: PaletteVariant.allCases)
    func checkboxes(_ variant: PaletteVariant) {
        check(render(variant) {
            HStack(spacing: 10) {
                CheckboxView(.open)
                CheckboxView(.completed)
                CheckboxView(.canceled)
                ProgressPie(0)
                ProgressPie(0.4)
                ProgressPie(1)
            }
        }, named: variant.rawValue)
    }

    @Test(arguments: PaletteVariant.allCases)
    func badges(_ variant: PaletteVariant) {
        check(render(variant) {
            HStack(spacing: 10) {
                TagPill("Errand")
                DeadlineBadge("Fri", isDue: false)
                DeadlineBadge("Today", isDue: true)
                CountBadge(4)
                CountBadge(2, isAlert: true)
            }
        }, named: variant.rawValue)
    }

    @Test(arguments: PaletteVariant.allCases)
    func listIcons(_ variant: PaletteVariant) {
        check(render(variant) {
            HStack(spacing: 10) {
                ForEach([ListSymbol.inbox, .today, .evening, .upcoming, .anytime, .someday, .logbook, .trash, .deadlines], id: \.self) {
                    ListIcon($0)
                }
            }
        }, named: variant.rawValue)
    }

    @Test(arguments: TextScale.allCases)
    func scalesTogether(_ scale: TextScale) {
        check(render(.light, scale: scale) {
            HStack(spacing: 8) {
                CheckboxView(.open)
                TagPill("Home")
                CountBadge(12)
            }
        }, named: "scale-\(scale.rawValue)")
    }
}
