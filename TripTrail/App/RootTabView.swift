import SwiftUI
import SwiftData
import Network

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var trips: [Trip]
    @StateObject private var connectivity = CloudConnectivity()
    @State private var selectedTab = "trip"
    @State private var incomingSharedJourney: IncomingSharedJourney?
    @State private var openFileError: String?
    @State private var incomingFiles = TemporaryFileOwner()

    var body: some View {
        TabView(selection: $selectedTab) {
            TripNavigationStack { CurrentTripsView() }
                .tabItem { Label("旅程", systemImage: "map.fill") }
                .tag("trip")
                .environment(\.horizontalSizeClass, horizontalSizeClass)
                .toolbar(UIDevice.current.userInterfaceIdiom == .pad ? .hidden : .visible, for: .tabBar)

            TripNavigationStack { StoriesView() }
                .tabItem { Label("足迹", systemImage: "book.closed.fill") }
                .tag("story")
                .environment(\.horizontalSizeClass, horizontalSizeClass)
                .toolbar(UIDevice.current.userInterfaceIdiom == .pad ? .hidden : .visible, for: .tabBar)

            TripNavigationStack { FavoritesView() }
                .tabItem { Label("收藏", systemImage: "heart.fill") }
                .tag("favorite")
                .environment(\.horizontalSizeClass, horizontalSizeClass)
                .toolbar(UIDevice.current.userInterfaceIdiom == .pad ? .hidden : .visible, for: .tabBar)

            TripNavigationStack { SettingsView() }
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag("settings")
                .environment(\.horizontalSizeClass, horizontalSizeClass)
                .toolbar(UIDevice.current.userInterfaceIdiom == .pad ? .hidden : .visible, for: .tabBar)
        }
        .safeAreaInset(edge: .top, spacing: 0) { CloudVersionNotice(kind: selectedTab == "story" ? "trip" : selectedTab) }
        .tint(Color.tripLakeText)
        .environment(\.horizontalSizeClass,
            UIDevice.current.userInterfaceIdiom == .pad ? .compact : horizontalSizeClass)
        .toolbar(UIDevice.current.userInterfaceIdiom == .pad ? .hidden : .visible, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if UIDevice.current.userInterfaceIdiom == .pad {
                HStack(spacing: 4) {
                    tabletTab("旅程", symbol: "map.fill", value: "trip")
                    tabletTab("足迹", symbol: "book.closed.fill", value: "story")
                    tabletTab("收藏", symbol: "heart.fill", value: "favorite")
                    tabletTab("我的", symbol: "person.crop.circle.fill", value: "settings")
                }
                .padding(6)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.tripSurface.opacity(0.9), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 3)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .toolbarBackground(Color.tripSurface.opacity(0.97), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .installsKeyboardDismissal()
        .task(id: connectivity.generation) {
            guard connectivity.online, scenePhase == .active, selectedTab != "settings" else { return }
            await CloudSyncService.shared.sync(context: modelContext, kind: selectedTab == "story" ? "trip" : selectedTab)
        }
        .task(id: selectedTab) {
            guard selectedTab != "settings" else { return }
            await CloudSyncService.shared.sync(context: modelContext, kind: selectedTab == "story" ? "trip" : selectedTab, automatic: true)
        }
        .task(id: trips.map { "\($0.id):\($0.startDate.timeIntervalSince1970):\($0.endDate.timeIntervalSince1970)" }.joined(separator: ",")) {
            await CloudSyncService.shared.refreshUnifiedJourneys(context: modelContext)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if selectedTab != "settings" { await CloudSyncService.shared.sync(context: modelContext, kind: selectedTab == "story" ? "trip" : selectedTab) }
            await CloudSyncService.shared.refreshUnifiedJourneys(context: modelContext)
        }
        .task(id: "\(scenePhase)-\(selectedTab)-\(connectivity.online)") {
            guard scenePhase == .active, connectivity.online, selectedTab != "settings" else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await CloudSyncService.shared.sync(context: modelContext, kind: selectedTab == "story" ? "trip" : selectedTab, automatic: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            guard scenePhase == .active else { return }
            Task { await CloudSyncService.shared.refreshUnifiedJourneys(context: modelContext) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            guard scenePhase == .active else { return }
            Task { await CloudSyncService.shared.refreshUnifiedJourneys(context: modelContext) }
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

    private func tabletTab(_ title: String, symbol: String, value: String) -> some View {
        Button { selectedTab = value } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 28, weight: .semibold))
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(selectedTab == value ? Color.tripLakeText : Color.tripInk)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(selectedTab == value ? Color.tripInk.opacity(0.07) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == value ? [.isSelected] : [])
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

@MainActor
private final class CloudConnectivity: ObservableObject {
    @Published var generation = 0
    private(set) var online = false
    private let monitor = NWPathMonitor()
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let restored = connected && !self.online
                self.online = connected
                if restored { self.generation += 1 }
            }
        }
        monitor.start(queue: DispatchQueue(label: "TripTrail.cloud-connectivity"))
    }
    deinit { monitor.cancel() }
}
