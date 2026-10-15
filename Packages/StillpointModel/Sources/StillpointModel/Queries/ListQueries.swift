import Foundation
import GRDB

/// Builds `ListContent` for each list (spec §4.2).
struct ListQueries {
    let db: Database
    let env: ModelEnvironment
    let today: Day
    let settings: Settings
    /// Not tombstoned, not trashed, not logged. Bind `visibleArguments` after it.
    let visible: String
    let visibleArguments: StatementArguments
    let logged: String
    let loggedArguments: StatementArguments

    init(db: Database, env: ModelEnvironment) throws {
        self.db = db
        self.env = env
        let now = env.now()
        today = Day(now, calendar: env.calendar)
        settings = try Store.settings(in: db, now: now)

        let cutoff = settings.manualLogCutoff?.timeIntervalSince1970 ?? -Double.greatestFiniteMagnitude
        let policy: String
        var policyArguments: StatementArguments = []
        switch settings.logPolicy {
        case .immediately:
            policy = "1"
        case .daily:
            policy = "item.stopDate < ?"
            policyArguments = [today.startOfDay(in: env.calendar).timeIntervalSince1970]
        case .manually:
            policy = "0"
        }
        logged = "(item.status != 0 AND item.stopDate IS NOT NULL AND (item.stopDate <= ? OR \(policy)))"
        loggedArguments = [cutoff] + policyArguments
        visible = "(item.deletedAt IS NULL AND item.trashedAt IS NULL AND NOT \(logged))"
        visibleArguments = loggedArguments
    }

    func fetch(_ list: ListID, tagFilter: String?) throws -> ListContent {
        var content: ListContent
        switch list {
        case .inbox: content = try inbox()
        case .today: content = try todayList()
        case .upcoming: content = try upcoming()
        case .anytime: content = try anytime()
        case .someday: content = try someday()
        case .deadlines: content = try deadlines()
        case .logbook: content = try logbook()
        case .trash: content = try trash()
        case .allProjects: content = try projects(later: false)
        case .laterProjects: content = try projects(later: true)
        case .project(let id): content = try project(id)
        case .area(let id): content = try area(id)
        }
        if let tagFilter {
            content = try filter(content, byTag: tagFilter)
        }
        let everything = content.allItems + content.later + content.logged
        content.tagIDsByItem = try tagIDs(for: everything)
        let tagIDs = Set(content.tagIDsByItem.values.joined())
        content.tagTitles = Dictionary(uniqueKeysWithValues: try Tag.fetchAll(db, keys: tagIDs).map { ($0.id, $0.title) })
        content.parentTitles = try parentTitles(for: everything)
        content.checklists = try checklists(for: everything.filter { $0.kind == .todo })
        content.projectProgress = try projectProgress(for: everything.filter { $0.kind == .project }.map(\.id))
        return content
    }

    // MARK: Lists

    private func inbox() throws -> ListContent {
        let items = try select("item.kind = 0 AND item.bucket = 0 AND \(visible)", visibleArguments)
        return single(id: "inbox", items)
    }

    private func todayList() throws -> ListContent {
        let items = try select(
            """
            item.kind IN (0, 1) AND \(visible) AND (
              (item.bucket = 1 AND item.startDay <= ?) OR item.deadlineDay <= ?)
            """,
            visibleArguments + [today, today],
            order: "item.todaySortKey IS NULL, item.todaySortKey, item.startDay, item.sortKey"
        )
        let main = items.filter { !$0.isEvening }
        let evening = items.filter(\.isEvening)
        var sections: [ListSection] = []
        if settings.groupTodayByProject {
            sections += try groupedByParent(main, idPrefix: "today")
        } else if !main.isEmpty {
            sections.append(ListSection(id: "today", kind: .plain, title: nil, items: main))
        }
        if !evening.isEmpty {
            sections.append(ListSection(id: "evening", kind: .evening, title: "This Evening", items: evening))
        }
        return ListContent(sections: sections, later: [], logged: [], tagIDsByItem: [:])
    }

