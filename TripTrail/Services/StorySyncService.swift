import Foundation
import SwiftData

struct StorySyncReport {
    var addedDays = 0
    var addedEntries = 0
    var updatedEntries = 0
    var detachedEntries = 0

    var message: String {
        "已同步最新旅程框架：新增 \(addedDays) 天、\(addedEntries) 个记录，更新 \(updatedEntries) 个；保留 \(detachedEntries) 个已有回忆或影像的旧记录。"
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

        migrateAutomaticSourceMemories(in: story)
        migrateLegacyInlineSummaries(in: story)
    }

    /// Earlier versions put source itinerary facts into the editable memory field.
    /// Keep those facts as source metadata, while leaving memory for the user's own words.
    private static func migrateAutomaticSourceMemories(in story: TravelStory) {
        for entry in story.entries {
            let memory = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !memory.isEmpty, entry.sourceItemID != nil else { continue }

            let storedSourceDetails = entry.sourceMemoryPrefill?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if memory == storedSourceDetails {
                entry.note = ""
            } else if storedSourceDetails == nil, memory.hasPrefix("类型：") {
                entry.sourceMemoryPrefill = memory
                entry.note = ""
                entry.didPrefillSourceMemory = true
            }
        }
    }

    /// Fills only missing legacy location fields. User-edited location data is never overwritten.
    @discardableResult
    static func migrateLegacyLocations(for story: TravelStory, from trip: Trip?) -> Bool {
        guard let trip else { return false }
        let sourceItems = Dictionary(uniqueKeysWithValues: trip.allItems.map { ($0.id, $0) })
        var changed = false

        for entry in story.entries {
            guard entry.locationModeRaw.isEmpty,
                  entry.placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.originName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.destinationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let sourceItemID = entry.sourceItemID,
                  let sourceItem = sourceItems[sourceItemID]
            else { continue }

            let skeleton = sourceItem.footprintSkeleton
            entry.locationMode = skeleton.locationMode
            entry.placeName = skeleton.placeName
            entry.placeAddress = skeleton.placeAddress
            entry.originName = skeleton.originName
            entry.originAddress = skeleton.originAddress
            entry.destinationName = skeleton.destinationName
            entry.destinationAddress = skeleton.destinationAddress
            entry.address = ""
            changed = true
        }
        return changed
    }

    private static func migrateLegacyInlineSummaries(in story: TravelStory) {
        for day in story.days where !day.didMigrateInlineSummary {
            if day.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let legacyEntry = day.sortedEntries.first(where: {
                   let memory = $0.note.trimmingCharacters(in: .whitespacesAndNewlines)
                   let sourceDetails = $0.sourceMemoryPrefill?
                       .trimmingCharacters(in: .whitespacesAndNewlines)
                   return !memory.isEmpty && memory != sourceDetails
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
            startTime: skeleton.startTime,
            endTime: skeleton.endTime,
            address: skeleton.address,
            locationMode: skeleton.locationMode,
            placeName: skeleton.placeName,
            placeAddress: skeleton.placeAddress,
            originName: skeleton.originName,
            originAddress: skeleton.originAddress,
            destinationName: skeleton.destinationName,
            destinationAddress: skeleton.destinationAddress,
            supplementalInfo: skeleton.supplementalInfo,
            transport: skeleton.transport,
            distanceText: skeleton.distanceText,
            cost: skeleton.cost,
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
        let memory = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let automaticPrefill = entry.sourceMemoryPrefill?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasEditedMemory = !memory.isEmpty && memory != automaticPrefill
        return hasEditedMemory || !entry.media.isEmpty
    }
}
