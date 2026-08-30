import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var incomingSharedJourney: IncomingSharedJourney?
    @State private var openFileError: String?

    var body: some View {
        TabView {
            NavigationStack { CurrentTripsView() }
                .tabItem { Label("行程", systemImage: "map.fill") }

            NavigationStack { StoriesView() }
                .tabItem { Label("足迹", systemImage: "book.closed.fill") }

            NavigationStack { SettingsView() }
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .installsKeyboardDismissal()
        .onOpenURL(perform: openSharedJourney)
        .task {
            #if DEBUG
            await DebugSampleDataService.prepareIfNeeded(in: modelContext)
            #endif
        }
        .sheet(item: $incomingSharedJourney) { incoming in
            SharedJourneyImportView(incoming: incoming)
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
            let preview = try SharedJourneyService.preview(at: copy)
            incomingSharedJourney = IncomingSharedJourney(fileURL: copy, preview: preview)
        } catch {
            openFileError = error.localizedDescription
        }
    }
}