    private func upcoming() throws -> ListContent {
        let items = try select(
            """
            item.kind IN (0, 1) AND \(visible) AND (
              (item.bucket = 1 AND item.startDay > ?) OR item.deadlineDay > ?)
            """,
            visibleArguments + [today, today]
        )
        // Each item appears once: on its start day if that's in the future, else its deadline.
        let dated = items.map { item -> (Day, Item) in
            if let start = item.startDay, start > today { return (start, item) }
            return (item.deadlineDay!, item)
        }.sorted { ($0.0, $0.1.sortKey) < ($1.0, $1.1.sortKey) }

        let calendar = env.calendar
        var sections: [ListSection] = []
        // The next seven days always appear, even when empty.
        for offset in 1...7 {
            let day = today.adding(days: offset, calendar: calendar)
            sections.append(ListSection(id: "day.\(day.rawValue)", kind: .day(day), title: nil, items: dated.filter { $0.0 == day }.map(\.1)))
        }
        let weekEnd = today.adding(days: 7, calendar: calendar)
        let monthEnd = Day(year: weekEnd.year, month: weekEnd.month,
                           day: calendar.range(of: .day, in: .month, for: weekEnd.date(in: calendar))!.count)
        if weekEnd < monthEnd {
            let from = weekEnd.adding(days: 1, calendar: calendar)
            let rest = dated.filter { $0.0 >= from && $0.0 <= monthEnd }.map(\.1)
            sections.append(ListSection(id: "rest.\(from.rawValue)", kind: .restOfMonth(from: from, through: monthEnd), title: nil, items: rest))
        }
        let later = dated.filter { $0.0 > monthEnd }
        var months: [Int: [Item]] = [:]
        var monthOrder: [Int] = []
        for (day, item) in later {
            let key = day.year * 100 + day.month
            if months[key] == nil { monthOrder.append(key) }
            months[key, default: []].append(item)
        }
        for key in monthOrder {
            let first = Day(year: key / 100, month: key % 100, day: 1)
            sections.append(ListSection(id: "month.\(key)", kind: .month(first), title: nil, items: months[key]!))
        }
        return ListContent(sections: sections, later: [], logged: [], tagIDsByItem: [:])
    }

    private func anytime() throws -> ListContent {
        let todos = try select(
            """
            item.kind = 0 AND \(visible) AND item.bucket = 1 AND (item.startDay IS NULL OR item.startDay <= ?)
              AND (item.projectID IS NULL OR EXISTS (
                SELECT 1 FROM item p WHERE p.id = item.projectID AND p.bucket = 1
                  AND (p.startDay IS NULL OR p.startDay <= ?)))
            """,
            visibleArguments + [today, today]
        )
        return ListContent(sections: try groupedByAreaAndProject(todos), later: [], logged: [], tagIDsByItem: [:])
    }

    private func someday() throws -> ListContent {
        let items = try select(
            """
            item.kind IN (0, 1) AND \(visible) AND item.bucket = 2 AND item.startDay IS NULL
              AND (item.projectID IS NULL OR NOT EXISTS (
                SELECT 1 FROM item p WHERE p.id = item.projectID AND p.bucket = 2))
            """,
            visibleArguments
        )
        return ListContent(sections: try groupedByAreaAndProject(items), later: [], logged: [], tagIDsByItem: [:])
    }

    private func deadlines() throws -> ListContent {
        let items = try select(
            "item.kind IN (0, 1) AND \(visible) AND item.status = 0 AND item.deadlineDay IS NOT NULL",
            visibleArguments,
            order: "item.deadlineDay, item.sortKey"
        )
        var sections: [ListSection] = []
        for item in items {
            let day = item.deadlineDay!
            if sections.last?.kind == .day(day) {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(ListSection(id: "deadline.\(day.rawValue)", kind: .day(day), title: nil, items: [item]))
            }
        }
        return ListContent(sections: sections, later: [], logged: [], tagIDsByItem: [:])
    }

    private func logbook() throws -> ListContent {
        let items = try select(
            "item.kind IN (0, 1) AND item.deletedAt IS NULL AND item.trashedAt IS NULL AND \(logged)",
            loggedArguments,
            order: "item.stopDate DESC"
        )
        let loggedProjects = Set(items.filter { $0.kind == .project }.map(\.id))
        var sections: [ListSection] = []
        for item in items where !(item.projectID.map(loggedProjects.contains) ?? false) {
            let day = Day(item.stopDate!, calendar: env.calendar)
            if sections.last?.kind == .day(day) {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(ListSection(id: "logged.\(day.rawValue)", kind: .day(day), title: nil, items: [item]))
            }
        }
        return ListContent(sections: sections, later: [], logged: [], tagIDsByItem: [:])
    }

