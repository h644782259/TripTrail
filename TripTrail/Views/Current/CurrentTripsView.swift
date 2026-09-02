import Combine
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private enum TripHomeSection: String, CaseIterable, Identifiable {
    case current
    case completed

    var id: Self { self }

    var title: String {
        switch self {
        case .current: "进行中/待出发"
        case .completed: "已结束"
        }
    }
}

struct CurrentTripsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Trip.startDate, order: .forward) private var trips: [Trip]
    @State private var showsNewTrip = false
    @State private var tripToEdit: Trip?
    @State private var tripToDelete: Trip?
    @State private var tripToArchive: Trip?
    @State private var tripToShare: Trip?
    @State private var tripForTextImport: Trip?
    @State private var tripForScreenshotImport: Trip?
    @State private var showsWholeTripScreenshotPicker = false
    @State private var wholeTripPickerItems: [PhotosPickerItem] = []
    @State private var wholeTripRetryPickerItems: [PhotosPickerItem] = []
    @State private var wholeTripDraftRequest: WholeTripDraftRequest?
    @State private var wholeTripImportMessage: String?
    @State private var offersPhotoSettingsForWholeTripImport = false
    @State private var isReadingWholeTripScreenshots = false
    @State private var routePlanningRequest: ItineraryRoutePlanningRequest?
    @State private var routePlanningMessage: String?
    @State private var progressReferenceDate = Date()
    @State private var selectedSection = TripHomeSection.current
    private let completionTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                if trips.isEmpty {
                    emptyHero
                    ContentUnavailableView {
                        Label("下一站，去哪里？", systemImage: "suitcase.rolling.fill")
                    } description: {
                        Text("新建旅行，按天安排地点、交通和照片。")
                    } actions: {
                        Button("创建第一段旅程") { showsNewTrip = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(minHeight: 320)
                } else {
                    sectionPicker
                    switch selectedSection {
                    case .current:
                        currentTripsContent
                    case .completed:
                        completedTripsContent
                    }
                }
            }
            .padding()
            .padding(.bottom, 84)
        }
        .background(Color.tripCanvas)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsNewTrip = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showsNewTrip, onDismiss: { completeElapsedItems() }) { TripEditorView() }
        .sheet(item: $tripToEdit, onDismiss: { completeElapsedItems() }) { TripEditorView(trip: $0) }
        .sheet(item: $tripToArchive) { ArchiveTripView(trip: $0) }
        .sheet(item: $tripToShare) { ShareExportView(trip: $0) }
        .sheet(item: $tripForTextImport) {
            TextItineraryImportView(trip: $0, referenceDate: $0.startDate)
        }
        .sheet(item: $wholeTripDraftRequest) { request in
            ScreenshotItineraryImportView(
                trip: request.trip,
                draft: request.draft,
                onRetryRecognition: request.draft.recognitionNotice == nil ? nil : {
                    retryWholeTripScreenshotRecognition()
                }
            )
        }
        .sheet(item: $routePlanningRequest) { AmapRoutePlanningView(request: $0) }
        .photosPicker(
            isPresented: $showsWholeTripScreenshotPicker,
            selection: $wholeTripPickerItems,
            maxSelectionCount: 10,
            selectionBehavior: .ordered,
            matching: .images,
            photoLibrary: .shared()
        )
        .alert(
            HierarchyDeletionCopy.tripTitle,
            isPresented: Binding(
                get: { tripToDelete != nil },
                set: { if !$0 { tripToDelete = nil } }
            ),
            presenting: tripToDelete
        ) { trip in
            Button(HierarchyDeletionCopy.confirmationButtonTitle, role: .destructive) {
                modelContext.delete(trip)
                tripToDelete = nil
            }
            Button(HierarchyDeletionCopy.cancelButtonTitle, role: .cancel) { tripToDelete = nil }
        } message: { trip in
            Text(HierarchyDeletionCopy.tripMessage(title: trip.title))
        }
        .alert("路线规划", isPresented: Binding(
            get: { routePlanningMessage != nil },
            set: { if !$0 { routePlanningMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { routePlanningMessage = nil }
        } message: {
            Text(routePlanningMessage ?? "")
        }
        .alert("录入整段旅程", isPresented: Binding(
            get: { wholeTripImportMessage != nil },
            set: {
                if !$0 {
                    wholeTripImportMessage = nil
                    offersPhotoSettingsForWholeTripImport = false
                }
            }
        )) {
            if !offersPhotoSettingsForWholeTripImport, !wholeTripRetryPickerItems.isEmpty {
                Button("重试") { retryWholeTripScreenshotRecognition() }
            }
            Button("知道了", role: .cancel) {
                wholeTripImportMessage = nil
                offersPhotoSettingsForWholeTripImport = false
            }
            if offersPhotoSettingsForWholeTripImport {
                Button("去设置") {
                    wholeTripImportMessage = nil
                    offersPhotoSettingsForWholeTripImport = false
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text(wholeTripImportMessage ?? "")
        }
        .onChange(of: wholeTripPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await recognizeWholeTripScreenshots(items) }
        }
        .onAppear {
            progressReferenceDate = Date()
            completeElapsedItems(relativeTo: progressReferenceDate)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                progressReferenceDate = Date()
                completeElapsedItems(relativeTo: progressReferenceDate)
            }
        }
        .onReceive(completionTimer) { date in
            progressReferenceDate = date
            completeElapsedItems(relativeTo: date)
        }
    }

    private var orderedTrips: [Trip] {
        TripTimelineOrdering.sorted(trips, relativeTo: progressReferenceDate)
    }

    private var currentTrips: [Trip] {
        orderedTrips.filter {
            TripTimelineOrdering.phase(for: $0, relativeTo: progressReferenceDate) != .history
        }
    }

    private var featuredTrip: Trip? {
        currentTrips.first
    }

    private var remainingCurrentTrips: [Trip] {
        Array(currentTrips.dropFirst())
    }

    private var historyTrips: [Trip] {
        orderedTrips.filter {
            TripTimelineOrdering.phase(for: $0, relativeTo: progressReferenceDate) == .history
        }
    }

    private func completeElapsedItems(relativeTo date: Date = Date()) {
        for day in trips.flatMap(\.days) {
            day.completeElapsedItems(relativeTo: date)
        }
    }

    private var sectionPicker: some View {
        Picker("旅程分类", selection: $selectedSection) {
            ForEach(TripHomeSection.allCases) { section in
                Text("\(section.title) \(tripCount(for: section))")
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("旅程分类")
    }

    @ViewBuilder
    private var currentTripsContent: some View {
        if let featuredTrip {
            tripCard(featuredTrip, isFeatured: true)
            ForEach(remainingCurrentTrips) { trip in
                tripCard(trip)
            }
        } else {
            ContentUnavailableView {
                Label("暂无进行中或待出发的旅程", systemImage: "calendar.badge.plus")
            } description: {
                Text("新建一段旅程，它会按出发日期显示在这里。")
            } actions: {
                Button("新建旅程") { showsNewTrip = true }
                    .buttonStyle(.borderedProminent)
            }
            .frame(minHeight: 320)
        }
    }

    @ViewBuilder
    private var completedTripsContent: some View {
        if historyTrips.isEmpty {
            ContentUnavailableView(
                "还没有已结束的旅程",
                systemImage: "clock.arrow.circlepath",
                description: Text("结束日期已过的旅程会自动出现在这里。")
            )
            .frame(minHeight: 320)
        } else {
            ForEach(historyTrips) { trip in
                tripCard(trip)
            }
        }
    }

    private func tripCount(for section: TripHomeSection) -> Int {
        switch section {
        case .current: currentTrips.count
        case .completed: historyTrips.count
        }
    }

    private func tripCard(_ trip: Trip, isFeatured: Bool = false) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: trip) {
                if isFeatured {
                    FeaturedTripHero(trip: trip, referenceDate: progressReferenceDate)
                } else {
                    TripCard(trip: trip, referenceDate: progressReferenceDate)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开这段旅程")

            Menu {
                Button("编辑旅程", systemImage: "pencil") {
                    tripToEdit = trip
                }
                Button("整理成足迹", systemImage: "book.closed") {
                    tripToArchive = trip
                }
                Button("分享旅程", systemImage: "square.and.arrow.up") {
                    tripToShare = trip
                }
                Menu("智能录入", systemImage: "square.and.arrow.down") {
                    Button("从截图录入", systemImage: "photo.stack") {
                        requestWholeTripScreenshotSelection(for: trip)
                    }
                    Button("从文本录入", systemImage: "text.badge.plus") {
                        tripForTextImport = trip
                    }
                }
                .disabled(isReadingWholeTripScreenshots)
                Button("规划全行程路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                    requestRoutePlanning(for: trip)
                }
                Divider()
                Button("删除旅程", systemImage: "trash", role: .destructive) {
                    tripToDelete = trip
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.tripInk.opacity(0.72))
            .padding(12)
            .accessibilityLabel("\(trip.title)更多操作")
        }
    }

    private func requestRoutePlanning(for trip: Trip) {
        let points = ItineraryRoutePlanning.points(in: trip.sortedDays)
        let missingLocationCount = trip.allItems.filter { $0.locationTargets.isEmpty }.count
        guard points.count >= 2 else {
            routePlanningMessage = "至少需要两个已填写地点，才能生成高德地图路线规划。"
            return
        }
        routePlanningRequest = ItineraryRoutePlanningRequest(
            title: "\(trip.title)全行程路线",
            points: points,
            missingLocationCount: missingLocationCount
        )
    }

    private func requestWholeTripScreenshotSelection(for trip: Trip) {
        Task { @MainActor in
            let authorization = await PhotoLibraryService.requestReadWriteAccessIfNeeded()
            if authorization == .authorized || authorization == .limited {
                tripForScreenshotImport = trip
                showsWholeTripScreenshotPicker = true
            } else {
                offersPhotoSettingsForWholeTripImport = authorization == .denied || authorization == .restricted
                wholeTripImportMessage = PhotoLibraryService.permissionGuidance
            }
        }
    }

    @MainActor
    private func recognizeWholeTripScreenshots(_ items: [PhotosPickerItem]) async {
        guard let trip = tripForScreenshotImport else { return }
        isReadingWholeTripScreenshots = true
        defer {
            isReadingWholeTripScreenshots = false
            wholeTripPickerItems = []
        }
        do {
            var imageDatas: [Data] = []
            var assetIdentifiers: [String] = []
            for item in items {
                if let data = try await item.loadTransferable(type: Data.self) {
                    imageDatas.append(data)
                    if let identifier = item.itemIdentifier { assetIdentifiers.append(identifier) }
                }
            }
            guard !imageDatas.isEmpty else {
                throw ScreenshotItineraryImportError.unreadableImage
            }
            let draft = try await SmartItineraryRecognitionService.recognizeJourney(
                imageDatas: imageDatas,
                referenceDate: trip.startDate,
                sourceAssetIdentifiers: assetIdentifiers
            )
            wholeTripRetryPickerItems = draft.recognitionNotice == nil ? [] : items
            wholeTripDraftRequest = WholeTripDraftRequest(trip: trip, draft: draft)
        } catch {
            wholeTripRetryPickerItems = items
            wholeTripImportMessage = error.localizedDescription
        }
    }

    private func retryWholeTripScreenshotRecognition() {
        let items = wholeTripRetryPickerItems
        guard !items.isEmpty, !isReadingWholeTripScreenshots else { return }
        wholeTripImportMessage = nil
        offersPhotoSettingsForWholeTripImport = false
        wholeTripDraftRequest = nil
        Task { await recognizeWholeTripScreenshots(items) }
    }

    private var emptyHero: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("把期待排进日历")
                    .font(.title2.bold())
                Text("路线、照片和回忆，都在一处。")
                    .font(.subheadline)
                    .foregroundStyle(Color.tripInk.opacity(0.66))
            }
            Spacer()
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(Color.tripLake)
        }
        .foregroundStyle(Color.tripInk)
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background { journeyBackground }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.tripMist.opacity(0.46), lineWidth: 0.8)
        }
        .shadow(color: Color.tripInk.opacity(0.07), radius: 18, y: 8)
    }

    private var journeyBackground: some View {
        Image("JourneyLakeHero")
            .resizable()
            .scaledToFill()
            .overlay(Color.white.opacity(0.06))
    }
}

