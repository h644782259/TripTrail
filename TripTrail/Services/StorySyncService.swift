import Foundation
import SwiftData

struct StorySyncReport {
    var addedDays = 0
    var addedEntries = 0
    var updatedEntries = 0
    var detachedEntries = 0

    var message: String {
        "已同步最新骨架：新增 \(addedDays) 天、\(addedEntries) 个行程点，更新 \(updatedEntries) 个；保留 \(detachedEntries) 个已有补充内容的旧片段。"
    }
}

@MainActor
enum StorySyncService {
    static func ensureHierarchy(for story: TravelStory) {
        if story.days.isEmpty, !story.entries.isEmpty {
            let grouped = Dictionary(grouping: story.entries) { entry in
                entry.timeLabel.split(separator: "·").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "已收录片段"
            }
            for (index, key) in grouped.keys.sorted().enumerated() {
                let day = StoryDay(
                    date: Calendar.current.date(byAdding: .day, value: index, to: story.startDate) ?? story.startDate,
                    title: key.isEmpty ? "已收录片段" : key,
                    sortOrder: index,
                    story: story
                )
                day.didMigrateInlineSummary = false
                story.days.append(day)
                for (entryIndex, entry) in (grouped[key] ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
                    entry.sortOrder = entryIndex
                    entry.storyDay = day
                    day.entries.append(entry)
                }
            }
        }

        migrateLegacyInlineSummaries(in: story)
    }

    private static func migrateLegacyInlineSummaries(in story: TravelStory) {
        for day in story.days where !day.didMigrateInlineSummary {
            if day.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let legacyEntry = day.sortedEntries.first(where: {
                   !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
               }) {
                day.note = legacyEntry.note
                legacyEntry.note = ""
            }
            day.didMigrateInlineSummary = true
        }
    }

    static func sync(story: TravelStory, from trip: Trip, modelContext: ModelContext) -> StorySyncReport {
        ensureHierarchy(for: story)
        var report = StorySyncReport()
        story.title = trip.title
        story.destination = trip.destination
        story.startDate = trip.startDate
        story.endDate = trip.endDate

        let sourceDays = scopedDays(for: story, trip: trip)
        let desiredDayIDs = Set(sourceDays.map(\.id))

        for (dayIndex, sourceDay) in sourceDays.enumerated() {
            let storyDay: StoryDay
            if let existing = story.days.first(where: { $0.sourceDayID == sourceDay.id }) {
                storyDay = existing
            } else {
                storyDay = StoryDay(date: sourceDay.date, title: sourceDay.title, sortOrder: dayIndex, sourceDayID: sourceDay.id, story: story)
                story.days.append(storyDay)
                report.addedDays += 1
            }
            storyDay.date = sourceDay.date
            storyDay.title = sourceDay.title
            storyDay.sortOrder = dayIndex

            let sourceItems = scopedItems(for: story, day: sourceDay)
            let desiredItemIDs = Set(sourceItems.map(\.id))
            for (itemIndex, sourceItem) in sourceItems.enumerated() {
                let entry: StoryEntry
                if let existing = story.entries.first(where: { $0.sourceItemID == sourceItem.id }) {
                    entry = existing
                    report.updatedEntries += 1
                } else {
                    entry = StoryEntry(title: sourceItem.title, category: sourceItem.category, sortOrder: itemIndex)
                    entry.sourceItemID = sourceItem.id
                    entry.story = story
                    story.entries.append(entry)
                    report.addedEntries += 1
                }
                if entry.storyDay?.id != storyDay.id {
                    entry.storyDay?.entries.removeAll { $0.id == entry.id }
                    entry.storyDay = storyDay
                    if !storyDay.entries.contains(where: { $0.id == entry.id }) { storyDay.entries.append(entry) }
                }
                updateSkeleton(entry, from: sourceItem, sortOrder: itemIndex)
            }

            for entry in storyDay.entries.filter({ $0.sourceItemID.map { !desiredItemIDs.contains($0) } == true }) {
                detachOrDelete(entry, from: storyDay, modelContext: modelContext, report: &report)
            }
        }

        for day in story.days where day.sourceDayID.map({ !desiredDayIDs.contains($0) }) == true {
            for entry in day.entries.filter({ $0.sourceItemID != nil }) {
                detachOrDelete(entry, from: day, modelContext: modelContext, report: &report)
            }
            if day.entries.isEmpty && day.note.isEmpty && day.details.isEmpty {
                modelContext.delete(day)
            } else {
                day.sourceDayID = nil
            }
        }
        return report
    }

    private static func scopedDays(for story: TravelStory, trip: Trip) -> [TripDay] {
        switch story.syncScope {
        case .trip:
            trip.sortedDays
        case .day, .item:
            trip.sortedDays.filter { day in
                story.sourceSelectionIDs.contains(day.id) ||
                day.items.contains { story.sourceSelectionIDs.contains($0.id) }
            }
        }
    }

    private static func scopedItems(for story: TravelStory, day: TripDay) -> [ItineraryItem] {
        if story.syncScope == .trip || story.sourceSelectionIDs.contains(day.id) {
            return day.sortedItems
        }
        return day.sortedItems.filter { story.sourceSelectionIDs.contains($0.id) }
    }

    private static func updateSkeleton(_ entry: StoryEntry, from item: ItineraryItem, sortOrder: Int) {
        var skeleton = item.footprintSkeleton
        skeleton = JourneyPointSkeleton(
            sourceID: skeleton.sourceID,
            title: skeleton.title,
            category: skeleton.category,
            timeLabel: skeleton.timeLabel,
            sortOrder: sortOrder
        )
        entry.apply(skeleton)
    }

    private static func detachOrDelete(
        _ entry: StoryEntry,
        from day: StoryDay,
        modelContext: ModelContext,
        report: inout StorySyncReport
    ) {
        if hasUserContent(entry) {
            entry.sourceItemID = nil
            report.detachedEntries += 1
        } else {
            day.entries.removeAll { $0.id == entry.id }
            entry.story?.entries.removeAll { $0.id == entry.id }
            modelContext.delete(entry)
        }
    }

    private static func hasUserContent(_ entry: StoryEntry) -> Bool {
        JourneyHierarchyService.hasUserContent(entry) || !entry.routeInfo.isEmpty
    }
}