    private func trash() throws -> ListContent {
        let items = try select(
            """
            item.deletedAt IS NULL AND item.trashedAt IS NOT NULL AND NOT EXISTS (
              SELECT 1 FROM item p WHERE p.id IN (item.projectID, item.headingID) AND p.trashedAt IS NOT NULL)
            """,
            [],
            order: "item.trashedAt DESC, item.sortKey"
        )
        return single(id: "trash", items)
    }

    private func projects(later: Bool) throws -> ListContent {
        let condition = later
            ? "(item.bucket = 2 OR item.startDay > ?)"
            : "item.bucket = 1 AND (item.startDay IS NULL OR item.startDay <= ?)"
        let projects = try select("item.kind = 1 AND \(visible) AND \(condition)", visibleArguments + [today])
        var sections: [ListSection] = []
        let loose = projects.filter { $0.areaID == nil }
        if !loose.isEmpty {
            sections.append(ListSection(id: "projects.none", kind: .plain, title: nil, items: loose))
        }
        for area in try liveAreas() {
            let inArea = projects.filter { $0.areaID == area.id }
            if !inArea.isEmpty {
                sections.append(ListSection(id: "projects.\(area.id)", kind: .area(area.id), title: area.title, items: inArea))
            }
        }
        return ListContent(sections: sections, later: [], logged: [], tagIDsByItem: [:])
    }

    private func project(_ projectID: String) throws -> ListContent {
        let children = try select(
            "item.projectID = ? AND item.deletedAt IS NULL AND item.trashedAt IS NULL",
            [projectID]
        )
        let isLogged = try loggedIDs(children.map(\.id))
        let headings = children.filter { $0.kind == .heading }
        let archivedHeadings = Set(headings.filter { $0.status != .open }.map(\.id))
        let todos = children.filter { $0.kind == .todo }

        var logged: [Item] = []
        var later: [Item] = []
        var current: [Item] = []
        for todo in todos {
            if isLogged.contains(todo.id) || (todo.headingID.map(archivedHeadings.contains) ?? false) {
                logged.append(todo)
            } else if isLater(todo) {
                later.append(todo)
            } else {
                current.append(todo)
            }
        }

        var sections: [ListSection] = []
        let loose = current.filter { $0.headingID == nil }
        if !loose.isEmpty {
            sections.append(ListSection(id: "project.\(projectID)", kind: .plain, title: nil, items: loose))
        }
        for heading in headings where heading.status == .open {
            sections.append(ListSection(id: "heading.\(heading.id)", kind: .heading(heading.id), title: heading.title,
                                        items: current.filter { $0.headingID == heading.id }))
        }
        logged.sort { ($0.stopDate ?? .distantPast) > ($1.stopDate ?? .distantPast) }
        return ListContent(sections: sections, later: later, logged: logged, tagIDsByItem: [:])
    }

    private func area(_ areaID: String) throws -> ListContent {
        let children = try select(
            "item.areaID = ? AND item.projectID IS NULL AND item.kind IN (0, 1) AND item.deletedAt IS NULL AND item.trashedAt IS NULL",
            [areaID]
        )
        let isLogged = try loggedIDs(children.map(\.id))
        var logged: [Item] = []
        var later: [Item] = []
        var current: [Item] = []
        for item in children {
            if isLogged.contains(item.id) {
                logged.append(item)
            } else if isLater(item) {
                later.append(item)
            } else {
                current.append(item)
            }
        }
        var sections: [ListSection] = []
        let todos = current.filter { $0.kind == .todo }
        let projects = current.filter { $0.kind == .project }
        if !todos.isEmpty {
            sections.append(ListSection(id: "area.\(areaID).todos", kind: .plain, title: nil, items: todos))
        }
        if !projects.isEmpty {
            sections.append(ListSection(id: "area.\(areaID).projects", kind: .plain, title: nil, items: projects))
        }
        logged.sort { ($0.stopDate ?? .distantPast) > ($1.stopDate ?? .distantPast) }
        return ListContent(sections: sections, later: later, logged: logged, tagIDsByItem: [:])
    }

    // MARK: Grouping

