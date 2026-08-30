import Foundation
import SwiftData

enum PlaceCategory: String, CaseIterable, Identifiable, Codable {
    case attraction = "景点"
    case restaurant = "餐饮"
    case hotel = "住宿"
    case transport = "交通"
    case other = "其他"
    // Keep the legacy values decodable so existing local data and backups remain readable.
    case shopping = "购物"
    case special = "特殊位置"
    case note = "待办"

    static let allCases: [PlaceCategory] = [
        .attraction,
        .restaurant,
        .hotel,
        .transport,
        .special,
        .other
    ]

    var id: String { rawValue }

    static func resolved(rawValue: String) -> PlaceCategory {
        switch PlaceCategory(rawValue: rawValue) {
        case .shopping, .note:
            .other
        case let category?:
            category
        case nil:
            .attraction
        }
    }

    var symbol: String {
        switch self {
        case .attraction: "camera.fill"
        case .restaurant: "fork.knife"
        case .hotel: "bed.double.fill"
        case .transport: "car.fill"
        case .other: "ellipsis.circle.fill"
        case .shopping: "bag.fill"
        case .special: "mappin.and.ellipse"
        case .note: "checklist"
        }
    }
}

enum TransportMode: String, CaseIterable, Identifiable, Codable {
    case car = "驾车"
    case walk = "步行"
    case ride = "骑行"
    case bus = "公交"
    case train = "火车"
    case flight = "飞机"

    var id: String { rawValue }

    var amapValue: String {
        switch self {
        case .walk: "walk"
        case .ride: "ride"
        case .bus: "bus"
        default: "car"
        }
    }
}

enum MediaKind: String, Codable {
    case image
    case video
}

enum HierarchyDeletionCopy {
    static let confirmationButtonTitle = "确认删除"
    static let cancelButtonTitle = "取消"

    static let tripTitle = "删除行程？"
    static let tripDayTitle = "删除当天？"
    static let itineraryItemTitle = "删除安排？"
    static let storyTitle = "删除足迹？"
    static let storyDayTitle = "删除当天？"
    static let storyEntryTitle = "删除足迹安排？"

    static func tripMessage(title: String) -> String {
        "“\(title)”及其中的当天行程、具体安排和媒体引用将被永久删除。"
    }

    static func tripDayMessage(title: String) -> String {
        "“\(title)”及其中的所有具体安排和媒体引用将被永久删除。"
    }

    static func itineraryItemMessage(title: String) -> String {
        "“\(title)”及其中的媒体引用将被永久删除。"
    }

    static func storyMessage(title: String) -> String {
        "“\(title)”及其中的当天足迹、具体安排和媒体引用将被永久删除，原行程不会受到影响。"
    }

    static func storyDayMessage(title: String) -> String {
        "“\(title)”及其中的所有足迹安排和媒体引用将被永久删除。"
    }

    static func storyEntryMessage(title: String) -> String {
        "“\(title)”及其中的媒体引用将从当前足迹中删除，系统相簿中的原文件不会受到影响。"
    }
}

@Model
final class Trip {
    var id: UUID = UUID()
    var title: String = ""
    var destination: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var note: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \TripDay.trip)
    var days: [TripDay] = []

    init(title: String, destination: String, startDate: Date, endDate: Date, note: String = "") {
        self.title = title
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
    }

    var sortedDays: [TripDay] {
        JourneyHierarchyService.sortedDays(days)
    }

    var allItems: [ItineraryItem] {
        sortedDays.flatMap { $0.sortedItems }
    }

    var nextUnfinishedItem: ItineraryItem? {
        allItems.first { !$0.isCompleted }
    }

    var completedCount: Int { allItems.filter(\.isCompleted).count }
    var totalCount: Int { allItems.count }
    var progress: Double { totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount) }
}

enum TripTimelinePhase: Int {
    case current
    case upcoming
    case history
}

enum TripTimelineOrdering {
    static func phase(
        for trip: Trip,
        relativeTo date: Date = Date(),
        calendar: Calendar = .current
    ) -> TripTimelinePhase {
        let today = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: trip.startDate)
        let end = calendar.startOfDay(for: trip.endDate)

