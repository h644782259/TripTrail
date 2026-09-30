import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var trips: [Trip]
    @State private var selectedTab = "trip"
    @State private var incomingSharedJourney: IncomingSharedJourney?
    @State private var openFileError: String?
    @State private var incomingFiles = TemporaryFileOwner()

    var body: some View {
        TabView(selection: $selectedTab) {
            TripNavigationStack { CurrentTripsView() }
                .tabItem { Label("旅程", systemImage: "map.fill") }
                .tag("trip")

            TripNavigationStack { StoriesView() }
                .tabItem { Label("足迹", systemImage: "book.closed.fill") }
                .tag("story")

            TripNavigationStack { FavoritesView() }
                .tabItem { Label("收藏", systemImage: "heart.fill") }
                .tag("favorite")

            TripNavigationStack { SettingsView() }
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag("settings")
        }
        .tint(Color.tripLakeText)
        .toolbarBackground(Color.tripSurface.opacity(0.97), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .installsKeyboardDismissal()
        .task(id: selectedTab) {
            await CloudSyncService.shared.uploadPending(context: modelContext)
            guard selectedTab != "settings" else { return }
            await CloudSyncService.shared.sync(context: modelContext, kind: selectedTab, automatic: true)
        }
        .task(id: trips.map { "\($0.id):\($0.endDate.timeIntervalSince1970)" }.joined(separator: ",")) {
            await CloudSyncService.shared.archiveFinishedTrips(context: modelContext)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await CloudSyncService.shared.archiveFinishedTrips(context: modelContext)
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { break }
            }
        }
        .onOpenURL(perform: openSharedJourney)
        .task {
            if PhotoLibraryService.status == .notDetermined {
                _ = await PhotoLibraryService.requestReadWriteAccess()
            }
        }
        .sheet(item: $incomingSharedJourney) { incoming in
            SharedJourneyImportView(incoming: incoming)
                .onDisappear { incomingFiles.remove(incoming.fileURL) }
        }
        .alert("无法打开分享", isPresented: Binding(get: { openFileError != nil }, set: { if !$0 { openFileError = nil } })) {
            Button("好", role: .cancel) { openFileError = nil }
        } message: {
            Text(openFileError ?? "")
        }
    }

    private func openSharedJourney(_ url: URL) {
        guard url.pathExtension.lowercased() == "triptrail" else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let copy = try PortablePackageService.temporaryCopy(of: url, extension: "triptrail")
            incomingFiles.keep(copy)
            let preview: SharedJourneyPreview
            do { preview = try SharedJourneyService.preview(at: copy) }
            catch { incomingFiles.remove(copy); throw error }
            incomingSharedJourney = IncomingSharedJourney(fileURL: copy, preview: preview)
        } catch {
            openFileError = error.localizedDescription
        }
    }
}
