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

enum ArrangementLocationMode: String, CaseIterable, Identifiable, Codable {
    case single = "单地点"
    case route = "起终点"

    var id: String { rawValue }
}

enum ItineraryExecutionStatus: String, CaseIterable, Identifiable, Codable {
    case notStarted = "未开始"
    case inProgress = "进行中"
    case completed = "已完成"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .notStarted: "clock"
        case .inProgress: "play.circle.fill"
        case .completed: "checkmark.circle.fill"
        }
    }
}

enum JourneyLocationRole: String, Codable {
    case place
    case origin
    case destination

    var displayName: String {
        switch self {
        case .place: "地点"
        case .origin: "出发地"
        case .destination: "目的地"
        }
    }
}

enum JourneyLocationText {
    static func entityName(
        from rawValue: String,
        arrangementTitle: String = "",
        role: JourneyLocationRole = .place
    ) -> String {
        let original = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return "" }
        var value = original

        if value.hasPrefix("在"), value.hasSuffix("用餐"), value.count > 4 {
            value.removeFirst()
            value.removeLast(2)
        } else {
            let prefixes = ["集合于", "游览", "参观", "打卡", "入住", "前往", "抵达", "到达"]
            if let prefix = prefixes.first(where: { value.hasPrefix($0) && value.count > $0.count + 1 }) {
                value.removeFirst(prefix.count)
            }
        }

        // Legacy arrangements sometimes stored a sentence such as
        // "高铁抵达杭州东站" as the location. Keep the arrangement copy intact,
        // but extract only the entity after the last directional verb for map use.
        for marker in ["前往", "抵达", "到达", "去往"] {
            if let range = value.range(of: marker, options: .backwards) {
                let suffix = String(value[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if suffix.count >= 2 {
                    value = suffix
                    break
                }
            }
        }

        switch role {
        case .origin:
            value = removingSuffix("出发", from: value)
        case .destination:
            for suffix in ["到达", "抵达"] {
                value = removingSuffix(suffix, from: value)
            }
        case .place:
            for suffix in ["夜景", "集合", "晨光", "日落"] {
                value = removingSuffix(suffix, from: value)
            }
        }

        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count >= 2 ? cleaned : original
    }

    private static func removingSuffix(_ suffix: String, from value: String) -> String {
        guard value.hasSuffix(suffix), value.count > suffix.count + 1 else { return value }
        return String(value.dropLast(suffix.count))
    }
}

struct JourneyLocationTarget: Identifiable, Equatable {
    var id: String { role.rawValue }
    let role: JourneyLocationRole
    let name: String
    let address: String

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty
            ? address.trimmingCharacters(in: .whitespacesAndNewlines)
            : trimmedName
    }

    var isEmpty: Bool { displayName.isEmpty }
}

struct ItineraryRoutePoint: Identifiable, Equatable {
    var id: String { "\(itemID.uuidString)-\(target.role.rawValue)" }
    let itemID: UUID
    let dayID: UUID
    let arrangementTitle: String
    let startTime: Date
    let endTime: Date
    let target: JourneyLocationTarget
}

