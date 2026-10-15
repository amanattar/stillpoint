import SwiftUI

/// Light, Dark, and Black (true-black backgrounds for OLED-style dark).
public enum PaletteVariant: String, CaseIterable, Sendable {
    case light, dark, black
}

/// Stillpoint's colours: warm neutrals plus one tint per built-in list.
public struct Palette: Sendable, Equatable {
    public var background: RGBA
    /// Expanded cards and grouped surfaces.
    public var raisedBackground: RGBA
    public var separator: RGBA
    public var textPrimary: RGBA
    public var textSecondary: RGBA
    public var textTertiary: RGBA
    public var checkboxStroke: RGBA

    public var inbox: RGBA
    public var today: RGBA
    public var evening: RGBA
    public var upcoming: RGBA
    public var anytime: RGBA
    public var someday: RGBA
    public var logbook: RGBA
    public var trash: RGBA
    public var deadline: RGBA
    /// Text drawn on a `deadline`-filled badge.
    public var onDeadline: RGBA

    public static func variant(_ variant: PaletteVariant) -> Palette {
        switch variant {
        case .light: .light
        case .dark: .dark
        case .black: .black
        }
    }

    public static let light = Palette(
        background: RGBA(hex: 0xFDFCFA),
        raisedBackground: RGBA(hex: 0xFFFFFF),
        separator: RGBA(hex: 0xE8E4DE),
        textPrimary: RGBA(hex: 0x1F1C18),
        textSecondary: RGBA(hex: 0x6B655E),
        textTertiary: RGBA(hex: 0x8F8880),
        checkboxStroke: RGBA(hex: 0x8C857C),
        inbox: RGBA(hex: 0x2F74E8),
        today: RGBA(hex: 0xC27800),
        evening: RGBA(hex: 0x5B57D9),
        upcoming: RGBA(hex: 0xD93D42),
        anytime: RGBA(hex: 0x0E8F80),
        someday: RGBA(hex: 0x9C7F4F),
        logbook: RGBA(hex: 0x2A8F5E),
        trash: RGBA(hex: 0x7D7F8A),
        deadline: RGBA(hex: 0xC92A5F),
        onDeadline: RGBA(hex: 0xFFFFFF)
    )

    public static let dark = Palette(
        background: RGBA(hex: 0x1E1C1A),
        raisedBackground: RGBA(hex: 0x292624),
        separator: RGBA(hex: 0x36322E),
        textPrimary: RGBA(hex: 0xF2EFEA),
        textSecondary: RGBA(hex: 0xADA69E),
        textTertiary: RGBA(hex: 0x8A837B),
        checkboxStroke: RGBA(hex: 0x8A837B),
        inbox: RGBA(hex: 0x5C9BFF),
        today: RGBA(hex: 0xF7B955),
        evening: RGBA(hex: 0x8F8CFF),
        upcoming: RGBA(hex: 0xFF6B70),
        anytime: RGBA(hex: 0x2EC5B0),
        someday: RGBA(hex: 0xD2B88A),
        logbook: RGBA(hex: 0x4CC38A),
        trash: RGBA(hex: 0x9EA0AB),
        deadline: RGBA(hex: 0xF0709A),
        onDeadline: RGBA(hex: 0x1E1C1A)
    )

    public static let black: Palette = {
        var palette = Palette.dark
        palette.background = RGBA(hex: 0x000000)
        palette.raisedBackground = RGBA(hex: 0x141312)
        palette.separator = RGBA(hex: 0x2A2724)
        return palette
    }()
}

extension EnvironmentValues {
    @Entry public var palette: Palette = .light
}
