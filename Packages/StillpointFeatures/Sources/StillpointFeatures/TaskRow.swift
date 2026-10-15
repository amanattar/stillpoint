import StillpointUI
import SwiftUI

/// One read-only row. (Plan 3 adds editing, selection and the expanded card.)
public struct TaskRow: View {
    let row: RowModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics

    public init(row: RowModel) {
        self.row = row
    }

    public var body: some View {
        HStack(alignment: .center, spacing: metrics.rowSpacing) {
            leading
            VStack(alignment: .leading, spacing: metrics.scaled(1)) {
                HStack(spacing: metrics.scaled(5)) {
                    if row.showsTodayMark { ListIcon(.today, size: metrics.scaled(11)) }
                    if row.showsEveningMark { ListIcon(.evening, size: metrics.scaled(11)) }
                    Text(row.title.isEmpty ? "New To-Do" : row.title)
                        .font(metrics.rowTitle)
                        .foregroundStyle(titleColor)
                        .strikethrough(row.isClosed, color: palette.textTertiary.color)
                        .lineLimit(1)
                    if row.hasNotes {
                        Image(systemName: "doc.text")
                            .font(.system(size: metrics.scaled(10)))
                            .foregroundStyle(palette.textTertiary.color)
                            .accessibilityLabel("Has notes")
                    }
                    if let checklist = row.checklist {
                        Label("\(checklist.done)/\(checklist.total)", systemImage: "checklist")
                            .font(metrics.badge)
                            .foregroundStyle(palette.textTertiary.color)
                            .fixedSize()
                    }
                }
                if let detail = row.detail {
                    Text(detail)
                        .font(metrics.rowDetail)
                        .foregroundStyle(palette.textSecondary.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: metrics.rowSpacing)
            ForEach(row.tags, id: \.self) { TagPill($0) }
            if let deadline = row.deadline {
                DeadlineBadge(deadline.text, isDue: deadline.isDue && !row.isClosed)
            }
        }
        .frame(minHeight: row.detail == nil ? metrics.rowHeight : metrics.rowHeightWithDetail)
        .contentShape(Rectangle())
        .opacity(row.isClosed ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var leading: some View {
        switch row.leading {
        case .checkbox(let status):
            CheckboxView(status == .completed ? .completed : status == .canceled ? .canceled : .open)
        case .progress(let value):
            ProgressPie(value)
        }
    }

    private var titleColor: Color {
        row.title.isEmpty ? palette.textTertiary.color : palette.textPrimary.color
    }
}