enum ItineraryRoutePlanning {
    static func points(in days: [TripDay]) -> [ItineraryRoutePoint] {
        let orderedDays = JourneyHierarchyService.sortedDays(days)
        let rawPoints = orderedDays.flatMap { day in
            day.items
                .sorted { lhs, rhs in
                    if lhs.startTime != rhs.startTime { return lhs.startTime < rhs.startTime }
                    if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .flatMap { item in
                    item.locationTargets.map { target in
                        ItineraryRoutePoint(
                            itemID: item.id,
                            dayID: day.id,
                            arrangementTitle: item.title,
                            startTime: item.startTime,
                            endTime: item.endTime,
                            target: target
                        )
                    }
                }
        }

        var result: [ItineraryRoutePoint] = []
        for point in rawPoints {
            if let previous = result.last,
               normalizedLocation(previous.target) == normalizedLocation(point.target) {
                continue
            }
            result.append(point)
        }
        return result
    }

    private static func normalizedLocation(_ target: JourneyLocationTarget) -> String {
        target.displayName
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}

enum MediaKind: String, Codable {
    case image
    case video
}

enum HierarchyDeletionCopy {
    static let confirmationButtonTitle = "确认删除"
    static let cancelButtonTitle = "取消"

    static let tripTitle = "删除旅程？"
    static let tripDayTitle = "删除当天？"
    static let itineraryItemTitle = "删除安排？"
    static let storyTitle = "删除足迹？"
    static let storyDayTitle = "删除当天？"
    static let storyEntryTitle = "删除这条记录？"

    static func tripMessage(title: String) -> String {
        "“\(title)”及其中的每日安排和媒体引用将被永久删除。"
    }

    static func tripDayMessage(title: String) -> String {
        "“\(title)”及其中的所有具体安排和媒体引用将被永久删除。"
    }

    static func itineraryItemMessage(title: String) -> String {
        "“\(title)”及其中的媒体引用将被永久删除。"
    }

    static func storyMessage(title: String) -> String {
        "“\(title)”及其中的每日记录、回忆和媒体引用将被永久删除，原旅程不会受到影响。"
    }

    static func storyDayMessage(title: String) -> String {
        "“\(title)”及其中的所有记录和媒体引用将被永久删除。"
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
        allItems.first { $0.executionStatus != .completed }
    }

    var completedCount: Int { allItems.filter { $0.executionStatus == .completed }.count }
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
        JourneyHierarchyService.sortedItems(items)
    }

    var displayItems: [ItineraryItem] {
        items.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.startTime < rhs.startTime : lhs.sortOrder < rhs.sortOrder
        }
    }

