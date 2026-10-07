import SwiftData
import SwiftUI

@main
struct TripTrailApp: App {
    private let modelContainer: ModelContainer = {

        TemporaryFileOwner.cleanPreviousSession()
        let schema = Schema([
            Trip.self,
            TripDay.self,
            ItineraryItem.self,
            MediaReference.self,
            TravelStory.self,
            StoryDay.self,
            StoryEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            try UnifiedJourneyService.prepareStoreBackup()
            let container = try ModelContainer(for: schema, configurations: [configuration])
            try UnifiedJourneyService.reconcile(context: container.mainContext)
            return container
        } catch {
            fatalError("无法创建本地旅行数据库：\(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .modifier(TripTabletReading())
                .tint(.tripLake)
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
    }
}
