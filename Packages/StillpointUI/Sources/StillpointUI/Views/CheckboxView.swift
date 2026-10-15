import SwiftUI

public enum CheckboxState: Sendable, Hashable {
    case open, completed, canceled
}

/// The to-do checkbox: a rounded square, filled when completed, crossed when canceled.
public struct CheckboxView: View {
    public var state: CheckboxState
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics

    public init(_ state: CheckboxState) {
        self.state = state
    }

    public var body: some View {
        let side = metrics.checkbox
        let shape = RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
        ZStack {
            switch state {
            case .open:
                shape.strokeBorder(palette.checkboxStroke.color, lineWidth: max(1, side / 12))
            case .completed:
                shape.fill(palette.inbox.color)
                Image(systemName: "checkmark")
                    .font(.system(size: side * 0.62, weight: .bold))
                    .foregroundStyle(.white)
            case .canceled:
                shape.fill(palette.textTertiary.color.opacity(0.35))
                Image(systemName: "xmark")
                    .font(.system(size: side * 0.55, weight: .bold))
                    .foregroundStyle(palette.textSecondary.color)
            }
        }
        .frame(width: side, height: side)
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        switch state {
        case .open: "Not completed"
        case .completed: "Completed"
        case .canceled: "Canceled"
        }
    }
}
