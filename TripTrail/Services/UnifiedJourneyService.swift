import Foundation
import SwiftData

/// Legacy footprint models are identity adapters; all editable content belongs to Trip.
@MainActor
enum UnifiedJourneyService {
    static func prepareStoreBackup() throws {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let folder = support.appendingPathComponent("BeforeUnifiedJourneys", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        let source = support.appendingPathComponent("default.store")
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let file = support.appendingPathComponent("default.store" + suffix)
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    static func reconcile(context: ModelContext) throws {
        var trips = try context.fetch(FetchDescriptor<Trip>())
        let stories = try context.fetch(FetchDescriptor<TravelStory>())
        for story in stories where !story.usesUnifiedJourney {
            let matching = trips.first { $0.id == story.sourceTripID || $0.id == story.id }
            let trip = matching ?? Trip(title: story.title, destination: story.destination,
                startDate: story.startDate, endDate: story.endDate)
            if matching == nil { trip.id = story.id; trip.createdAt = story.createdAt; context.insert(trip); trips.append(trip) }
            if !story.summary.isEmpty && trip.journalSummary != story.summary {
                trip.journalSummary = trip.journalSummary.isEmpty ? story.summary : trip.journalSummary + "\n\n" + story.summary
            }
            if trip.coverMedia == nil {
                trip.coverMedia = story.legacyCoverMedia
                trip.coverZoom = story.coverZoom; trip.coverOffsetX = story.coverOffsetX; trip.coverOffsetY = story.coverOffsetY
            }
            StorySyncService.ensureHierarchy(for: story)
            let orphans = story.entries.filter { $0.storyDay == nil }
            if !orphans.isEmpty {
                let day = StoryDay(date: story.startDate, title: "", sortOrder: story.days.count, story: story)
                story.days.append(day)
                for entry in orphans { entry.storyDay = day; day.entries.append(entry) }
            }
            for day in story.days {
                let target = trip.days.first { $0.id == day.sourceDayID || $0.id == day.id }
                    ?? trip.days.first { Calendar.current.isDate($0.date, inSameDayAs: day.date) }
                    ?? TripDay(date: day.date, title: day.title, sortOrder: day.sortOrder, trip: trip)
                if !trip.days.contains(where: { $0.id == target.id }) { target.id = day.sourceDayID ?? day.id; trip.days.append(target) }
                target.journalNote = mergeText(target.journalNote, day.note)
                target.journalDetails = mergeText(target.journalDetails, day.details)
                for entry in day.entries {
                    let item = trip.allItems.first { $0.id == entry.sourceItemID || $0.id == entry.id }
                        ?? makeItem(entry, day: target)
                    if !target.items.contains(where: { $0.id == item.id }) && item.day == target { target.items.append(item) }
                    mergeMemory(entry, into: item)
                    entry.journeyItem = item; entry.id = item.id; entry.sourceItemID = item.id; entry.usesUnifiedJourney = true
                }
                day.journeyDay = target; day.id = target.id; day.sourceDayID = target.id; day.usesUnifiedJourney = true
            }
            for entry in story.entries {
                if let item = entry.journeyItem, entry.storyDay?.journeyDay?.id != item.day?.id {
                    entry.storyDay?.entries.removeAll { $0.id == entry.id }; entry.storyDay = nil
                }
            }
            story.journey = trip; story.id = trip.id; story.sourceTripID = trip.id; story.usesUnifiedJourney = true
        }
        // All legacy copies have been merged; retain one identity adapter per canonical trip.
        var adapterIDs = Set<UUID>()
        for story in stories where story.usesUnifiedJourney {
            if !adapterIDs.insert(story.id).inserted {
                context.delete(story)
            }
        }
        let adapters = stories.filter { !$0.isDeleted }
        for trip in trips {
            let story = adapters.first { $0.id == trip.id } ?? {
                let adapter = TravelStory(title: trip.title, destination: trip.destination, startDate: trip.startDate, endDate: trip.endDate, summary: "")
                adapter.id = trip.id; adapter.sourceTripID = trip.id; adapter.journey = trip; adapter.usesUnifiedJourney = true
                context.insert(adapter); return adapter
            }()
            // New narrative days and records created by the existing editors become canonical arrangements.
            for day in story.days where !day.usesUnifiedJourney {
                let target = TripDay(date: day.date, title: day.title, sortOrder: day.sortOrder, trip: trip)
                target.id = day.id; target.journalNote = day.note; target.journalDetails = day.details
                trip.days.append(target); day.journeyDay = target; day.sourceDayID = target.id; day.usesUnifiedJourney = true
            }
            for entry in story.entries where !entry.usesUnifiedJourney {
                guard let target = entry.storyDay?.journeyDay ?? trip.sortedDays.first else { continue }
                let item = makeItem(entry, day: target); mergeMemory(entry, into: item); target.items.append(item)
                entry.journeyItem = item; entry.id = item.id; entry.sourceItemID = item.id; entry.usesUnifiedJourney = true
            }
            // Bind by stable IDs before reading relationships invalidated by a remote graph replacement.
            for day in story.days where day.usesUnifiedJourney {
                day.journeyDay = trip.days.first { $0.id == day.id }
            }
            for entry in story.entries where entry.usesUnifiedJourney {
                entry.journeyItem = trip.allItems.first { $0.id == entry.id }
            }
            for entry in story.entries {
                if let item = entry.journeyItem, let targetDay = entry.storyDay?.journeyDay, item.day?.id != targetDay.id {
                    item.day?.items.removeAll { $0.id == item.id }; item.day = targetDay
                    if !targetDay.items.contains(where: { $0.id == item.id }) { targetDay.items.append(item) }
                }
            }
            let dayIDs = Set(trip.days.map(\.id)); let itemIDs = Set(trip.allItems.map(\.id))
            for entry in story.entries where entry.usesUnifiedJourney && !itemIDs.contains(entry.id) {
                story.entries.removeAll { $0.id == entry.id }; entry.storyDay?.entries.removeAll { $0.id == entry.id }; context.delete(entry)
            }
            for day in story.days where day.usesUnifiedJourney && !dayIDs.contains(day.id) { story.days.removeAll { $0.id == day.id }; context.delete(day) }
            for target in trip.sortedDays {
                let day = story.days.first { $0.id == target.id } ?? {
                    let adapter = StoryDay(date: target.date, title: target.title, sortOrder: target.sortOrder, sourceDayID: target.id, story: story)
                    adapter.id = target.id; adapter.journeyDay = target; adapter.usesUnifiedJourney = true; story.days.append(adapter); return adapter
                }()
                day.journeyDay = target
                for item in target.sortedItems {
                    let entry = story.entries.first { $0.id == item.id } ?? {
                        let adapter = StoryEntry(title: item.title, category: item.category, sortOrder: item.sortOrder)
                        adapter.id = item.id; adapter.journeyItem = item; adapter.sourceItemID = item.id; adapter.usesUnifiedJourney = true
                        adapter.story = story; story.entries.append(adapter); return adapter
                    }()
                    entry.journeyItem = item
                    if entry.storyDay?.id != day.id {
                        entry.storyDay?.entries.removeAll { $0.id == entry.id }; entry.storyDay = day
                        if !day.entries.contains(where: { $0.id == entry.id }) { day.entries.append(entry) }
                    }
                }
            }
        }
        try context.save()
    }

    static func removeMedia(ids: Set<UUID>, from entry: StoryEntry, context: ModelContext) {
        if let item = entry.journeyItem {
            removeMedia(ids: ids, from: item, context: context)
            return
        }
        let removed = entry.media.filter { ids.contains($0.id) }
        entry.media = entry.media.filter { !ids.contains($0.id) }
        for media in removed {
            media.storyEntry = nil
            media.itineraryItem = nil
            context.delete(media)
        }
    }

    static func removeMedia(ids: Set<UUID>, from item: ItineraryItem, context: ModelContext) {
        let removed = item.media.filter { ids.contains($0.id) }
        item.media = item.media.filter { !ids.contains($0.id) }
        for media in removed {
            media.storyEntry = nil
            media.itineraryItem = nil
            context.delete(media)
        }
    }

    private static func makeItem(_ entry: StoryEntry, day: TripDay) -> ItineraryItem {
        let start = entry.startTime ?? day.date
        let item = ItineraryItem(title: entry.title, category: entry.category, startTime: start,
                                 endTime: entry.endTime ?? start.addingTimeInterval(3600), sortOrder: entry.sortOrder)
        item.id = entry.sourceItemID ?? entry.id; item.day = day; item.isTimePending = entry.startTime == nil
        item.note = entry.arrangementNote
        item.address = entry.address; item.locationModeRaw = entry.locationModeRaw
        item.placeName = entry.placeName; item.placeAddress = entry.placeAddress
        item.originName = entry.originName; item.originAddress = entry.originAddress
        item.destinationName = entry.destinationName; item.destinationAddress = entry.destinationAddress
        item.transportRaw = entry.transportRaw; item.attractionTypeRaw = entry.attractionTypeRaw
        item.distanceText = entry.routeInfo; item.cost = entry.cost
        return item
    }

    private static func mergeText(_ existing: String, _ incoming: String) -> String {
        guard !incoming.isEmpty, existing != incoming else { return existing }
        return existing.isEmpty ? incoming : existing + "\n\n" + incoming
    }

    private static func mergeMemory(_ entry: StoryEntry, into item: ItineraryItem) {
        if !entry.note.isEmpty && entry.note != item.journalNote {
            item.journalNote = item.journalNote.isEmpty ? entry.note : item.journalNote + "\n\n" + entry.note
        }
        item.journalSupplement = mergeText(item.journalSupplement, entry.supplementalInfo)
        var existing = Set(item.media.map(\.id))
        for media in entry.legacyMedia.sorted(by: MediaReference.precedes) where !existing.contains(media.id) {
            media.sortOrder = (item.media.map(\.sortOrder).max() ?? -1) + 1
            media.itineraryItem = item; item.media.append(media); existing.insert(media.id)
        }
    }
}
