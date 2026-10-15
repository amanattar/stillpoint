import StillpointModel
import StillpointUI
import SwiftUI

/// A list's scrolling content: header, sections, rows and the later/logged disclosures.
/// `ListScreen` (in the app) feeds it live data; tests render it with fixed data.
public struct ListBody: View {
    let list: ListID
    let title: String
    let notes: String
    let content: ListContent?
    let dates: DateText
    @Binding var showsLater: Bool
    @Binding var showsLogged: Bool
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics

    public init(
        list: ListID, title: String, notes: String, content: ListContent?, dates: DateText,
        showsLater: Binding<Bool>, showsLogged: Binding<Bool>
    ) {
        self.list = list
        self.title = title
        self.notes = notes
        self.content = content
        self.dates = dates
        _showsLater = showsLater
        _showsLogged = showsLogged
    }

    public var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ListHeader(symbol: list.symbol, title: title, notes: notes)
            if let content {
                if content.sections.isEmpty, content.later.isEmpty, content.logged.isEmpty {
                    EmptyListView(symbol: list.symbol)
                }
                ForEach(content.sections) { section in
                    SectionHeader(section: section, title: dates.sectionTitle(section), dates: dates)
                    ForEach(section.items) { item in
                        TaskRow(row: RowModel(item: item, in: list, content: content, dates: dates))
                    }
                }
                disclosure(content.later, label: "later", isOn: $showsLater, content: content)
                disclosure(content.logged, label: "logged", isOn: $showsLogged, content: content)
            }
        }
    }

    @ViewBuilder
    private func disclosure(_ items: [Item], label: String, isOn: Binding<Bool>, content: ListContent) -> some View {
        if !items.isEmpty {
            Button {
                isOn.wrappedValue.toggle()
            } label: {
                Text(isOn.wrappedValue ? "Hide \(label) items" : "Show \(items.count) \(label) item\(items.count == 1 ? "" : "s")")
                    .font(metrics.badge)
                    .foregroundStyle(palette.textSecondary.color)
            }
            .buttonStyle(.plain)
            .padding(.top, metrics.scaled(16))
            if isOn.wrappedValue {
                ForEach(items) { item in
                    TaskRow(row: RowModel(item: item, in: list, content: content, dates: dates))
                }
            }
        }
    }
}

struct ListHeader: View {
    let symbol: ListSymbol
    let title: String
    let notes: String
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.scaled(6)) {
            HStack(spacing: metrics.scaled(10)) {
                ListIcon(symbol, size: metrics.scaled(22))
                Text(title)
                    .font(metrics.listTitle)
                    .foregroundStyle(palette.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
            }
            if !notes.isEmpty {
                Text(notes)
                    .font(metrics.rowTitle)
                    .foregroundStyle(palette.textSecondary.color)
            }
        }
        .padding(.top, metrics.scaled(28))
        .padding(.bottom, metrics.scaled(14))
    }
}

struct SectionHeader: View {
    let section: ListSection
    let title: String?
    let dates: DateText
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics

    var body: some View {
        if let title {
            VStack(alignment: .leading, spacing: metrics.scaled(4)) {
                HStack(alignment: .firstTextBaseline, spacing: metrics.scaled(8)) {
                    if case .day(let day) = section.kind, dates.showsDayNumber(day) {
                        Text("\(day.day)")
                            .font(.system(size: metrics.scale * 22, weight: .bold))
                            .foregroundStyle(palette.textPrimary.color)
                    }
                    if case .evening = section.kind {
                        ListIcon(.evening, size: metrics.scaled(13))
                    }
                    Text(title)
                        .font(metrics.sectionTitle)
                        .foregroundStyle(section.kind == .evening ? palette.evening.color : palette.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                }
                Rectangle().fill(palette.separator.color).frame(height: 1)
            }
            .padding(.top, metrics.scaled(22))
            .padding(.bottom, metrics.scaled(4))
        }
    }
}

struct EmptyListView: View {
    let symbol: ListSymbol
    @Environment(\.palette) private var palette

    var body: some View {
        ListIcon(symbol, size: 64)
            .opacity(0.18)
            .frame(maxWidth: .infinity)
            .padding(.top, 120)
            .accessibilityLabel("No items")
    }
}

extension Store {
    /// The header title and notes for a list.
    public func header(for list: ListID) async throws -> (String, String) {
        if let title = list.builtInTitle { return (title, "") }
        return try await read { db in
            switch list {
            case .project(let id):
                let project = try Item.fetchOne(db, key: id)
                return (project?.title ?? "", project?.notes ?? "")
            case .area(let id):
                return (try Area.fetchOne(db, key: id)?.title ?? "", "")
            default:
                return ("", "")
            }
        }
    }
}
