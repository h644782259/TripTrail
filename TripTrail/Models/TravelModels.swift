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
        .other
    ]

    var id: String { rawValue }

    static func resolved(rawValue: String) -> PlaceCategory {
        switch PlaceCategory(rawValue: rawValue) {
        case .shopping, .special, .note:
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

enum AttractionType: String, CaseIterable, Identifiable, Codable {
    case automatic = "unknown", mountain, water, park, museum, heritage, temple, themePark = "theme_park", viewpoint, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: "自动识别"
        case .mountain: "山岳"
        case .water: "湖泊海滨"
        case .park: "公园"
        case .museum: "博物馆"
        case .heritage: "古迹古镇"
        case .temple: "寺庙宗教"
        case .themePark: "主题乐园"
        case .viewpoint: "观景点"
        case .other: "其他景点"
        }
    }
    var symbol: String {
        switch self {
        case .mountain: "mountain.2.fill"
        case .water: "water.waves"
        case .park: "tree.fill"
        case .museum: "building.columns.fill"
        case .heritage: "building.2.fill"
        case .temple: "building.columns"
        case .themePark: "ferriswheel"
        case .viewpoint: "binoculars.fill"
        default: "camera.fill"
        }
    }
    func resolved(_ title: String, _ note: String) -> AttractionType {
        guard self == .automatic else { return self }
        for text in [title, note] {
            for (words, type): ([String], AttractionType) in [
                (["博物馆", "美术馆", "展览馆", "纪念馆"], .museum),
                (["寺", "教堂", "清真寺", "道观"], .temple),
                (["乐园", "游乐场", "迪士尼", "环球影城"], .themePark),
                (["古镇", "古城", "遗址", "故宫", "长城"], .heritage),
                (["观景台", "观景点"], .viewpoint), (["公园", "植物园"], .park),
                (["湖", "海滩", "海滨", "沙滩", "瀑布"], .water), (["山", "峰", "峡谷"], .mountain)
            ] { if words.contains(where: text.contains) { return type } }
        }
        return .other
    }
}

enum TransportMode: String, CaseIterable, Identifiable, Codable {
    case car = "驾车"
    case walk = "步行"
    case ride = "骑行"
    case bus = "公交"
    case train = "火车"
    case flight = "飞机"
    case driving = "自驾"
    case highSpeedRail = "高铁"
    case taxi = "打车"
    case subway = "地铁"
    case ferry = "轮船"

    var id: String { rawValue }

    // The legacy car value was assigned to every arrangement, so treat it as automatic.
    var displayName: String { self == .car ? "自动识别" : self == .driving ? "驾车" : rawValue }
    var symbol: String {
        switch self {
        case .car: "arrow.left.arrow.right"
        case .driving: "car.fill"
        case .walk: "figure.walk"
        case .ride: "bicycle"
        case .bus: "bus.fill"
        case .train, .highSpeedRail: "tram.fill"
        case .flight: "airplane"
        case .taxi: "car.side.fill"
        case .subway: "tram.tunnel.fill"
        case .ferry: "ferry.fill"
        }
    }
    static func recognized(_ value: String?) -> TransportMode {
        let value = value?.lowercased() ?? ""
        switch value {
        case "flight", "plane", "飞机": return .flight
        case "high_speed_rail", "高铁", "动车": return .highSpeedRail
        case "train", "火车": return .train
        case "car", "driving", "驾车", "自驾": return .driving
        case "taxi", "打车": return .taxi
        case "subway", "metro", "地铁": return .subway
        case "bus", "公交", "大巴": return .bus
        case "ferry", "船", "轮船": return .ferry
        case "bicycle", "ride", "骑行": return .ride
        case "walk", "步行": return .walk
        default: return .car
        }
    }
    func resolved(title: String, note: String) -> TransportMode {
        guard self == .car else { return self }
        for text in [title, note] {
            for (words, mode): ([String], TransportMode) in [
                (["取车", "还车", "租车", "自驾", "驾车", "开车", "接机", "送机"], .driving),
                (["打车", "出租车", "网约车"], .taxi), (["地铁"], .subway),
                (["航班", "起飞", "飞机", "登机", "航空"], .flight),
                (["高铁", "动车"], .highSpeedRail), (["火车", "列车", "车次"], .train),
                (["公交", "大巴", "巴士"], .bus), (["轮船", "渡轮", "轮渡", "乘船"], .ferry),
                (["骑行", "自行车"], .ride), (["步行", "徒步"], .walk)
            ] { if words.contains(where: text.contains) { return mode } }
        }
        return .car
    }

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
    var isTimePending: Bool = false
    var isCompleted: Bool = false
}

