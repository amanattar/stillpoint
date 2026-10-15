import Testing
@testable import StillpointUI

struct TokenTests {
    @Test(arguments: PaletteVariant.allCases)
    func textMeetsContrastTargets(_ variant: PaletteVariant) {
        let p = Palette.variant(variant)
        // WCAG: 7:1 for body text (AAA), 4.5:1 for secondary text (AA), 3:1 for tertiary/large text.
        #expect(p.textPrimary.contrast(with: p.background) >= 7)
        #expect(p.textSecondary.contrast(with: p.background) >= 4.5)
        #expect(p.textTertiary.contrast(with: p.background) >= 3)
        #expect(p.textPrimary.contrast(with: p.raisedBackground) >= 7)
        #expect(p.checkboxStroke.contrast(with: p.background) >= 3)
    }

    @Test(arguments: PaletteVariant.allCases)
    func tintedTextMeetsContrastTargets(_ variant: PaletteVariant) {
        let p = Palette.variant(variant)
        // The due-count badge: text on a deadline-coloured fill (small text, 4.5:1).
        #expect(p.onDeadline.contrast(with: p.deadline) >= 4.5, "badge text in \(variant)")
        // Deadline badge text on the background (small text, 4.5:1).
        #expect(p.deadline.contrast(with: p.background) >= 4.5)
        // "This Evening" section title (large semibold text, 3:1).
        #expect(p.evening.contrast(with: p.background) >= 3)
    }

    @Test(arguments: PaletteVariant.allCases)
    func listTintsAreVisibleAsIcons(_ variant: PaletteVariant) {
        let p = Palette.variant(variant)
        let symbols: [ListSymbol] = [.inbox, .today, .evening, .upcoming, .anytime, .someday, .logbook, .trash, .deadlines]
        for symbol in symbols {
            // 3:1 is the WCAG minimum for meaningful graphics.
            #expect(symbol.tint(in: p).contrast(with: p.background) >= 3, "\(symbol) in \(variant)")
        }
    }

    @Test func contrastMath() {
        #expect(abs(RGBA(hex: 0x000000).contrast(with: RGBA(hex: 0xFFFFFF)) - 21) < 0.01)
        #expect(RGBA(hex: 0x777777).contrast(with: RGBA(hex: 0x777777)) == 1)
    }

    @Test func scaleMultipliesEveryToken() {
        let medium = Metrics(.medium)
        let large = Metrics(.extraLarge)
        #expect(medium.rowHeight == 30)
        #expect(large.rowHeight == 39)
        #expect(Metrics(.small).checkbox == 14)
    }

    @Test func blackOnlyChangesSurfaces() {
        #expect(Palette.black.textPrimary == Palette.dark.textPrimary)
        #expect(Palette.black.today == Palette.dark.today)
        #expect(Palette.black.background == RGBA(hex: 0x000000))
    }
}
