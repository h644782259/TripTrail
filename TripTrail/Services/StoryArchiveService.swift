import Foundation
import SwiftData

struct StoryArchiveResult {
    let story: TravelStory
    let createdStory: Bool
    let addedDays: Int
    let addedEntries: Int
}

@MainActor
enum StoryArchiveService {
    static func archive(
        trip: Trip,
        selectedItems: [ItineraryItem],
        syncScope: StorySyncScope,
        sourceIDs: Set<UUID>,
        summary: String,
        replacesSyncSelection: Bool = false,
        modelContext: ModelContext
    ) throws -> StoryArchiveResult {
        let allStories = try modelContext.fetch(FetchDescriptor<TravelStory>())
        let existingStory = allStories
            .filter { $0.sourceTripID == trip.id }
            .sorted { $0.createdAt < $1.createdAt }
            .first

        let story: TravelStory
        let createdStory: Bool
        if let existingStory {
            story = existingStory
            createdStory = false
        } else {
            story = TravelStory(
                title: trip.title,
                destination: trip.destination,
                startDate: trip.startDate,
                endDate: trip.endDate,
                summary: summary
            )
            story.sourceTripID = trip.id
            story.syncScope = syncScope
            story.sourceSelectionIDs = sourceIDs
            modelContext.insert(story)
            createdStory = true
        }

        // 一段源行程始终只写入同一个足迹容器；再次收藏只合并骨架。
        story.title = trip.title
        story.destination = trip.destination
        story.startDate = trip.startDate
        story.endDate = trip.endDate
        if story.summary.isEmpty && !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            story.summary = summary
        }
        if !createdStory && replacesSyncSelection {
            story.syncScope = syncScope
            story.sourceSelectionIDs = sourceIDs
            let report = StorySyncService.sync(story: story, from: trip, modelContext: modelContext)
            return StoryArchiveResult(
                story: story,
                createdStory: false,
                addedDays: report.addedDays,
                addedEntries: report.addedEntries
            )
        } else if !createdStory {
            mergeSyncSelection(into: story, scope: syncScope, sourceIDs: sourceIDs)
        }

        let selectedItemIDs = Set(selectedItems.map(\.id))
        var addedDays = 0
        var addedEntries = 0

        for sourceDay in trip.sortedDays {
            let sourceItems = sourceDay.sortedItems.filter { selectedItemIDs.contains($0.id) }
            guard syncScope == .trip || !sourceItems.isEmpty else { continue }

            let storyDay: StoryDay
            if let existing = story.days.first(where: { $0.sourceDayID == sourceDay.id }) {
                storyDay = existing
            } else {
                storyDay = StoryDay(
                    date: sourceDay.date,
                    title: sourceDay.title,
                    sortOrder: sourceDay.sortOrder,
                    sourceDayID: sourceDay.id,
                    story: story
                )
                story.days.append(storyDay)
                addedDays += 1
            }

            storyDay.date = sourceDay.date
            storyDay.title = sourceDay.title
            storyDay.sortOrder = sourceDay.sortOrder

            for sourceItem in sourceItems {
                let entry: StoryEntry
                if let existing = story.entries.first(where: { $0.sourceItemID == sourceItem.id }) {
                    entry = existing
                } else {
                    entry = StoryEntry(
                        title: sourceItem.title,
                        category: sourceItem.category,
                        sortOrder: sourceItem.sortOrder
                    )
                    entry.sourceItemID = sourceItem.id
                    entry.story = story
                    story.entries.append(entry)
                    addedEntries += 1
                }

                if entry.storyDay?.id != storyDay.id {
                    entry.storyDay?.entries.removeAll { $0.id == entry.id }
                    entry.storyDay = storyDay
                }
                if !storyDay.entries.contains(where: { $0.id == entry.id }) {
                    storyDay.entries.append(entry)
                }

                // 这里只同步框架，不从行程复制地址、备注、路线或媒体。
                entry.apply(sourceItem.footprintSkeleton)
            }
        }

        return StoryArchiveResult(
            story: story,
            createdStory: createdStory,
            addedDays: addedDays,
            addedEntries: addedEntries
        )
    }

    private static func mergeSyncSelection(
        into story: TravelStory,
        scope: StorySyncScope,
        sourceIDs: Set<UUID>
    ) {
        if story.syncScope == .trip || scope == .trip {
            story.syncScope = .trip
            story.sourceSelectionIDs = []
            return
        }

        story.sourceSelectionIDs.formUnion(sourceIDs)
        // day / item 在合并后都按 sourceSelectionIDs 中的实际 UUID 类型解析。
        story.syncScope = story.syncScope == .day || scope == .day ? .day : .item
    }
}