private struct WholeTripDraftRequest: Identifiable {
    let id = UUID()
    let trip: Trip
    let draft: ItineraryJourneyDraft
}

private struct FeaturedTripHero: View {
    let trip: Trip
    let referenceDate: Date

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: referenceDate) }
    private var startDate: Date { calendar.startOfDay(for: trip.startDate) }
    private var phase: TripTimelinePhase {
        TripTimelineOrdering.phase(for: trip, relativeTo: referenceDate, calendar: calendar)
    }
    private var dayProgress: TripCalendarProgress {
        TripCalendarProgress.make(for: trip, relativeTo: referenceDate, calendar: calendar)
    }
    private var todayItems: [ItineraryItem] {
        trip.sortedDays
            .first { calendar.isDate($0.date, inSameDayAs: referenceDate) }?
            .sortedItems ?? []
    }
    private var completedTodayCount: Int {
        todayItems.filter { $0.executionStatus == .completed }.count
    }
    private var todayProgressFraction: Double {
        guard !todayItems.isEmpty else { return 0 }
        return Double(completedTodayCount) / Double(todayItems.count)
    }
    private var currentArrangement: ItineraryItem? {
        todayItems.first { $0.executionStatus == .inProgress }
    }
    private var nextArrangement: ItineraryItem? {
        guard let currentArrangement,
              let currentIndex = todayItems.firstIndex(where: { $0.id == currentArrangement.id }) else {
            return todayItems.first { $0.executionStatus == .notStarted }
        }
        return todayItems.dropFirst(currentIndex + 1).first { $0.executionStatus == .notStarted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Label(eyebrowText, systemImage: phase == .current ? "location.fill" : "calendar.badge.clock")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.tripLakeText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.72), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.tripLake.opacity(0.30), lineWidth: 0.8)
                        }

                    Text(trip.title)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.tripInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)

                    if let destinationText {
                        Label(destinationText, systemImage: "mappin.and.ellipse")
                            .lineLimit(1)
                    }

                    Label(dateRangeText, systemImage: "calendar")
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(Color.tripInk.opacity(0.68))
                .frame(maxWidth: .infinity, alignment: .leading)

                progressRing
                    .padding(.top, 38)
            }

            if !trip.note.isEmpty {
                Text(trip.note)
                    .font(.subheadline)
                    .foregroundStyle(Color.tripInk.opacity(0.72))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if phase == .current {
                todayScheduleSummary
            }
        }
        .padding(phase == .current ? 22 : 20)
        .padding(.trailing, 4)
        .frame(
            maxWidth: .infinity,
            minHeight: phase == .current ? 252 : 192,
            alignment: .topLeading
        )
        .background {
            ZStack {
                Image("JourneyLakeHero")
                    .resizable()
                    .scaledToFill()

                if phase == .current {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.42),
                            .init(color: Color.white.opacity(0.38), location: 0.68),
                            .init(color: Color.white.opacity(0.88), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    phase == .current ? Color.tripLake.opacity(0.58) : Color.tripMist.opacity(0.48),
                    lineWidth: phase == .current ? 1.5 : 0.8
                )
        }
        .shadow(
            color: phase == .current ? Color.tripLake.opacity(0.18) : Color.tripInk.opacity(0.08),
            radius: phase == .current ? 22 : 18,
            y: phase == .current ? 10 : 8
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibilityText)
    }

    private var todayScheduleSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color.tripLake.opacity(0.26))
                .frame(height: 1)
                .padding(.bottom, 4)

            HStack(spacing: 8) {
                Label("今日安排", systemImage: "list.bullet.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.tripInk)

                Spacer()

                Text(todayProgressText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.tripLakeText)
            }

            ProgressView(value: todayProgressFraction)
                .tint(Color.tripLake)

            scheduleLine(title: "正在进行", item: currentArrangement)
            scheduleLine(title: "接下来", item: nextArrangement)
        }
        .padding(.top, 2)
    }

    private func scheduleLine(title: String, item: ItineraryItem?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(title)：")
                .fontWeight(.semibold)
                .foregroundStyle(Color.tripInk.opacity(0.82))
            Text(arrangementTitle(item))
                .fontWeight(item == nil ? .medium : .bold)
                .foregroundStyle(item == nil ? Color.tripInk.opacity(0.62) : Color.tripInk)
                .lineLimit(1)
        }
        .font(.caption)
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)

            Circle()
                .stroke(Color.tripLake.opacity(0.24), lineWidth: 7)

            Circle()
                .trim(from: 0, to: ringFraction)
                .stroke(
                    Color.tripLake,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: -1) {
                Text(ringCaption)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.tripInk.opacity(0.62))
                Text(ringValue)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.tripInk)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
            }
        }
        .frame(width: 80, height: 80)
        .shadow(color: Color.tripInk.opacity(0.08), radius: 8, y: 3)
        .accessibilityHidden(true)
    }

    private var eyebrowText: String {
        startDate > today ? "下一段旅程" : "当前旅程"
    }

    private var destinationText: String? {
        let destination = trip.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trip.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty, destination.localizedCaseInsensitiveCompare(title) != .orderedSame else {
            return nil
        }
        return destination
    }

    private var dateRangeText: String {
        "\(trip.startDate.compactDayText) — \(trip.endDate.compactDayText)"
    }

    private var daysUntilDeparture: Int {
        max(1, calendar.dateComponents([.day], from: today, to: startDate).day ?? 1)
    }

    private var ringFraction: Double {
        phase == .upcoming ? 0 : dayProgress.fraction
    }

    private var ringCaption: String {
        phase == .upcoming ? "还有" : "第 \(dayProgress.currentDay) 天"
    }

    private var ringValue: String {
        phase == .upcoming ? "\(daysUntilDeparture) 天" : "\(dayProgress.currentDay)/\(dayProgress.totalDays)"
    }

    private var ringAccessibilityText: String {
        if phase == .upcoming {
            return daysUntilDeparture == 1 ? "明天出发" : "还有 \(daysUntilDeparture) 天出发"
        }
        return "旅程进度，第 \(dayProgress.currentDay) 天，共 \(dayProgress.totalDays) 天"
    }

    private func arrangementTitle(_ item: ItineraryItem?) -> String {
        guard let item else { return "暂无" }
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "未命名安排" : title
    }

    private var todayProgressText: String {
        todayItems.isEmpty ? "暂无安排" : "\(completedTodayCount)/\(todayItems.count) 已完成"
    }

    private var todayScheduleAccessibilityText: String? {
        guard phase == .current else { return nil }
        return "今日安排，已完成 \(completedTodayCount) 项，共 \(todayItems.count) 项，正在进行：\(arrangementTitle(currentArrangement))，接下来：\(arrangementTitle(nextArrangement))"
    }

    private var heroAccessibilityText: String {
        [
            eyebrowText,
            trip.title,
            destinationText,
            dateRangeText,
            ringAccessibilityText,
            todayScheduleAccessibilityText,
            trip.note.isEmpty ? nil : trip.note
        ]
        .compactMap { $0 }
        .joined(separator: "，")
    }
}