    /// Loose items first, then each area's loose items and projects, then projects without an area.
    private func groupedByAreaAndProject(_ items: [Item]) throws -> [ListSection] {
        var loose: [Item] = []
        var byArea: [String: [Item]] = [:]
        var byProject: [String: [Item]] = [:]
        for item in items {
            if let projectID = item.projectID {
                byProject[projectID, default: []].append(item)
            } else if let areaID = item.areaID {
                byArea[areaID, default: []].append(item)
            } else {
                loose.append(item)
            }
        }
        let parents = try Item.fetchAll(db, keys: Set(byProject.keys)).sorted { $0.sortKey < $1.sortKey }
        let headingKeys = try headingSortKeys(projectIDs: Set(byProject.keys))

        func projectSections(areaID: String?) -> [ListSection] {
            parents.filter { $0.areaID == areaID }.map { project in
                // Within a project: no-heading items first, then by heading order, then by item order.
                let members = byProject[project.id]!
                    .map { (headingKeys[$0.headingID ?? ""] ?? "", $0) }
                    .sorted { ($0.0, $0.1.sortKey) < ($1.0, $1.1.sortKey) }
                    .map(\.1)
                return ListSection(id: "project.\(project.id)", kind: .project(project.id), title: project.title, items: members)
            }
        }

        var sections: [ListSection] = []
        if !loose.isEmpty {
            sections.append(ListSection(id: "none", kind: .plain, title: nil, items: loose))
        }
        for area in try liveAreas() {
            if let areaItems = byArea[area.id] {
                sections.append(ListSection(id: "area.\(area.id)", kind: .area(area.id), title: area.title, items: areaItems))
            }
            sections += projectSections(areaID: area.id)
        }
        sections += projectSections(areaID: nil)
        return sections
    }

    /// Today's "group by project" option: loose items first, then one section per project or area.
    private func groupedByParent(_ items: [Item], idPrefix: String) throws -> [ListSection] {
        var order: [String] = []
        var groups: [String: [Item]] = [:]
        for item in items {
            let key = item.projectID ?? item.areaID ?? ""
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        order.sort { $0.isEmpty && !$1.isEmpty }
        return try order.map { key in
            if key.isEmpty {
                return ListSection(id: idPrefix, kind: .plain, title: nil, items: groups[key]!)
            }
            if let area = try Area.fetchOne(db, key: key) {
                return ListSection(id: "\(idPrefix).\(key)", kind: .area(key), title: area.title, items: groups[key]!)
            }
            let project = try Item.fetchOne(db, key: key)
            return ListSection(id: "\(idPrefix).\(key)", kind: .project(key), title: project?.title, items: groups[key]!)
        }
    }

    // MARK: Tags

    /// Keeps items tagged with `tagID` or any tag nested under it, directly or
    /// through their project or area.
    private func filter(_ content: ListContent, byTag tagID: String) throws -> ListContent {
        var wanted: Set<String> = [tagID]
        var frontier = [tagID]
        while let current = frontier.popLast() {
            let children = try String.fetchAll(db, sql: "SELECT id FROM tag WHERE parentID = ? AND deletedAt IS NULL", arguments: [current])
            for child in children where wanted.insert(child).inserted {
                frontier.append(child)
            }
        }
        let tagged = Set(try String.fetchAll(
            db,
            sql: "SELECT itemID FROM item_tag WHERE deletedAt IS NULL AND tagID IN (SELECT value FROM json_each(?))",
            arguments: [jsonArray(wanted)]
        ))
        let taggedAreas = Set(try String.fetchAll(
            db,
            sql: "SELECT areaID FROM area_tag WHERE deletedAt IS NULL AND tagID IN (SELECT value FROM json_each(?))",
            arguments: [jsonArray(wanted)]
        ))
        var projectAreas: [String: String] = [:]
        for project in try Item.fetchAll(db, keys: Set((content.allItems + content.later + content.logged).compactMap(\.projectID))) {
            projectAreas[project.id] = project.areaID
        }
        func matches(_ item: Item) -> Bool {
            if tagged.contains(item.id) { return true }
            if let projectID = item.projectID {
                if tagged.contains(projectID) { return true }
                if let areaID = projectAreas[projectID], taggedAreas.contains(areaID) { return true }
            }
            if let areaID = item.areaID, taggedAreas.contains(areaID) { return true }
            return false
        }
        var result = content
        result.sections = content.sections.compactMap { section in
            var section = section
            section.items = section.items.filter(matches)
            // Day sections in Upcoming stay even when empty, like the unfiltered list.
            if case .day = section.kind { return section }
            return section.items.isEmpty ? nil : section
        }
        result.later = content.later.filter(matches)
        result.logged = content.logged.filter(matches)
        return result
    }

    private func tagIDs(for items: [Item]) throws -> [String: [String]] {
        guard !items.isEmpty else { return [:] }
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT item_tag.itemID, item_tag.tagID FROM item_tag JOIN tag ON tag.id = item_tag.tagID
            WHERE item_tag.deletedAt IS NULL AND tag.deletedAt IS NULL
              AND item_tag.itemID IN (SELECT value FROM json_each(?))
            ORDER BY tag.sortKey
            """,
            arguments: [jsonArray(Set(items.map(\.id)))]
        )
        var result: [String: [String]] = [:]
        for row in rows {
            result[row["itemID"], default: []].append(row["tagID"])
        }
        return result
    }

    // MARK: Row details

    private func parentTitles(for items: [Item]) throws -> [String: String] {
        let projectIDs = Set(items.compactMap(\.projectID))
        let areaIDs = Set(items.compactMap(\.areaID))
        var titles: [String: String] = [:]
        for project in try Item.fetchAll(db, keys: projectIDs) { titles[project.id] = project.title }
        for area in try Area.fetchAll(db, keys: areaIDs) { titles[area.id] = area.title }
        var result: [String: String] = [:]
        for item in items {
            if let parent = (item.projectID ?? item.areaID).flatMap({ titles[$0] }) {
                result[item.id] = parent
            }
        }
        return result
    }

    private func checklists(for todos: [Item]) throws -> [String: ChecklistProgress] {
        guard !todos.isEmpty else { return [:] }
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT itemID, COUNT(*) AS total, SUM(isDone) AS done FROM checklist_item
            WHERE deletedAt IS NULL AND itemID IN (SELECT value FROM json_each(?))
            GROUP BY itemID
            """,
            arguments: [jsonArray(Set(todos.map(\.id)))]
        )
        var result: [String: ChecklistProgress] = [:]
        for row in rows {
            result[row["itemID"]] = ChecklistProgress(done: row["done"], total: row["total"])
        }
        return result
    }

