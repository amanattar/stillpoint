import SwiftUI

/// A tag on a row: small text in an outlined capsule.
public struct TagPill: View {
    public var title: String
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(metrics.pill)
            .foregroundStyle(palette.textSecondary.color)
            .lineLimit(1)
            .padding(.horizontal, metrics.scaled(6))
            .padding(.vertical, metrics.scaled(1.5))
            .overlay(Capsule().strokeBorder(palette.textTertiary.color.opacity(0.6), lineWidth: 1))
            .fixedSize()
    }
}

/// A deadline on a row, e.g. "Fri" or "2 days left". Turns red when due or overdue.
public struct DeadlineBadge: View {
    public var text: String
    public var isDue: Bool
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics

    public init(_ text: String, isDue: Bool) {
        self.text = text
        self.isDue = isDue
    }

    public var body: some View {
        Label(text, systemImage: "flag.fill")
            .labelStyle(.titleAndIcon)
            .font(metrics.badge)
            .foregroundStyle(isDue ? palette.deadline.color : palette.textSecondary.color)
            .lineLimit(1)
            .fixedSize()
    }
}

/// The number at the end of a sidebar row. `isAlert` draws it as a filled red capsule (due items).
public struct CountBadge: View {
    public var count: Int
    public var isAlert: Bool
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics

    public init(_ count: Int, isAlert: Bool = false) {
        self.count = count
        self.isAlert = isAlert
    }

    public var body: some View {
        if isAlert {
            Text("\(count)")
                .font(metrics.badge.monospacedDigit())
                .foregroundStyle(palette.onDeadline.color)
                .padding(.horizontal, metrics.scaled(6))
                .padding(.vertical, metrics.scaled(1))
                .background(Capsule().fill(palette.deadline.color))
        } else {
            Text("\(count)")
                .font(metrics.badge.monospacedDigit())
                .foregroundStyle(palette.textTertiary.color)
        }
    }
}
