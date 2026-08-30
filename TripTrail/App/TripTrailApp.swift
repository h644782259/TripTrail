import SwiftData
import SwiftUI

@main
struct TripTrailApp: App {
    private let modelContainer: ModelContainer = {
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
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法创建本地旅行数据库：\(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(.tripLake)
        }
        .modelContainer(modelContainer)
    }
}