    var hasCompletedAllItems: Bool {
        !items.isEmpty && items.allSatisfy { $0.executionStatus == .completed }
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
    var note: String = ""
    var locationModeRaw: String = ""
    var placeName: String = ""
    var placeAddress: String = ""
    var originName: String = ""
    var originAddress: String = ""
    var destinationName: String = ""
    var destinationAddress: String = ""
    var transportRaw: String = TransportMode.car.rawValue
    var distanceText: String = ""
    var playDurationMinutes: Int = 60
    var reservationInfo: String = ""
    var cost: Double = 0
    var isCompleted: Bool = false
    var executionStatusRaw: String = ""
    var isAutomaticCompletionOverridden: Bool = false
    var isFixedTime: Bool = false
    var sortOrder: Int = 0
    var isFavorite: Bool = false
    var favoriteCreatedAt: Date = Date()
    var sourceFavoriteID: UUID?
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

    var locationMode: ArrangementLocationMode {
        get {
            ArrangementLocationMode(rawValue: locationModeRaw)
                ?? ((originName.isEmpty && destinationName.isEmpty) ? .single : .route)
        }
        set { locationModeRaw = newValue.rawValue }
    }

    var executionStatus: ItineraryExecutionStatus {
        get {
            ItineraryExecutionStatus(rawValue: executionStatusRaw)
                ?? (isCompleted ? .completed : .notStarted)
        }
        set {
            executionStatusRaw = newValue.rawValue
            isCompleted = newValue == .completed
        }
    }

    var locationTargets: [JourneyLocationTarget] {
        switch locationMode {
        case .single:
            let fallbackName = placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? JourneyLocationText.entityName(from: title, arrangementTitle: title)
                : JourneyLocationText.entityName(from: placeName, arrangementTitle: title)
            let fallbackAddress = placeAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? address
                : placeAddress
            let target = JourneyLocationTarget(
                role: .place,
                name: fallbackName,
                address: fallbackAddress
            )
            return target.isEmpty ? [] : [target]
        case .route:
            return [
                JourneyLocationTarget(
                    role: .origin,
                    name: JourneyLocationText.entityName(from: originName, arrangementTitle: title, role: .origin),
                    address: originAddress
                ),
                JourneyLocationTarget(
                    role: .destination,
                    name: JourneyLocationText.entityName(from: destinationName, arrangementTitle: title, role: .destination),
                    address: destinationAddress
                )
            ].filter { !$0.isEmpty }
        }
    }

    var primaryNavigationTarget: JourneyLocationTarget? {
        switch locationMode {
        case .single:
            locationTargets.first
        case .route:
            locationTargets.first(where: { $0.role == .destination }) ?? locationTargets.first
        }
    }

    var nextNavigationTarget: JourneyLocationTarget? {
        switch locationMode {
        case .single:
            locationTargets.first
        case .route:
            locationTargets.first(where: { $0.role == .origin }) ?? locationTargets.first
        }
    }

    var locationSummary: String {
        switch locationMode {
        case .single:
            return locationTargets.first?.displayName ?? ""
        case .route:
            return locationTargets.map(\.displayName).joined(separator: " → ")
        }
    }

    func hasElapsed(relativeTo date: Date = Date()) -> Bool {
        endTime <= date
    }

    @discardableResult
    func completeIfElapsed(relativeTo date: Date = Date()) -> Bool {
        let hadLegacyOverride = isAutomaticCompletionOverridden
        isAutomaticCompletionOverridden = false

        let expectedStatus: ItineraryExecutionStatus
        if hasElapsed(relativeTo: date) {
            expectedStatus = .completed
        } else if startTime <= date {
            expectedStatus = .inProgress
        } else {
            expectedStatus = .notStarted
        }

        guard executionStatus != expectedStatus else { return hadLegacyOverride }
        executionStatus = expectedStatus
        return true
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
    var storyCover: TravelStory?

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
    var coverZoom: Double = 1
    var coverOffsetX: Double = 0
    var coverOffsetY: Double = 0

    @Relationship(deleteRule: .cascade, inverse: \MediaReference.storyCover)
    var coverMedia: MediaReference?

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
    var startTime: Date?
    var endTime: Date?
    var timeLabel: String = ""
    var address: String = ""
    var supplementalInfo: String = ""
    var note: String = ""
    var locationModeRaw: String = ""
    var placeName: String = ""
    var placeAddress: String = ""
    var originName: String = ""
    var originAddress: String = ""
    var destinationName: String = ""
    var destinationAddress: String = ""
    var transportRaw: String = TransportMode.car.rawValue
    var routeInfo: String = ""
    var cost: Double = 0
    var didPrefillSourceMemory: Bool = false
    var sourceMemoryPrefill: String?
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

    var transport: TransportMode {
        get { TransportMode(rawValue: transportRaw) ?? .car }
        set { transportRaw = newValue.rawValue }
    }

    var locationMode: ArrangementLocationMode {
        get {
            ArrangementLocationMode(rawValue: locationModeRaw)
                ?? ((originName.isEmpty && destinationName.isEmpty) ? .single : .route)
        }
        set { locationModeRaw = newValue.rawValue }
    }

    var locationTargets: [JourneyLocationTarget] {
        switch locationMode {
        case .single:
            let fallbackName = placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? JourneyLocationText.entityName(from: title, arrangementTitle: title)
                : JourneyLocationText.entityName(from: placeName, arrangementTitle: title)
            let fallbackAddress = placeAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? address
                : placeAddress
            let target = JourneyLocationTarget(role: .place, name: fallbackName, address: fallbackAddress)
            return target.isEmpty ? [] : [target]
        case .route:
            return [
                JourneyLocationTarget(
                    role: .origin,
                    name: JourneyLocationText.entityName(from: originName, arrangementTitle: title, role: .origin),
                    address: originAddress
                ),
                JourneyLocationTarget(
                    role: .destination,
                    name: JourneyLocationText.entityName(from: destinationName, arrangementTitle: title, role: .destination),
                    address: destinationAddress
                )
            ].filter { !$0.isEmpty }
        }
    }

    var primaryNavigationTarget: JourneyLocationTarget? {
        switch locationMode {
        case .single:
            locationTargets.first
        case .route:
            locationTargets.first(where: { $0.role == .destination }) ?? locationTargets.first
        }
    }

    var distanceText: String {
        get { routeInfo }
        set { routeInfo = newValue }
    }

    var sortedMedia: [MediaReference] {
        media.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.createdAt < rhs.createdAt : lhs.sortOrder < rhs.sortOrder
        }
    }
}
