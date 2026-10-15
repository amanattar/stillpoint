import SwiftUI

/// A list's symbol in its tint, sized for the sidebar or a list header.
public struct ListIcon: View {
    public var symbol: ListSymbol
    public var size: CGFloat?
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics

    public init(_ symbol: ListSymbol, size: CGFloat? = nil) {
        self.symbol = symbol
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol.systemName)
            .font(.system(size: size ?? metrics.sidebarIcon, weight: .medium))
            .foregroundStyle(symbol.tint(in: palette).color)
            .accessibilityHidden(true)
    }
}