enum ItineraryRoutePlanning {
    static func points(in days: [TripDay]) -> [ItineraryRoutePoint] {
        let orderedDays = JourneyHierarchyService.sortedDays(days)
        let rawPoints = orderedDays.flatMap { day in
            day.sortedItems
                .flatMap { item in
                    item.locationTargets.map { target in
                        ItineraryRoutePoint(
                            itemID: item.id,
                            dayID: day.id,
                            arrangementTitle: item.title,
                            startTime: item.startTime,
                            endTime: item.endTime,
                            target: target,
                            isTimePending: item.isTimePending,
                            isCompleted: item.executionStatus == .completed
                        )
                    }
                }
        }

        return removingAdjacentDuplicates(rawPoints)
    }

    static func removingAdjacentDuplicates(_ points: [ItineraryRoutePoint]) -> [ItineraryRoutePoint] {
        var result: [ItineraryRoutePoint] = []
        for point in points {
            if let previous = result.last,
               normalizedLocation(previous.target) == normalizedLocation(point.target) {
                continue
            }
            result.append(point)
        }
        return result
    }

    private static func normalizedLocation(_ target: JourneyLocationTarget) -> String {
        [target.displayName, target.address].map {
            $0.components(separatedBy: .whitespacesAndNewlines).joined().lowercased()
        }.joined(separator: "\u{0}")
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
        "“\(title)”将移入回收站，24 小时内可恢复。云端项目会同步从其他设备移除。"
    }

    static func tripDayMessage(title: String) -> String {
        "“\(title)”及其中的所有具体安排和媒体引用将被永久删除。"
    }

    static func itineraryItemMessage(title: String) -> String {
        "“\(title)”及其中的媒体引用将被永久删除。"
    }

