import Foundation

enum JourneyModuleKind {
    case itinerary
    case footprint

    var capabilities: JourneyCapabilities {
        switch self {
        case .itinerary:
            JourneyCapabilities(
                supportsCompletion: true,
                supportsReservation: true,
                supportsPlannedTransport: true,
                supportsBudget: true,
                supportsSourceSync: false,
                supportsPostTripNarrative: false
            )
        case .footprint:
            JourneyCapabilities(
                supportsCompletion: false,
                supportsReservation: false,
                supportsPlannedTransport: true,
                supportsBudget: true,
                supportsSourceSync: true,
                supportsPostTripNarrative: true
            )
        }
    }
}

struct JourneyCapabilities {
    let supportsCompletion: Bool
    let supportsReservation: Bool
    let supportsPlannedTransport: Bool
    let supportsBudget: Bool
    let supportsSourceSync: Bool
    let supportsPostTripNarrative: Bool
}

protocol JourneyRootNode: AnyObject, Identifiable {
    var id: UUID { get }
    var title: String { get set }
    var destination: String { get set }
    var startDate: Date { get set }
    var endDate: Date { get set }
}

protocol JourneyDayNode: AnyObject, Identifiable {
    var id: UUID { get }
    var date: Date { get set }
    var title: String { get set }
    var note: String { get set }
    var sortOrder: Int { get set }
}

protocol JourneyPointNode: AnyObject, Identifiable {
    var id: UUID { get }
    var title: String { get set }
    var category: PlaceCategory { get set }
    var address: String { get set }
    var note: String { get set }
    var sortOrder: Int { get set }
    var media: [MediaReference] { get set }
}

struct JourneyDaySeed {
    let date: Date
    let title: String
    let sortOrder: Int
}

struct JourneyPointSkeleton {
    let sourceID: UUID
    let title: String
    let category: PlaceCategory
    let startTime: Date
    let endTime: Date
    let address: String
    let supplementalInfo: String
    let transport: TransportMode
    let distanceText: String
    let cost: Double
    let sortOrder: Int

    var defaultFootprintMemory: String {
        var parts = ["类型：\(category.rawValue)"]

        let trimmedAddress = Self.cleanedPhrase(address)
        if !trimmedAddress.isEmpty {
            parts.append("说明：\(trimmedAddress)")
        }

        let trimmedDistance = Self.cleanedPhrase(distanceText)
        if trimmedDistance.isEmpty {
            parts.append("前往方式：\(transport.rawValue)")
        } else {
            parts.append("\(transport.rawValue)前往，路程 \(trimmedDistance)")
        }

        if cost > 0 {
            parts.append("花费：¥\(Self.costText(cost))")
        }

        let trimmedSupplement = Self.cleanedPhrase(supplementalInfo)
        if !trimmedSupplement.isEmpty {
            parts.append("补充：\(trimmedSupplement)")
        }

        return parts.joined(separator: "；") + "。"
    }

    private static func costText(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }

