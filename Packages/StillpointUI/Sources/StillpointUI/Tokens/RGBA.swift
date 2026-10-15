import SwiftUI

/// A colour defined in code, so tests can check contrast without rendering.
public struct RGBA: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    /// `0xRRGGBB`, fully opaque.
    public init(hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// WCAG relative luminance (alpha ignored).
    public var luminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.039_28 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio, from 1 (none) to 21 (black on white).
    public func contrast(with other: RGBA) -> Double {
        let (a, b) = (luminance + 0.05, other.luminance + 0.05)
        return max(a, b) / min(a, b)
    }
}