private struct TripCard: View {
    let trip: Trip
    let referenceDate: Date

    private var phase: TripTimelinePhase {
        TripTimelineOrdering.phase(for: trip, relativeTo: referenceDate)
    }

    private var dayProgress: TripCalendarProgress {
        TripCalendarProgress.make(for: trip, relativeTo: referenceDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(trip.title).font(.title3.bold()).foregroundStyle(.primary)
                    Label(trip.destination.isEmpty ? "待确定目的地" : trip.destination, systemImage: "mappin.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 48)
                Text(statusText)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(statusColor)
                    .background(statusColor.opacity(0.12), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(statusColor.opacity(0.16), lineWidth: 0.7)
                    }
            }
            .padding(.trailing, 42)
            HStack {
                Label("\(trip.startDate.compactDayText) — \(trip.endDate.compactDayText)", systemImage: "calendar")
                Spacer()
                Text(calendarProgressText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !trip.note.isEmpty {
                Text(trip.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(phase == .upcoming ? 1 : 2)
            }

            if phase != .upcoming {
                HStack {
                    Text("旅程进度")
                    Spacer()
                    Text("\(trip.completedCount)/\(trip.totalCount) 项安排已完成")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ProgressView(value: dayProgress.fraction)
                    .tint(statusColor)
            }
        }
        .padding(18)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: cardGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(statusColor.opacity(0.08))
                    .frame(width: 150, height: 150)
                    .blur(radius: 24)
                    .offset(x: 50, y: -78)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [statusColor.opacity(0.82), statusColor.opacity(0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 48)
                .padding(.leading, 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 0.9)
        }
        .shadow(color: Color.tripInk.opacity(0.045), radius: 5, y: 2)
        .shadow(color: statusColor.opacity(0.08), radius: 18, y: 9)
    }

    private var calendarProgressText: String {
        switch dayProgress.phase {
        case .current:
            return "第 \(dayProgress.currentDay)/\(dayProgress.totalDays) 天"
        case .upcoming:
            return "共 \(dayProgress.totalDays) 天"
        case .history:
            return "已走完 \(dayProgress.totalDays) 天"
        }
    }

    private var statusText: String {
        switch phase {
        case .current:
            return "旅行中"
        case .upcoming:
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: referenceDate)
            let startDate = calendar.startOfDay(for: trip.startDate)
            let days = max(1, calendar.dateComponents([.day], from: today, to: startDate).day ?? 1)
            return "\(days)天后出发"
        case .history:
            return "已结束"
        }
    }

    private var statusColor: Color {
        switch phase {
        case .current:
            return Color.tripSage
        case .upcoming:
            return Color.tripLake
        case .history:
            return Color.secondary
        }
    }

    private var cardGradientColors: [Color] {
        switch phase {
        case .current:
            return [
                Color.tripMist.opacity(0.30),
                Color.tripSurface,
                Color.tripSand.opacity(0.13)
            ]
        case .upcoming:
            return [
                Color.tripLake.opacity(0.13),
                Color.tripSurface,
                Color.tripMist.opacity(0.18)
            ]
        case .history:
            return [
                Color.tripItemSurface.opacity(0.88),
                Color.tripSurface,
                Color.tripSand.opacity(0.07)
            ]
        }
    }

    private var cardBorderColor: Color {
        switch phase {
        case .current, .upcoming:
            return statusColor.opacity(0.20)
        case .history:
            return Color.tripMist.opacity(0.28)
        }
    }
}

struct TripEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let trip: Trip?
    @State private var title: String
    @State private var destination: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var note: String

    init(trip: Trip? = nil) {
        self.trip = trip
        _title = State(initialValue: trip?.title ?? "")
        _destination = State(initialValue: trip?.destination ?? "")
        _startDate = State(initialValue: trip?.startDate ?? Date())
        _endDate = State(initialValue: trip?.endDate ?? Calendar.current.date(byAdding: .day, value: 2, to: Date())!)
        _note = State(initialValue: trip?.note ?? "")
    }

    var body: some View {
        TripNavigationStack {
            Form {
                Section("这次旅行") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("旅程名称")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("例如：初秋杭州三日", text: $title)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("目的地")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("例如：杭州", text: $destination)
                    }
                    .padding(.vertical, 4)

                    TwoTapDateRangePicker(
                        title: "旅行日期",
                        startTitle: "出发",
                        endTitle: "返程",
                        startDate: startDateSelection,
                        endDate: $endDate
                    )
                }
                Section("备注") {
                    TextField("同行人、旅行主题或准备事项", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(trip == nil ? "新建旅程" : "编辑旅程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var startDateSelection: Binding<Date> {
        Binding(
            get: { startDate },
            set: { newStartDate in
                let shiftedEndDate = JourneyHierarchyService.shiftedDate(
                    endDate,
                    whenTripStartMovesFrom: startDate,
                    to: newStartDate
                )
                startDate = newStartDate
                endDate = max(newStartDate, shiftedEndDate)
            }
        )
    }

    private func save() {
        let calendar = Calendar.current
        if let trip {
            let normalizedStartDate = calendar.startOfDay(for: startDate)
            JourneyHierarchyService.updateTripDateRange(
                trip,
                startDate: normalizedStartDate,
                endDate: endDate,
                calendar: calendar
            )
            trip.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            trip.destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            trip.note = note
        } else {
            let newTrip = Trip(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: calendar.startOfDay(for: startDate),
                endDate: calendar.startOfDay(for: endDate),
                note: note
            )
            modelContext.insert(newTrip)
            for seed in JourneyHierarchyService.daySeeds(from: startDate, through: endDate, calendar: calendar) {
                let day = TripDay(
                    date: seed.date,
                    title: seed.title,
                    sortOrder: seed.sortOrder,
                    trip: newTrip
                )
                newTrip.days.append(day)
            }
        }
        dismiss()
    }
}
