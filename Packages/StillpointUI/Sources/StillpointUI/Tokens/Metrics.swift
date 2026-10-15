import SwiftUI

/// Sizes and spacing at medium text size. Use `scaled(_:)` for actual values.
public struct Metrics: Sendable {
    public let scale: CGFloat

    public init(_ textScale: TextScale) {
        scale = textScale.factor
    }

    public func scaled(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded(.toNearestOrAwayFromZero)
    }

    public var rowHeight: CGFloat { scaled(30) }
    public var rowHeightWithDetail: CGFloat { scaled(42) }
    public var checkbox: CGFloat { scaled(15) }
    public var contentInset: CGFloat { scaled(24) }
    public var rowSpacing: CGFloat { scaled(8) }
    public var sidebarRowHeight: CGFloat { scaled(28) }
    public var sidebarIcon: CGFloat { scaled(16) }

    // Fonts (SF Pro via the system font).
    public var listTitle: Font { .system(size: scale * 26, weight: .bold) }
    public var sectionTitle: Font { .system(size: scale * 15, weight: .semibold) }
    public var rowTitle: Font { .system(size: scale * 14) }
    public var rowDetail: Font { .system(size: scale * 11.5) }
    public var badge: Font { .system(size: scale * 11, weight: .medium) }
    public var pill: Font { .system(size: scale * 10.5, weight: .medium) }
    public var sidebarItem: Font { .system(size: scale * 13.5) }
    public var sidebarArea: Font { .system(size: scale * 13.5, weight: .semibold) }
}

extension EnvironmentValues {
    public var metrics: Metrics { Metrics(textScale) }
}