    static func storyMessage(title: String) -> String {
        "“\(title)”将移入回收站，24 小时内可恢复。云端项目会同步从其他设备移除，原旅程不受影响。"
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
    var journalSummary: String = ""
    var coverZoom: Double = 1
    var coverOffsetX: Double = 0
    var coverOffsetY: Double = 0
    @Relationship(deleteRule: .cascade, inverse: \MediaReference.tripCover)
    var coverMedia: MediaReference?

    var licensePlate: String = ""
    var licensePlateDisplay: String { licensePlate.formattedLicensePlate }

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
        allItems.first { !$0.isTimePending && $0.executionStatus != .completed }
            ?? allItems.first { $0.executionStatus != .completed }
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
    var journalNote: String = ""
    var journalDetails: String = ""

    var id: UUID = UUID()
    var date: Date = Date()
    var title: String = ""
    var note: String = ""
    var city: String = ""
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
        if let previousEndTime = sortedItems.filter({ !$0.isTimePending }).map(\.endTime).max() {
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
    var journalNote: String = ""
    var journalSupplement: String = ""

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
    // Retained for SwiftData compatibility with existing stores; no longer a user-facing field.
    var attractionTypeRaw: String = "unknown"
    var transportRaw: String = TransportMode.car.rawValue
    var distanceText: String = ""
    var playDurationMinutes: Int = 60
    var reservationInfo: String = ""
    var cost: Double = 0
    var isCompleted: Bool = false
    var executionStatusRaw: String = ""
    var isAutomaticCompletionOverridden: Bool = false
    var isFixedTime: Bool = false
    var isTimePending: Bool = false
    @Attribute(.externalStorage) var voucherData: Data? = nil
    var sortOrder: Int = 0
    var isFavorite: Bool = false
    var favoriteCity: String = ""
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

    var arrangementSymbol: String {
        category == .transport ? transport.resolved(title: title, note: note).symbol : category == .attraction ? (AttractionType(rawValue: attractionTypeRaw) ?? .automatic).resolved(title, note).symbol : category.symbol
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
            let fallbackName = JourneyLocationText.entityName(from: placeName, arrangementTitle: title)
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

    var vouchers: [TravelVoucher] {
        get { voucherData.flatMap { try? JSONDecoder().decode([TravelVoucher].self, from: $0) } ?? [] }
        set { voucherData = try? JSONEncoder().encode(newValue) }
    }

    var timeRangeText: String { isTimePending ? "时间待定" : "\(startTime.timeText)–\(endTime.timeText)" }

    func hasElapsed(relativeTo date: Date = Date()) -> Bool {
        !isTimePending && endTime <= date
    }

    @discardableResult
    func completeIfElapsed(relativeTo date: Date = Date()) -> Bool {
        guard !isTimePending else { return false }
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
    static func precedes(_ lhs: MediaReference, _ rhs: MediaReference) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
    var id: UUID = UUID()
    var localIdentifier: String = ""
    var kindRaw: String = MediaKind.image.rawValue
    var caption: String = ""
    var createdAt: Date = Date()
    var sortOrder: Int = 0
    var itineraryItem: ItineraryItem?
    var storyEntry: StoryEntry?
    var storyCover: TravelStory?
    var tripCover: Trip?

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
    var journey: Trip?
    var usesUnifiedJourney: Bool = false
    var id: UUID = UUID()
    @Attribute(originalName: "title")
    var legacyTitle: String = ""
    var title: String {
        get { journey?.title ?? legacyTitle }
        set { if let journey { journey.title = newValue } else { legacyTitle = newValue } }
    }
    @Attribute(originalName: "destination")
    var legacyDestination: String = ""
    var destination: String {
        get { journey?.destination ?? legacyDestination }
        set { if let journey { journey.destination = newValue } else { legacyDestination = newValue } }
    }
    @Attribute(originalName: "startDate")
    var legacyStartDate: Date = Date()
    var startDate: Date {
        get { journey?.startDate ?? legacyStartDate }
        set { if let journey { journey.startDate = newValue } else { legacyStartDate = newValue } }
    }
    @Attribute(originalName: "endDate")
    var legacyEndDate: Date = Date()
    var endDate: Date {
        get { journey?.endDate ?? legacyEndDate }
        set { if let journey { journey.endDate = newValue } else { legacyEndDate = newValue } }
    }
    @Attribute(originalName: "summary")
    var legacySummary: String = ""
    var summary: String {
        get { journey?.journalSummary ?? legacySummary }
        set { if let journey { journey.journalSummary = newValue } else { legacySummary = newValue } }
    }
    @Attribute(originalName: "createdAt")
    var legacyCreatedAt: Date = Date()
    var createdAt: Date {
        get { journey?.createdAt ?? legacyCreatedAt }
        set { if let journey { journey.createdAt = newValue } else { legacyCreatedAt = newValue } }
    }
    var sourceTripID: UUID?
    var syncScopeRaw: String = StorySyncScope.trip.rawValue
    var sourceSelectionIDsRaw: String = ""
    @Attribute(originalName: "coverZoom")
    var legacyCoverZoom: Double = 1
    var coverZoom: Double {
        get { journey?.coverZoom ?? legacyCoverZoom }
        set { if let journey { journey.coverZoom = newValue } else { legacyCoverZoom = newValue } }
    }
    @Attribute(originalName: "coverOffsetX")
    var legacyCoverOffsetX: Double = 0
    var coverOffsetX: Double {
        get { journey?.coverOffsetX ?? legacyCoverOffsetX }
        set { if let journey { journey.coverOffsetX = newValue } else { legacyCoverOffsetX = newValue } }
    }
    @Attribute(originalName: "coverOffsetY")
    var legacyCoverOffsetY: Double = 0
    var coverOffsetY: Double {
        get { journey?.coverOffsetY ?? legacyCoverOffsetY }
        set { if let journey { journey.coverOffsetY = newValue } else { legacyCoverOffsetY = newValue } }
    }

    @Relationship(deleteRule: .nullify, originalName: "coverMedia", inverse: \MediaReference.storyCover)
    var legacyCoverMedia: MediaReference?
    var coverMedia: MediaReference? {
        get { journey != nil ? journey!.coverMedia : legacyCoverMedia }
        set { if let journey { journey.coverMedia = newValue } else { legacyCoverMedia = newValue } }
    }

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
    var journeyDay: TripDay?
    var usesUnifiedJourney: Bool = false
    var id: UUID = UUID()
    @Attribute(originalName: "date")
    var legacyDate: Date = Date()
    var date: Date {
        get { journeyDay?.date ?? legacyDate }
        set { if let journeyDay { journeyDay.date = newValue } else { legacyDate = newValue } }
    }
    @Attribute(originalName: "title")
    var legacyTitle: String = ""
    var title: String {
        get { journeyDay?.title ?? legacyTitle }
        set { if let journeyDay { journeyDay.title = newValue } else { legacyTitle = newValue } }
    }
    @Attribute(originalName: "note")
    var legacyNote: String = ""
    var note: String {
        get { journeyDay?.journalNote ?? legacyNote }
        set { if let journeyDay { journeyDay.journalNote = newValue } else { legacyNote = newValue } }
    }
    @Attribute(originalName: "details")
    var legacyDetails: String = ""
    var details: String {
        get { journeyDay?.journalDetails ?? legacyDetails }
        set { if let journeyDay { journeyDay.journalDetails = newValue } else { legacyDetails = newValue } }
    }
    var didMigrateInlineSummary: Bool = false
    @Attribute(originalName: "sortOrder")
    var legacySortOrder: Int = 0
    var sortOrder: Int {
        get { journeyDay?.sortOrder ?? legacySortOrder }
        set { if let journeyDay { journeyDay.sortOrder = newValue } else { legacySortOrder = newValue } }
    }
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
    var journeyItem: ItineraryItem?
    var usesUnifiedJourney: Bool = false
    var id: UUID = UUID()
    @Attribute(originalName: "title")
    var legacyTitle: String = ""
    var title: String {
        get { journeyItem?.title ?? legacyTitle }
        set { if let journeyItem { journeyItem.title = newValue } else { legacyTitle = newValue } }
    }
    @Attribute(originalName: "categoryRaw")
    var legacyCategoryRaw: String = PlaceCategory.attraction.rawValue
    var categoryRaw: String {
        get { journeyItem?.categoryRaw ?? legacyCategoryRaw }
        set { if let journeyItem { journeyItem.categoryRaw = newValue } else { legacyCategoryRaw = newValue } }
    }
    @Attribute(originalName: "startTime")
    var legacyStartTime: Date?
    var startTime: Date? {
        get { if let journeyItem { return journeyItem.isTimePending ? nil : journeyItem.startTime }; return legacyStartTime }
        set { if let journeyItem { journeyItem.isTimePending = newValue == nil; if let newValue { journeyItem.startTime = newValue } } else { legacyStartTime = newValue } }
    }
    @Attribute(originalName: "endTime")
    var legacyEndTime: Date?
    var endTime: Date? {
        get { if let journeyItem { return journeyItem.isTimePending ? nil : journeyItem.endTime }; return legacyEndTime }
        set { if let journeyItem { journeyItem.isTimePending = newValue == nil; if let newValue { journeyItem.endTime = newValue } } else { legacyEndTime = newValue } }
    }
    @Attribute(originalName: "timeLabel")
    var legacyTimeLabel: String = ""
    var timeLabel: String {
        get { journeyItem?.timeRangeText ?? legacyTimeLabel }
        set { legacyTimeLabel = newValue }
    }
    @Attribute(originalName: "address")
    var legacyAddress: String = ""
    var address: String {
        get { journeyItem?.address ?? legacyAddress }
        set { if let journeyItem { journeyItem.address = newValue } else { legacyAddress = newValue } }
    }
    @Attribute(originalName: "supplementalInfo")
    var legacySupplementalInfo: String = ""
    var supplementalInfo: String {
        get { journeyItem?.journalSupplement ?? legacySupplementalInfo }
        set { if let journeyItem { journeyItem.journalSupplement = newValue } else { legacySupplementalInfo = newValue } }
    }
    var legacyArrangementNote: String = ""
    var arrangementNote: String {
        get { journeyItem?.note ?? legacyArrangementNote }
        set { if let journeyItem { journeyItem.note = newValue } else { legacyArrangementNote = newValue } }
    }
    @Attribute(originalName: "note")
    var legacyNote: String = ""
    var note: String {
        get { journeyItem?.journalNote ?? legacyNote }
        set { if let journeyItem { journeyItem.journalNote = newValue } else { legacyNote = newValue } }
    }
    @Attribute(originalName: "locationModeRaw")
    var legacyLocationModeRaw: String = ""
    var locationModeRaw: String {
        get { journeyItem?.locationModeRaw ?? legacyLocationModeRaw }
        set { if let journeyItem { journeyItem.locationModeRaw = newValue } else { legacyLocationModeRaw = newValue } }
    }
    @Attribute(originalName: "placeName")
    var legacyPlaceName: String = ""
    var placeName: String {
        get { journeyItem?.placeName ?? legacyPlaceName }
        set { if let journeyItem { journeyItem.placeName = newValue } else { legacyPlaceName = newValue } }
    }
    @Attribute(originalName: "placeAddress")
    var legacyPlaceAddress: String = ""
    var placeAddress: String {
        get { journeyItem?.placeAddress ?? legacyPlaceAddress }
        set { if let journeyItem { journeyItem.placeAddress = newValue } else { legacyPlaceAddress = newValue } }
    }
    @Attribute(originalName: "originName")
    var legacyOriginName: String = ""
    var originName: String {
        get { journeyItem?.originName ?? legacyOriginName }
        set { if let journeyItem { journeyItem.originName = newValue } else { legacyOriginName = newValue } }
    }
    @Attribute(originalName: "originAddress")
    var legacyOriginAddress: String = ""
    var originAddress: String {
        get { journeyItem?.originAddress ?? legacyOriginAddress }
        set { if let journeyItem { journeyItem.originAddress = newValue } else { legacyOriginAddress = newValue } }
    }
    @Attribute(originalName: "destinationName")
    var legacyDestinationName: String = ""
    var destinationName: String {
        get { journeyItem?.destinationName ?? legacyDestinationName }
        set { if let journeyItem { journeyItem.destinationName = newValue } else { legacyDestinationName = newValue } }
    }
    @Attribute(originalName: "destinationAddress")
    var legacyDestinationAddress: String = ""
    var destinationAddress: String {
        get { journeyItem?.destinationAddress ?? legacyDestinationAddress }
        set { if let journeyItem { journeyItem.destinationAddress = newValue } else { legacyDestinationAddress = newValue } }
    }
    // Retained for SwiftData compatibility with existing stores; no longer a user-facing field.
    @Attribute(originalName: "attractionTypeRaw")
    var legacyAttractionTypeRaw: String = "unknown"
    var attractionTypeRaw: String {
        get { journeyItem?.attractionTypeRaw ?? legacyAttractionTypeRaw }
        set { if let journeyItem { journeyItem.attractionTypeRaw = newValue } else { legacyAttractionTypeRaw = newValue } }
    }
    @Attribute(originalName: "transportRaw")
    var legacyTransportRaw: String = TransportMode.car.rawValue
    var transportRaw: String {
        get { journeyItem?.transportRaw ?? legacyTransportRaw }
        set { if let journeyItem { journeyItem.transportRaw = newValue } else { legacyTransportRaw = newValue } }
    }
    @Attribute(originalName: "routeInfo")
    var legacyRouteInfo: String = ""
    var routeInfo: String {
        get { journeyItem?.distanceText ?? legacyRouteInfo }
        set { if let journeyItem { journeyItem.distanceText = newValue } else { legacyRouteInfo = newValue } }
    }
    @Attribute(originalName: "cost")
    var legacyCost: Double = 0
    var cost: Double {
        get { journeyItem?.cost ?? legacyCost }
        set { if let journeyItem { journeyItem.cost = newValue } else { legacyCost = newValue } }
    }
    var didPrefillSourceMemory: Bool = false
    var sourceMemoryPrefill: String?
    @Attribute(originalName: "sortOrder")
    var legacySortOrder: Int = 0
    var sortOrder: Int {
        get { journeyItem?.sortOrder ?? legacySortOrder }
        set { if let journeyItem { journeyItem.sortOrder = newValue } else { legacySortOrder = newValue } }
    }
    var sourceItemID: UUID?
    var story: TravelStory?
    var storyDay: StoryDay?

    @Relationship(deleteRule: .nullify, originalName: "media", inverse: \MediaReference.storyEntry)
    var legacyMedia: [MediaReference] = []
    var media: [MediaReference] {
        get { journeyItem?.media ?? legacyMedia }
        set { if let journeyItem { journeyItem.media = newValue } else { legacyMedia = newValue } }
    }

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

    var arrangementSymbol: String {
        if let journeyItem { return journeyItem.arrangementSymbol }
        return category == .transport ? transport.resolved(title: title, note: arrangementNote).symbol : category == .attraction ? (AttractionType(rawValue: attractionTypeRaw) ?? .automatic).resolved(title, arrangementNote).symbol : category.symbol
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
            let fallbackName = JourneyLocationText.entityName(from: placeName, arrangementTitle: title)
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
        media.sorted(by: MediaReference.precedes)
    }
}


struct TravelVoucher: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    let name: String
    let mimeType: String
    let dataBase64: String
}


extension String {
    var formattedLicensePlate: String {
        let value = filter { !$0.isWhitespace && $0 != "·" }.uppercased()
        let characters = Array(value)
        guard characters.count > 2,
              "京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤青藏川宁琼".contains(characters[0]),
              "ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains(characters[1]) else { return value }
        return String(characters.prefix(2)) + "·" + String(characters.dropFirst(2))
    }
}

extension ItineraryItem {
    func retainSelectedLocation() {
        if locationMode == .single {
            originName = ""; originAddress = ""; destinationName = ""; destinationAddress = ""
        } else {
            placeName = ""; placeAddress = ""
        }
        address = locationMode == .single ? placeAddress : destinationAddress
    }
}

extension StoryEntry {
    func retainSelectedLocation() {
        if locationMode == .single {
            originName = ""; originAddress = ""; destinationName = ""; destinationAddress = ""
        } else {
            placeName = ""; placeAddress = ""
        }
        address = locationMode == .single ? placeAddress : destinationAddress
    }
}
