import SwiftUI

/// The single text-size setting. Every font size and spacing token is
/// multiplied by `factor`, so the whole interface scales together.
public enum TextScale: Int, CaseIterable, Sendable {
    case small = 0, medium = 1, large = 2, extraLarge = 3

    public var factor: CGFloat {
        switch self {
        case .small: 0.9
        case .medium: 1.0
        case .large: 1.15
        case .extraLarge: 1.3
        }
    }
}

extension EnvironmentValues {
    @Entry public var textScale: TextScale = .medium
}
