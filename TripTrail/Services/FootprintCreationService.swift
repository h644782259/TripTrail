import Foundation
import SwiftData

@MainActor
enum FootprintCreationService {
    static func create(
        title: String,
        destination: String,
        startDate: Date,
        endDate: Date,
        summary: String,
        modelContext: ModelContext
    ) -> TravelStory {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = max(normalizedStart, calendar.startOfDay(for: endDate))
        let story = TravelStory(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: normalizedStart,
            endDate: normalizedEnd,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let trip = Trip(title: story.title, destination: story.destination,
                        startDate: normalizedStart, endDate: normalizedEnd)
        trip.id = story.id; trip.journalSummary = story.summary
        story.journey = trip; story.sourceTripID = trip.id; story.usesUnifiedJourney = true
        modelContext.insert(trip)
        modelContext.insert(story)

        for seed in JourneyHierarchyService.daySeeds(from: normalizedStart, through: normalizedEnd) {
            let day = StoryDay(
                date: seed.date,
                title: seed.title,
                sortOrder: seed.sortOrder,
                story: story
            )
            let canonicalDay = TripDay(date: seed.date, title: seed.title, sortOrder: seed.sortOrder, trip: trip)
            canonicalDay.id = day.id; trip.days.append(canonicalDay)
            day.journeyDay = canonicalDay; day.sourceDayID = canonicalDay.id; day.usesUnifiedJourney = true
            story.days.append(day)
        }
        return story
    }
}
