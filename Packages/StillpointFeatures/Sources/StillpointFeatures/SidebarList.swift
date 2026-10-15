import StillpointModel
import StillpointUI
import SwiftUI

/// The sidebar's list: fixed lists, loose projects, then areas with their projects.
/// `SidebarView` (in the app) feeds it live data; tests render it with fixed data.
public struct SidebarList: View {
    let content: SidebarContent?
    @Binding var selection: ListID?
    @Environment(\.metrics) private var metrics

    public init(content: SidebarContent?, selection: Binding<ListID?>) {
        self.content = content
        _selection = selection
    }

    public var body: some View {
        List(selection: $selection) {
            Section {
                row(.inbox, count: content?.inboxCount ?? 0)
            }
            Section {
                row(.today, count: content?.todayCount ?? 0, alert: content?.dueCount ?? 0)
                row(.upcoming)
                row(.anytime)
                row(.someday)
            }
            Section {
                row(.logbook)
                row(.trash)
            }
            if let content {
                if !content.looseProjects.isEmpty {
                    Section {
                        ForEach(content.looseProjects) { project in
                            projectRow(project)
                        }
                    }
                }
                ForEach(content.areas) { area in
                    Section {
                        SidebarLabel(title: area.area.title, font: metrics.sidebarArea) { ListIcon(.area) }
                            .tag(ListID.area(area.area.id))
                        if !area.area.isCollapsed {
                            ForEach(area.projects) { project in
                                projectRow(project)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Lists")
    }

    private func row(_ list: ListID, count: Int = 0, alert: Int = 0) -> some View {
        SidebarLabel(title: list.builtInTitle ?? "", font: metrics.sidebarItem, count: count, alert: alert) {
            ListIcon(list.symbol)
        }
        .tag(list)
    }

    private func projectRow(_ project: SidebarProject) -> some View {
        SidebarLabel(title: project.item.title.isEmpty ? "New Project" : project.item.title, font: metrics.sidebarItem) {
            ProgressPie(project.progress)
        }
        .tag(ListID.project(project.item.id))
    }
}

struct SidebarLabel<Icon: View>: View {
    let title: String
    let font: Font
    var count = 0
    var alert = 0
    @ViewBuilder let icon: () -> Icon
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.scaled(8)) {
            icon().frame(width: metrics.sidebarIcon + 2)
            Text(title).font(font).lineLimit(1)
            Spacer(minLength: 4)
            if alert > 0 { CountBadge(alert, isAlert: true) }
            if count > 0 { CountBadge(count) }
        }
        .frame(minHeight: metrics.sidebarRowHeight)
        .accessibilityElement(children: .combine)
    }
}