    private static func cleanedPhrase(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingPunctuation = CharacterSet(charactersIn: "。；; ，,.！？!?")
        while let scalar = result.unicodeScalars.last,
              trailingPunctuation.contains(scalar) {
            result.removeLast()
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ItineraryTimeAdjustment: Identifiable {
    var id: UUID { item.id }
    let item: ItineraryItem
    let suggestedStartTime: Date
    let suggestedEndTime: Date
}

struct ItineraryMoveResult {
    let didMove: Bool
    let timeAdjustments: [ItineraryTimeAdjustment]

    static let unchanged = ItineraryMoveResult(didMove: false, timeAdjustments: [])
}

enum JourneyHierarchyService {
    static func sortedDays<T: JourneyDayNode>(_ days: [T]) -> [T] {
        days.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.date < rhs.date : lhs.sortOrder < rhs.sortOrder
        }
    }

    @discardableResult
    static func previewMoveTripDay(
        id dayID: UUID,
        to targetDayID: UUID,
        in days: [TripDay]
    ) -> Bool {
        var reordered = sortedDays(days)
        guard
            let sourceIndex = reordered.firstIndex(where: { $0.id == dayID }),
            let targetIndex = reordered.firstIndex(where: { $0.id == targetDayID }),
            sourceIndex != targetIndex
        else { return false }

        let day = reordered.remove(at: sourceIndex)
        reordered.insert(day, at: min(targetIndex, reordered.count))
        for (index, day) in reordered.enumerated() {
            day.sortOrder = index
        }
        return true
    }

    @discardableResult
    static func moveTripDaySchedule(
        id dayID: UUID,
        to targetDayID: UUID,
        in days: [TripDay],
        calendar: Calendar = .current
    ) -> Bool {
        let original = sortedDays(days)
        let dateSlots = original.map(\.date)
        guard
            let sourceIndex = original.firstIndex(where: { $0.id == dayID }),
            let targetIndex = original.firstIndex(where: { $0.id == targetDayID }),
            sourceIndex != targetIndex
        else { return false }

        var reordered = original
        let movedDay = reordered.remove(at: sourceIndex)
        reordered.insert(movedDay, at: min(targetIndex, reordered.count))

        for (index, day) in reordered.enumerated() {
            let oldDate = day.date
            let newDate = dateSlots[index]
            day.sortOrder = index
            day.date = newDate
            if isOrdinalDayTitle(day.title) {
                day.title = "第 \(index + 1) 天"
            }
            guard !calendar.isDate(oldDate, inSameDayAs: newDate) else { continue }
            for item in day.items {
                item.startTime = shiftedDate(
                    item.startTime,
                    whenTripStartMovesFrom: oldDate,
                    to: newDate,
                    calendar: calendar
                )
                item.endTime = shiftedDate(
                    item.endTime,
                    whenTripStartMovesFrom: oldDate,
                    to: newDate,
                    calendar: calendar
                )
            }
        }
        return true
    }

    private static func isOrdinalDayTitle(_ title: String) -> Bool {
        let compact = title.replacingOccurrences(of: " ", with: "")
        guard compact.hasPrefix("第"), compact.hasSuffix("天") else { return false }
        return Int(compact.dropFirst().dropLast()) != nil
    }

    static func sortedPoints<T: JourneyPointNode>(_ points: [T]) -> [T] {
        points.sorted { $0.sortOrder < $1.sortOrder }
    }

    @discardableResult
    static func movePoint<T: JourneyPointNode>(
        id pointID: UUID,
        to targetID: UUID,
        in points: [T]
    ) -> Bool {
        var reordered = sortedPoints(points)
        guard
            let sourceIndex = reordered.firstIndex(where: { $0.id == pointID }),
            let targetIndex = reordered.firstIndex(where: { $0.id == targetID }),
            sourceIndex != targetIndex
        else { return false }

        let point = reordered.remove(at: sourceIndex)
        reordered.insert(point, at: min(targetIndex, reordered.count))
        for (index, point) in reordered.enumerated() {
            point.sortOrder = index
        }
        return true
    }

    @discardableResult
    static func moveItineraryItem(
        id itemID: UUID,
        to targetItemID: UUID,
        in days: [TripDay],
        calendar: Calendar = .current
    ) -> Bool {
        moveItineraryItemResult(
            id: itemID,
            to: targetItemID,
            in: days,
            calendar: calendar
        ).didMove
    }

    static func moveItineraryItemResult(
        id itemID: UUID,
        to targetItemID: UUID,
        in days: [TripDay],
        calendar: Calendar = .current
    ) -> ItineraryMoveResult {
        guard
            let sourceDay = days.first(where: { day in day.items.contains(where: { $0.id == itemID }) }),
            let targetDay = days.first(where: { day in day.items.contains(where: { $0.id == targetItemID }) }),
            let item = sourceDay.items.first(where: { $0.id == itemID })
        else { return .unchanged }

        if sourceDay.id == targetDay.id {
            let originalItems = sourceDay.sortedItems
            let slots = originalItems.map { timeSlot(for: $0, calendar: calendar) }
            let moved = movePoint(id: itemID, to: targetItemID, in: sourceDay.items)
            guard moved else { return .unchanged }
            let adjustments = reconcileTimeSlots(
                slots,
                withOriginalOwners: originalItems.map(\.id),
                to: sourceDay.sortedItems,
                on: sourceDay.date,
                calendar: calendar
            )
            return ItineraryMoveResult(didMove: true, timeAdjustments: adjustments)
        }

        let slotOwners = (targetDay.sortedItems + [item]).sorted {
            timeSlot(for: $0, calendar: calendar) < timeSlot(for: $1, calendar: calendar)
        }
        let targetSlots = slotOwners.map { timeSlot(for: $0, calendar: calendar) }
        var targetItems = targetDay.sortedItems
        guard let targetIndex = targetItems.firstIndex(where: { $0.id == targetItemID }) else { return .unchanged }
        sourceDay.items.removeAll { $0.id == itemID }
        item.day = targetDay
        targetDay.items.append(item)
        targetItems.insert(item, at: targetIndex)
        normalizeSortOrder(sourceDay.sortedItems)
        normalizeSortOrder(targetItems)
        let adjustments = reconcileTimeSlots(
            targetSlots,
            withOriginalOwners: slotOwners.map(\.id),
            to: targetItems,
            on: targetDay.date,
            calendar: calendar
        )
        return ItineraryMoveResult(didMove: true, timeAdjustments: adjustments)
    }

    @discardableResult
    static func previewMoveItineraryItem(
        id itemID: UUID,
        to targetItemID: UUID,
        in days: [TripDay]
    ) -> Bool {
        guard
            itemID != targetItemID,
            let sourceDay = days.first(where: { day in day.items.contains(where: { $0.id == itemID }) }),
            let targetDay = days.first(where: { day in day.items.contains(where: { $0.id == targetItemID }) }),
            let item = sourceDay.items.first(where: { $0.id == itemID })
        else { return false }

        if sourceDay.id == targetDay.id {
            return movePoint(id: itemID, to: targetItemID, in: sourceDay.items)
        }

        var targetItems = targetDay.sortedItems
        guard let targetIndex = targetItems.firstIndex(where: { $0.id == targetItemID }) else { return false }
        sourceDay.items.removeAll { $0.id == itemID }
        item.day = targetDay
        targetDay.items.append(item)
        targetItems.insert(item, at: targetIndex)
        normalizeSortOrder(sourceDay.sortedItems)
        normalizeSortOrder(targetItems)
        return true
    }

    @discardableResult
    static func moveItineraryItem(
        id itemID: UUID,
        toEndOf targetDay: TripDay,
        in days: [TripDay],
        calendar: Calendar = .current
    ) -> Bool {
        moveItineraryItemResult(
            id: itemID,
            toEndOf: targetDay,
            in: days,
            calendar: calendar
        ).didMove
    }

    static func moveItineraryItemResult(
        id itemID: UUID,
        toEndOf targetDay: TripDay,
        in days: [TripDay],
        calendar: Calendar = .current
    ) -> ItineraryMoveResult {
        guard
            let sourceDay = days.first(where: { day in day.items.contains(where: { $0.id == itemID }) }),
            let item = sourceDay.items.first(where: { $0.id == itemID })
        else { return .unchanged }

        if sourceDay.id == targetDay.id {
            let originalItems = sourceDay.sortedItems
            let slots = originalItems.map { timeSlot(for: $0, calendar: calendar) }
            var items = originalItems
            guard let sourceIndex = items.firstIndex(where: { $0.id == itemID }), sourceIndex != items.count - 1 else {
                return .unchanged
            }
            items.remove(at: sourceIndex)
            items.append(item)
            normalizeSortOrder(items)
            let adjustments = reconcileTimeSlots(
                slots,
                withOriginalOwners: originalItems.map(\.id),
                to: items,
                on: sourceDay.date,
                calendar: calendar
            )
            return ItineraryMoveResult(didMove: true, timeAdjustments: adjustments)
        }

        let slotOwners = (targetDay.sortedItems + [item]).sorted {
            timeSlot(for: $0, calendar: calendar) < timeSlot(for: $1, calendar: calendar)
        }
        let targetSlots = slotOwners.map { timeSlot(for: $0, calendar: calendar) }
        sourceDay.items.removeAll { $0.id == itemID }
        item.day = targetDay
        targetDay.items.append(item)
        normalizeSortOrder(sourceDay.sortedItems)
        normalizeSortOrder(targetDay.sortedItems)
        let adjustments = reconcileTimeSlots(
            targetSlots,
            withOriginalOwners: slotOwners.map(\.id),
            to: targetDay.sortedItems,
            on: targetDay.date,
            calendar: calendar
        )
        return ItineraryMoveResult(didMove: true, timeAdjustments: adjustments)
    }

    @discardableResult
    static func previewMoveItineraryItem(
        id itemID: UUID,
        toEndOf targetDay: TripDay,
        in days: [TripDay]
    ) -> Bool {
        guard
            let sourceDay = days.first(where: { day in day.items.contains(where: { $0.id == itemID }) }),
            let item = sourceDay.items.first(where: { $0.id == itemID })
        else { return false }

        if sourceDay.id == targetDay.id {
            var items = sourceDay.sortedItems
            guard let sourceIndex = items.firstIndex(where: { $0.id == itemID }), sourceIndex != items.count - 1 else {
                return false
            }
            items.remove(at: sourceIndex)
            items.append(item)
            normalizeSortOrder(items)
            return true
        }

        sourceDay.items.removeAll { $0.id == itemID }
        item.day = targetDay
        targetDay.items.append(item)
        normalizeSortOrder(sourceDay.sortedItems)
        normalizeSortOrder(targetDay.sortedItems)
        return true
    }

    private static func normalizeSortOrder<T: JourneyPointNode>(_ points: [T]) {
        for (index, point) in points.enumerated() {
            point.sortOrder = index
        }
    }

    private struct ItineraryTimeSlot: Comparable {
        let hour: Int
        let minute: Int
        let second: Int
        let duration: TimeInterval

        static func < (lhs: ItineraryTimeSlot, rhs: ItineraryTimeSlot) -> Bool {
            (lhs.hour, lhs.minute, lhs.second) < (rhs.hour, rhs.minute, rhs.second)
        }
    }

    private static func reconcileTimeSlots(
        _ slots: [ItineraryTimeSlot],
        withOriginalOwners originalOwnerIDs: [UUID],
        to items: [ItineraryItem],
        on date: Date,
        calendar: Calendar
    ) -> [ItineraryTimeAdjustment] {
        let affectedIndices = items.indices.filter { index in
            index < originalOwnerIDs.count && items[index].id != originalOwnerIDs[index]
        }
        let unaffectedIndices = items.indices.filter { !affectedIndices.contains($0) }
        for index in unaffectedIndices where slots.indices.contains(index) {
            apply(slots[index], to: items[index], on: date, calendar: calendar)
        }
        guard !affectedIndices.isEmpty else { return [] }

        let durationsMatch = affectedIndices.allSatisfy { index in
            abs(items[index].endTime.timeIntervalSince(items[index].startTime) - slots[index].duration) < 1
        }
        if durationsMatch {
            for index in affectedIndices {
                apply(slots[index], to: items[index], on: date, calendar: calendar)
            }
            return []
        }

        return affectedIndices.compactMap { index in
            guard let range = suggestedRange(for: index, in: slots, on: date, calendar: calendar) else {
                return nil
            }
            return ItineraryTimeAdjustment(
                item: items[index],
                suggestedStartTime: range.start,
                suggestedEndTime: range.end
            )
        }
    }

    private static func suggestedRange(
        for index: Int,
        in slots: [ItineraryTimeSlot],
        on date: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        guard slots.indices.contains(index), let slotStart = startDate(for: slots[index], on: date, calendar: calendar) else {
            return nil
        }
        let slotEnd = slotStart.addingTimeInterval(slots[index].duration)
        var start = slotStart
        var end = slotEnd

        if index > slots.startIndex,
           let previousStart = startDate(for: slots[index - 1], on: date, calendar: calendar) {
            start = max(start, previousStart.addingTimeInterval(slots[index - 1].duration))
        }
        if index < slots.index(before: slots.endIndex),
           let nextStart = startDate(for: slots[index + 1], on: date, calendar: calendar) {
            end = min(end, nextStart)
        }
        if end < start {
            return (slotStart, slotEnd)
        }
        return (start, end)
    }

    private static func timeSlot(for item: ItineraryItem, calendar: Calendar) -> ItineraryTimeSlot {
        let components = calendar.dateComponents([.hour, .minute, .second], from: item.startTime)
        return ItineraryTimeSlot(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            duration: max(0, item.endTime.timeIntervalSince(item.startTime))
        )
    }

    private static func apply(
        _ slots: [ItineraryTimeSlot],
        to items: [ItineraryItem],
        on date: Date,
        calendar: Calendar
    ) {
        for (item, slot) in zip(items, slots) {
            apply(slot, to: item, on: date, calendar: calendar)
        }
    }

    private static func apply(
        _ slot: ItineraryTimeSlot,
        to item: ItineraryItem,
        on date: Date,
        calendar: Calendar
    ) {
        guard let start = startDate(for: slot, on: date, calendar: calendar) else { return }
        item.startTime = start
        item.endTime = start.addingTimeInterval(slot.duration)
    }

    private static func startDate(for slot: ItineraryTimeSlot, on date: Date, calendar: Calendar) -> Date? {
        calendar.date(
            bySettingHour: slot.hour,
            minute: slot.minute,
            second: slot.second,
            of: date
        )
    }

    static func nextDaySeed<D: JourneyDayNode>(
        after days: [D],
        fallbackDate: Date,
        calendar: Calendar = .current
    ) -> JourneyDaySeed {
        let sorted = sortedDays(days)
        let date = calendar.date(byAdding: .day, value: 1, to: sorted.last?.date ?? fallbackDate) ?? fallbackDate
        return JourneyDaySeed(date: date, title: "第 \(days.count + 1) 天", sortOrder: days.count)
    }

    @discardableResult
    static func appendDay(
        to trip: Trip,
        calendar: Calendar = .current
    ) -> TripDay {
        let seed = nextDaySeed(after: trip.days, fallbackDate: trip.startDate, calendar: calendar)
        let day = TripDay(date: seed.date, title: seed.title, sortOrder: seed.sortOrder, trip: trip)
        trip.days.append(day)

        if calendar.startOfDay(for: seed.date) > calendar.startOfDay(for: trip.endDate) {
            trip.endDate = calendar.startOfDay(for: seed.date)
        }
        return day
    }

    static func daySeeds(
        from startDate: Date,
        through endDate: Date,
        maximumCount: Int = 31,
        calendar: Calendar = .current
    ) -> [JourneyDaySeed] {
        let start = calendar.startOfDay(for: startDate)
        let end = max(start, calendar.startOfDay(for: endDate))
        let count = min(maximumCount, max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1))
        return (0..<count).map { index in
            JourneyDaySeed(
                date: calendar.date(byAdding: .day, value: index, to: start) ?? start,
                title: "第 \(index + 1) 天",
                sortOrder: index
            )
        }
    }

    static func shiftedDate(
        _ date: Date,
        whenTripStartMovesFrom oldStartDate: Date,
        to newStartDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        let oldStart = calendar.startOfDay(for: oldStartDate)
        let newStart = calendar.startOfDay(for: newStartDate)
        let dayOffset = calendar.dateComponents([.day], from: oldStart, to: newStart).day ?? 0
        return calendar.date(byAdding: .day, value: dayOffset, to: date) ?? date
    }

    static func shiftTripScheduleDates(
        _ trip: Trip,
        from oldStartDate: Date,
        to newStartDate: Date,
        calendar: Calendar = .current
    ) {
        let oldStart = calendar.startOfDay(for: oldStartDate)
        let newStart = calendar.startOfDay(for: newStartDate)
        guard oldStart != newStart else { return }

        for day in trip.days {
            day.date = shiftedDate(
                day.date,
                whenTripStartMovesFrom: oldStart,
                to: newStart,
                calendar: calendar
            )
            for item in day.items {
                item.startTime = shiftedDate(
                    item.startTime,
                    whenTripStartMovesFrom: oldStart,
                    to: newStart,
                    calendar: calendar
                )
                item.endTime = shiftedDate(
                    item.endTime,
                    whenTripStartMovesFrom: oldStart,
                    to: newStart,
                    calendar: calendar
                )
            }
        }
    }

    static func updateTripDateRange(
        _ trip: Trip,
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .current
    ) {
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = max(normalizedStart, calendar.startOfDay(for: endDate))
        let currentScheduleStart = sortedDays(trip.days).first?.date ?? trip.startDate

        shiftTripScheduleDates(
            trip,
            from: currentScheduleStart,
            to: normalizedStart,
            calendar: calendar
        )
        trip.startDate = normalizedStart
        trip.endDate = normalizedEnd
    }

    static func hasUserContent<P: JourneyPointNode>(_ point: P) -> Bool {
        !point.address.isEmpty || !point.note.isEmpty || !point.media.isEmpty
    }
}

extension Trip: JourneyRootNode {
    var moduleKind: JourneyModuleKind { .itinerary }
}

extension TravelStory: JourneyRootNode {
    var moduleKind: JourneyModuleKind { .footprint }
}

extension TripDay: JourneyDayNode {}
extension StoryDay: JourneyDayNode {}
extension ItineraryItem: JourneyPointNode {}
extension StoryEntry: JourneyPointNode {}

extension ItineraryItem {
    var footprintSkeleton: JourneyPointSkeleton {
        JourneyPointSkeleton(
            sourceID: id,
            title: title,
            category: category,
            startTime: startTime,
            endTime: endTime,
            address: address,
            supplementalInfo: note,
            transport: transport,
            distanceText: distanceText,
            cost: cost,
            sortOrder: sortOrder
        )
    }
}

extension StoryEntry {
    func apply(_ skeleton: JourneyPointSkeleton) {
        sourceItemID = skeleton.sourceID
        title = skeleton.title
        category = skeleton.category
        startTime = skeleton.startTime
        endTime = skeleton.endTime
        timeLabel = "\(skeleton.startTime.timeText)～\(skeleton.endTime.timeText)"
        if !didPrefillSourceMemory {
            if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let prefill = skeleton.defaultFootprintMemory
                note = prefill
                sourceMemoryPrefill = prefill
            }
            didPrefillSourceMemory = true
        }
        address = ""
        supplementalInfo = ""
        transport = .car
        distanceText = ""
        cost = 0
        sortOrder = skeleton.sortOrder
    }
}
