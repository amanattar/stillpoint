import StillpointModel

/// Everything one row displays, derived from the item and its list.
public struct RowModel: Identifiable, Equatable {
    public enum Leading: Equatable {
        case checkbox(ItemStatus)
        case progress(Double)
    }

    public var id: String
    public var title: String
    public var leading: Leading
    /// Project or area name, hidden when the row is already inside that project or area.
    public var detail: String?
    /// Amber sun: a to-do that's in Today, shown in lists other than Today.
    public var showsTodayMark: Bool
    /// Indigo moon: scheduled for this evening, shown in lists other than Today.
    public var showsEveningMark: Bool
    public var hasNotes: Bool
    public var checklist: ChecklistProgress?
    public var tags: [String]
    public var deadline: (text: String, isDue: Bool)?
    public var isClosed: Bool

    public static func == (lhs: RowModel, rhs: RowModel) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.leading == rhs.leading && lhs.detail == rhs.detail
            && lhs.showsTodayMark == rhs.showsTodayMark && lhs.showsEveningMark == rhs.showsEveningMark
            && lhs.hasNotes == rhs.hasNotes && lhs.checklist == rhs.checklist && lhs.tags == rhs.tags
            && lhs.deadline?.text == rhs.deadline?.text && lhs.deadline?.isDue == rhs.deadline?.isDue
            && lhs.isClosed == rhs.isClosed
    }

    public init(item: Item, in list: ListID, content: ListContent, dates: DateText) {
        id = item.id
        title = item.title
        leading = item.kind == .project ? .progress(content.projectProgress[item.id] ?? 0) : .checkbox(item.status)

        let parentID = item.projectID ?? item.areaID
        let insideParent: Bool = switch list {
        case .project(let id), .area(let id): parentID == id
        default: false
        }
        detail = insideParent ? nil : content.parentTitles[item.id]

        let isInToday = item.bucket == .anytime && (item.startDay.map { $0 <= dates.today } ?? false)
        showsEveningMark = list != .today && isInToday && item.isEvening
        showsTodayMark = list != .today && isInToday && !item.isEvening
        hasNotes = !item.notes.isEmpty
        checklist = content.checklists[item.id]
        tags = (content.tagIDsByItem[item.id] ?? []).compactMap { content.tagTitles[$0] }
        deadline = item.deadlineDay.map { dates.deadline($0) }
        isClosed = item.status != .open
    }
}