    // MARK: Helpers

    private func select(_ condition: String, _ arguments: StatementArguments, order: String = "item.sortKey") throws -> [Item] {
        try Item.fetchAll(db, sql: "SELECT item.* FROM item WHERE \(condition) ORDER BY \(order)", arguments: arguments)
    }

    private func single(id: String, _ items: [Item]) -> ListContent {
        ListContent(sections: items.isEmpty ? [] : [ListSection(id: id, kind: .plain, title: nil, items: items)],
                    later: [], logged: [], tagIDsByItem: [:])
    }

    private func isLater(_ item: Item) -> Bool {
        item.bucket == .someday || (item.startDay.map { $0 > today } ?? false)
    }

    private func loggedIDs(_ ids: [String]) throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        return Set(try String.fetchAll(
            db,
            sql: "SELECT item.id FROM item WHERE item.id IN (SELECT value FROM json_each(?)) AND \(logged)",
            arguments: [jsonArray(Set(ids))] + loggedArguments
        ))
    }

    private func liveAreas() throws -> [Area] {
        try Area.filter(Column("deletedAt") == nil).order(Column("sortKey")).fetchAll(db)
    }

    private func headingSortKeys(projectIDs: Set<String>) throws -> [String: String] {
        guard !projectIDs.isEmpty else { return [:] }
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT id, sortKey FROM item WHERE kind = 2 AND projectID IN (SELECT value FROM json_each(?))",
            arguments: [jsonArray(projectIDs)]
        )
        return Dictionary(uniqueKeysWithValues: rows.map { ($0["id"], $0["sortKey"]) })
    }

    private func jsonArray(_ ids: Set<String>) -> String {
        String(decoding: try! JSONEncoder().encode(ids.sorted()), as: UTF8.self)
    }
}

extension Store {
    /// One-shot fetch of a list.
    public func fetch(_ list: ListID, tagFilter: String? = nil) async throws -> ListContent {
        let env = self.env
        return try await read { db in try ListQueries(db: db, env: env).fetch(list, tagFilter: tagFilter) }
    }

    /// Live updates for a list: emits whenever any table it reads changes.
    /// The app re-subscribes at midnight so "today" moves forward.
    public func observe(_ list: ListID, tagFilter: String? = nil) -> AsyncValueObservation<ListContent> {
        let env = self.env
        return ValueObservation
            .tracking { db in try ListQueries(db: db, env: env).fetch(list, tagFilter: tagFilter) }
            .removeDuplicates()
            .values(in: writer)
    }
}