        if start <= today, end >= today { return .current }
        if start > today { return .upcoming }
        return .history
    }

    static func sorted(
        _ trips: [Trip],
        relativeTo date: Date = Date(),
        calendar: Calendar = .current
    ) -> [Trip] {
        trips.sorted { lhs, rhs in
            let lhsPhase = phase(for: lhs, relativeTo: date, calendar: calendar)
            let rhsPhase = phase(for: rhs, relativeTo: date, calendar: calendar)
            if lhsPhase != rhsPhase { return lhsPhase.rawValue < rhsPhase.rawValue }

            let lhsStart = calendar.startOfDay(for: lhs.startDate)
            let rhsStart = calendar.startOfDay(for: rhs.startDate)
            let lhsEnd = calendar.startOfDay(for: lhs.endDate)
            let rhsEnd = calendar.startOfDay(for: rhs.endDate)

            switch lhsPhase {
            case .current:
                if lhsEnd != rhsEnd { return lhsEnd < rhsEnd }
                if lhsStart != rhsStart { return lhsStart > rhsStart }
            case .upcoming:
                if lhsStart != rhsStart { return lhsStart < rhsStart }
                if lhsEnd != rhsEnd { return lhsEnd < rhsEnd }
            case .history:
                if lhsEnd != rhsEnd { return lhsEnd > rhsEnd }
                if lhsStart != rhsStart { return lhsStart > rhsStart }
            }

            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func featured(
        in trips: [Trip],
        relativeTo date: Date = Date(),
        calendar: Calendar = .current
    ) -> Trip? {
        sorted(trips, relativeTo: date, calendar: calendar).first {
            phase(for: $0, relativeTo: date, calendar: calendar) != .history
        }
    }
}

@Model
final class TripDay {
    var id: UUID = UUID()
    var date: Date = Date()
    var title: String = ""
    var note: String = ""
    var sortOrder: Int = 0
    var trip: Trip?

    @Relationship(deleteRule: .cascade, inverse: \ItineraryItem.day)
    var items: [ItineraryItem] = []

    init(date: Date, title: String, sortOrder: Int, trip: Trip? = nil) {
        self.date = date
        self.title = title
        self.sortOrder = sortOrder
        self.trip = trip
    }

    var sortedItems: [ItineraryItem] {
        JourneyHierarchyService.sortedPoints(items)
    }

    var displayItems: [ItineraryItem] {
        sortedItems.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var hasCompletedAllItems: Bool {
        !items.isEmpty && items.allSatisfy(\.isCompleted)
    }

    func isPast(
        relativeTo date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        calendar.startOfDay(for: self.date) < calendar.startOfDay(for: date)
    }

    func shouldAutomaticallyCollapse(
        relativeTo date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        isPast(relativeTo: date, calendar: calendar) || hasCompletedAllItems
    }

    @discardableResult
    func completeElapsedItems(
        relativeTo date: Date = Date()
    ) -> Bool {
        var didChange = false
        for item in items {
            if item.completeIfElapsed(relativeTo: date) {
                didChange = true
            }
        }
        return didChange
    }

    func suggestedStartTime(calendar: Calendar = .current) -> Date {
        if let previousEndTime = sortedItems.last?.endTime {
            return previousEndTime
        }

        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }
}

struct TripCalendarProgress: Equatable {
    let currentDay: Int
    let totalDays: Int
    let phase: TripTimelinePhase

    var fraction: Double {
        Double(currentDay) / Double(max(totalDays, 1))
    }

    var statusText: String {
        switch phase {
        case .current:
            "第 \(currentDay) 天"
        case .upcoming:
            "未出发"
        case .history:
            "已结束"
        }
    }

    static func make(
        for trip: Trip,
        relativeTo date: Date = Date(),
        calendar: Calendar = .current
    ) -> TripCalendarProgress {
        let start = calendar.startOfDay(for: trip.startDate)
        let rawEnd = calendar.startOfDay(for: trip.endDate)
        let end = max(start, rawEnd)
        let today = calendar.startOfDay(for: date)
        let totalDays = max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
        let phase = TripTimelineOrdering.phase(for: trip, relativeTo: date, calendar: calendar)

        let currentDay: Int
        switch phase {
        case .upcoming:
            currentDay = 0
        case .history:
            currentDay = totalDays
        case .current:
            let elapsedDays = calendar.dateComponents([.day], from: start, to: today).day ?? 0
            currentDay = min(max(elapsedDays + 1, 1), totalDays)
        }

        return TripCalendarProgress(currentDay: currentDay, totalDays: totalDays, phase: phase)
    }
}

@Model
final class ItineraryItem {
    var id: UUID = UUID()
    var title: String = ""
    var categoryRaw: String = PlaceCategory.attraction.rawValue
    var startTime: Date = Date()
    var endTime: Date = Date()
    var address: String = ""
    var latitude: Double?
    var longitude: Double?
    var note: String = ""
    var transportRaw: String = TransportMode.car.rawValue
    var distanceText: String = ""
    var playDurationMinutes: Int = 60
    var reservationInfo: String = ""
    var cost: Double = 0
    var isCompleted: Bool = false
    var isAutomaticCompletionOverridden: Bool = false
    var sortOrder: Int = 0
    var day: TripDay?

    @Relationship(deleteRule: .cascade, inverse: \MediaReference.itineraryItem)
    var media: [MediaReference] = []

    init(title: String, category: PlaceCategory, startTime: Date, endTime: Date, sortOrder: Int) {
        self.title = title
        self.categoryRaw = category.rawValue
        self.startTime = startTime
        self.endTime = endTime
        self.sortOrder = sortOrder
    }

    var category: PlaceCategory {
        get { PlaceCategory.resolved(rawValue: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }

    var transport: TransportMode {
        get { TransportMode(rawValue: transportRaw) ?? .car }
        set { transportRaw = newValue.rawValue }
    }

    var hasCoordinate: Bool { latitude != nil && longitude != nil }

    func hasElapsed(relativeTo date: Date = Date()) -> Bool {
        endTime <= date
    }

    @discardableResult
    func completeIfElapsed(relativeTo date: Date = Date()) -> Bool {
        guard hasElapsed(relativeTo: date), !isCompleted, !isAutomaticCompletionOverridden else {
            return false
        }
        isCompleted = true
        return true
    }

    func toggleCompletionManually(relativeTo date: Date = Date()) {
        if isCompleted {
            isCompleted = false
            isAutomaticCompletionOverridden = hasElapsed(relativeTo: date)
        } else {
            isCompleted = true
            isAutomaticCompletionOverridden = false
        }
    }
}

@Model
final class MediaReference {
    var id: UUID = UUID()
    var localIdentifier: String = ""
    var kindRaw: String = MediaKind.image.rawValue
    var caption: String = ""
    var createdAt: Date = Date()
    var sortOrder: Int = 0
    var itineraryItem: ItineraryItem?
    var storyEntry: StoryEntry?

    init(localIdentifier: String, kind: MediaKind, sortOrder: Int = 0) {
        self.localIdentifier = localIdentifier
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
    }

    var kind: MediaKind {
        get { MediaKind(rawValue: kindRaw) ?? .image }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class TravelStory {
    var id: UUID = UUID()
    var title: String = ""
    var destination: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var summary: String = ""
    var createdAt: Date = Date()
    var sourceTripID: UUID?
    var syncScopeRaw: String = StorySyncScope.trip.rawValue
    var sourceSelectionIDsRaw: String = ""

    @Relationship(deleteRule: .cascade, inverse: \StoryEntry.story)
    var entries: [StoryEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \StoryDay.story)
    var days: [StoryDay] = []

    init(title: String, destination: String, startDate: Date, endDate: Date, summary: String) {
        self.title = title
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.summary = summary
    }

    var sortedDays: [StoryDay] {
        JourneyHierarchyService.sortedDays(days)
    }

    var sortedEntries: [StoryEntry] {
        let hierarchical = sortedDays.flatMap(\.sortedEntries)
        let hierarchicalIDs = Set(hierarchical.map(\.id))
        let legacy = entries.filter { !hierarchicalIDs.contains($0.id) }.sorted { $0.sortOrder < $1.sortOrder }
        return hierarchical + legacy
    }

    var syncScope: StorySyncScope {
        get { StorySyncScope(rawValue: syncScopeRaw) ?? .trip }
        set { syncScopeRaw = newValue.rawValue }
    }

    var sourceSelectionIDs: Set<UUID> {
        get { Set(sourceSelectionIDsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }) }
        set { sourceSelectionIDsRaw = newValue.map(\.uuidString).sorted().joined(separator: ",") }
    }

    var allMedia: [MediaReference] {
        sortedEntries.flatMap(\.sortedMedia)
    }
}

enum StorySyncScope: String, Codable {
    case trip
    case day
    case item
}

@Model
final class StoryDay {
    var id: UUID = UUID()
    var date: Date = Date()
    var title: String = ""
    var note: String = ""
    var details: String = ""
    var didMigrateInlineSummary: Bool = false
    var sortOrder: Int = 0
    var sourceDayID: UUID?
    var story: TravelStory?

    @Relationship(deleteRule: .nullify, inverse: \StoryEntry.storyDay)
    var entries: [StoryEntry] = []

    init(date: Date, title: String, sortOrder: Int, sourceDayID: UUID? = nil, story: TravelStory? = nil) {
        self.date = date
        self.title = title
        self.sortOrder = sortOrder
        self.sourceDayID = sourceDayID
        self.story = story
        self.didMigrateInlineSummary = true
    }

    var sortedEntries: [StoryEntry] {
        JourneyHierarchyService.sortedPoints(entries)
    }

    var cardSummary: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@Model
final class StoryEntry {
    var id: UUID = UUID()
    var title: String = ""
    var categoryRaw: String = PlaceCategory.attraction.rawValue
    var timeLabel: String = ""
    var address: String = ""
    var latitude: Double?
    var longitude: Double?
    var note: String = ""
    var routeInfo: String = ""
    var sortOrder: Int = 0
    var sourceItemID: UUID?
    var story: TravelStory?
    var storyDay: StoryDay?

    @Relationship(deleteRule: .cascade, inverse: \MediaReference.storyEntry)
    var media: [MediaReference] = []

    init(title: String, category: PlaceCategory, sortOrder: Int) {
        self.title = title
        self.categoryRaw = category.rawValue
        self.sortOrder = sortOrder
    }

    var category: PlaceCategory {
        get { PlaceCategory.resolved(rawValue: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }

    var sortedMedia: [MediaReference] {
        media.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.createdAt < rhs.createdAt : lhs.sortOrder < rhs.sortOrder
        }
    }
}
