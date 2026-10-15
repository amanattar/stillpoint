import SwiftUI

/// A project's progress: an outlined circle that fills clockwise from the top.
public struct ProgressPie: View {
    public var progress: Double
    public var tint: Color?
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics

    public init(_ progress: Double, tint: Color? = nil) {
        self.progress = min(max(progress, 0), 1)
        self.tint = tint
    }

    public var body: some View {
        let side = metrics.checkbox
        let color = tint ?? palette.inbox.color
        ZStack {
            Circle().strokeBorder(color, lineWidth: max(1.2, side / 10))
            PieSlice(fraction: progress)
                .fill(color)
                .padding(side * 0.18)
        }
        .frame(width: side, height: side)
        .accessibilityElement()
        .accessibilityLabel(Text("\(Int((progress * 100).rounded())) percent complete"))
    }
}

struct PieSlice: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        guard fraction > 0 else { return Path() }
        if fraction >= 1 { return Path(ellipseIn: rect) }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: rect.width / 2,
                    startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
        path.closeSubpath()
        return path
    }
}
