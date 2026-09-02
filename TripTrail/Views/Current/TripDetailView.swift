import Combine
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var trip: Trip
    @State private var dayForNewItem: TripDay?
    @State private var dayForTextItemImport: TripDay?
    @State private var dayForImageItemImport: TripDay?
    @State private var dayForFavoriteImport: TripDay?
    @State private var itemToEdit: ItineraryItem?
    @State private var dayToEdit: TripDay?
    @State private var dayToDelete: TripDay?
    @State private var itemToDelete: ItineraryItem?
    @State private var shareRequest: TripShareRequest?
    @State private var routePlanningRequest: ItineraryRoutePlanningRequest?
    @State private var placeMessage: String?
    @State private var navigationRequest: ItineraryNavigationRequest?
    @State private var timeReviewRequest: ItineraryTimeReviewRequest?
    @State private var showsScreenshotPicker = false
    @State private var screenshotPickerItems: [PhotosPickerItem] = []
    @State private var retryScreenshotPickerItems: [PhotosPickerItem] = []
    @State private var screenshotDraft: ItineraryJourneyDraft?
    @State private var showsTextImport = false
    @State private var screenshotImportMessage: String?
    @State private var offersPhotoSettingsForScreenshot = false
    @State private var isReadingScreenshot = false
    @State private var selectedDayID: UUID?
    @State private var itineraryDrag: ItineraryDragState?
    @State private var itineraryDragRevision = 0
    @State private var dayDrag: TripDayDragState?
    @State private var dayDragRevision = 0
    @State private var dragCleanupTask: Task<Void, Never>?
    @State private var progressReferenceDate = Date()
    private let completionTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        lifecycleContent
    }

    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                selectedDayHeader
                itineraryDays
            }
            .padding()
            .padding(.bottom, 84)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            dayNavigator
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.tripCanvas)
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let selection = selectedDaySelection {
                        let day = selection.day
                        Button("编辑当天", systemImage: "pencil") {
                            dayToEdit = day
                        }
                        Menu("录入当天", systemImage: "calendar.badge.plus") {
                            Button("文字录入", systemImage: "text.badge.plus") {
                                showsTextImport = true
                            }
                            Button("图片录入", systemImage: "photo.stack") {
                                requestScreenshotSelection()
                            }
                        }
                        .disabled(isReadingScreenshot)
                        Button("分享当天", systemImage: "square.and.arrow.up") {
                            shareRequest = TripShareRequest(scopeID: day.id)
                        }
                        Button("规划当天路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                            requestRoutePlanning(
                                for: [day],
                                title: "\(displayTitle(for: day))路线"
                            )
                        }
                        Divider()
                        Button("删除当天", systemImage: "trash", role: .destructive) {
                            dayToDelete = day
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("当天更多操作")
            }
        }
    }

    private var sheetContent: some View {
        mainContent
        .sheet(item: $dayForNewItem) { ItemEditorView(day: $0) }
        .sheet(item: $dayForTextItemImport) {
            ItemEditorView(
                day: $0,
                startsWithSmartImport: true,
                initialSmartImportMode: .text
            )
        }
        .sheet(item: $dayForImageItemImport) {
            ItemEditorView(
                day: $0,
                startsWithSmartImport: true,
                initialSmartImportMode: .image
            )
        }
        .sheet(item: $dayForFavoriteImport) { FavoriteImportSelectionView(day: $0) }
        .sheet(item: $itemToEdit) { ItemEditorView(day: $0.day, item: $0) }
        .sheet(item: $dayToEdit, onDismiss: {
            JourneyHierarchyService.normalizeTripDaySchedule(trip)
            completeElapsedItems()
        }) { DayEditorView(day: $0) }
        .sheet(item: $timeReviewRequest) { ItineraryTimeReviewView(request: $0) }
        .sheet(item: $screenshotDraft) { draft in
            ScreenshotItineraryImportView(
                trip: trip,
                draft: draft,
                targetDay: selectedDaySelection?.day,
                onRetryRecognition: draft.recognitionNotice == nil ? nil : {
                    retryScreenshotRecognition()
                }
            )
        }
        .sheet(isPresented: $showsTextImport) {
            TextItineraryImportView(
                trip: trip,
                referenceDate: selectedDaySelection?.day.date ?? trip.startDate,
                targetDay: selectedDaySelection?.day
            )
        }
        .sheet(item: $shareRequest) { request in
            ShareExportView(trip: trip, initialScopeID: request.scopeID)
        }
        .sheet(item: $routePlanningRequest) { request in
            AmapRoutePlanningView(request: request)
        }
        .sheet(item: $navigationRequest) { request in
            NavigationOptionsSheet(
                onAmap: { open(request) },
                onXiaohongshu: { openDiscovery(.xiaohongshu, for: request) },
                onDouyin: { openDiscovery(.douyin, for: request) }
            )
        }
    }

    private var recognitionFeedbackContent: some View {
        sheetContent
        .photosPicker(
            isPresented: $showsScreenshotPicker,
            selection: $screenshotPickerItems,
            maxSelectionCount: 10,
            selectionBehavior: .ordered,
            matching: .images,
            photoLibrary: .shared()
        )
        .alert("地点提示", isPresented: Binding(get: { placeMessage != nil }, set: { if !$0 { placeMessage = nil } })) {
            Button("知道了", role: .cancel) { placeMessage = nil }
        } message: {
            Text(placeMessage ?? "")
        }
        .alert("截图识别", isPresented: Binding(
            get: { screenshotImportMessage != nil },
            set: {
                if !$0 {
                    screenshotImportMessage = nil
                    offersPhotoSettingsForScreenshot = false
                }
            }
        )) {
            if !offersPhotoSettingsForScreenshot, !retryScreenshotPickerItems.isEmpty {
                Button("重试") {
                    retryScreenshotRecognition()
                }
            }
            Button("知道了", role: .cancel) {
                screenshotImportMessage = nil
                offersPhotoSettingsForScreenshot = false
            }
            if offersPhotoSettingsForScreenshot {
                Button("去设置") {
                    screenshotImportMessage = nil
                    offersPhotoSettingsForScreenshot = false
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text(screenshotImportMessage ?? "")
        }
    }

    private var deletionConfirmationContent: some View {
        recognitionFeedbackContent
        .alert(
            HierarchyDeletionCopy.tripDayTitle,
            isPresented: Binding(
                get: { dayToDelete != nil },
                set: { if !$0 { dayToDelete = nil } }
            ),
            presenting: dayToDelete
        ) { day in
            Button(HierarchyDeletionCopy.confirmationButtonTitle, role: .destructive) {
                deleteDay(day)
                dayToDelete = nil
            }
            Button(HierarchyDeletionCopy.cancelButtonTitle, role: .cancel) { dayToDelete = nil }
        } message: { day in
            Text(HierarchyDeletionCopy.tripDayMessage(title: displayTitle(for: day)))
        }
        .alert(
            HierarchyDeletionCopy.itineraryItemTitle,
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            ),
            presenting: itemToDelete
        ) { item in
            Button(HierarchyDeletionCopy.confirmationButtonTitle, role: .destructive) {
                modelContext.delete(item)
                itemToDelete = nil
            }
            Button(HierarchyDeletionCopy.cancelButtonTitle, role: .cancel) { itemToDelete = nil }
        } message: { item in
            Text(HierarchyDeletionCopy.itineraryItemMessage(title: item.title))
        }
    }

    private var lifecycleContent: some View {
        deletionConfirmationContent
        .onChange(of: screenshotPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await recognizeScreenshots(items) }
        }
        .onAppear {
            JourneyHierarchyService.normalizeTripDaySchedule(trip)
            progressReferenceDate = Date()
            completeElapsedItems(relativeTo: progressReferenceDate)
            ensureSelectedDay()
        }
        .onChange(of: trip.sortedDays.map(\.id)) { _, _ in
            ensureSelectedDay()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                progressReferenceDate = Date()
                completeElapsedItems(relativeTo: progressReferenceDate)
            }
        }
        .onChange(of: dayDateSignature) { _, _ in
            completeElapsedItems()
        }
        .onChange(of: itemEndTimeSignature) { _, _ in
            completeElapsedItems()
        }
        .onReceive(completionTimer) { date in
            progressReferenceDate = date
            completeElapsedItems(relativeTo: date)
        }
        .onDisappear { cancelActiveDragIfNeeded() }
    }

    @ViewBuilder
    private var itineraryDays: some View {
        if trip.sortedDays.isEmpty {
            ContentUnavailableView("还没有日程", systemImage: "calendar.badge.plus", description: Text("先添加一天。"))
                .frame(height: 260)
        } else if let selection = selectedDaySelection {
            daySection(selection.day)
                .id(selection.day.id)
        }
    }

    private var selectedDaySelection: (index: Int, day: TripDay)? {
        let days = trip.sortedDays
        guard !days.isEmpty else { return nil }
        if let selectedDayID,
           let index = days.firstIndex(where: { $0.id == selectedDayID }) {
            return (index, days[index])
        }
        return (0, days[0])
    }

    @ViewBuilder
    private var selectedDayHeader: some View {
        if let selection = selectedDaySelection {
            Text(selection.day.title.isEmpty ? "第 \(selection.index + 1) 天" : selection.day.title)
                .font(.title2.bold())
                .foregroundStyle(Color.tripInk)
                .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dayNavigator: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(trip.sortedDays.enumerated()), id: \.element.id) { index, day in
                            dayNavigatorItem(index: index, day: day)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.vertical, 8)
                    .animation(.snappy(duration: 0.22), value: trip.sortedDays.map(\.id))
                    .animation(.snappy(duration: 0.22), value: dayDragRevision)
                }
                .onChange(of: selectedDayID) { _, newID in
                    guard let newID else { return }
                    withAnimation(.snappy(duration: 0.22)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }

            Button {
                addDay()
            } label: {
                Image(systemName: "plus")
                    .font(.headline.bold())
                    .foregroundStyle(Color.tripLake)
                    .frame(width: 42, height: 42)
                    .background(Color.tripSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.tripLake.opacity(0.22), lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添加一天")
            .padding(.trailing, 16)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }

    private func dayNavigatorItem(index: Int, day: TripDay) -> some View {
        let isSelected = selectedDaySelection?.day.id == day.id
        let isDragging = dayDrag?.dayID == day.id

        return Button {
            selectDay(day)
        } label: {
            dayNavigatorPill(index: index, day: day, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .id(day.id)
        // Keep the drag source alive inside the horizontal ScrollView.
        // opacity(0) makes SwiftUI drop its hit-testing during the session.
        .mask {
            Rectangle()
                .fill(isDragging ? Color.clear : Color.white)
        }
        .overlay {
            if isDragging {
                DayNavigatorPlacementPlaceholder()
            }
        }
        .contentShape(Capsule())
        .onDrag {
            beginDayDrag(day)
            return dragItemProvider(payload: "trip-day:\(day.id.uuidString)") {
                cancelDayDragIfNeeded(dayID: day.id)
            }
        } preview: {
            dayNavigatorPill(index: index, day: day, isSelected: true)
                .fixedSize()
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: ItineraryReorderDropDelegate(
                onEntered: {
                    cancelPendingDragCleanup()
                    previewDayDrag(over: day)
                },
                onExited: { scheduleDragCleanup() },
                onDrop: { finishDayDrag(over: day) }
            )
        )
        .accessibilityLabel("第 \(index + 1) 天，\(day.date.chineseDateText)")
        .accessibilityValue(isSelected ? "当前选择" : "")
        .accessibilityHint("长按并左右拖动可调整日期顺序")
    }

    private func dayNavigatorPill(index: Int, day: TripDay, isSelected: Bool) -> some View {
        VStack(spacing: 2) {
            Text("第 \(index + 1) 天")
                .font(.caption2.bold())
            Text(day.date.formatted(.dateTime.month().day()))
                .font(.caption.bold())
        }
        .foregroundStyle(isSelected ? .white : Color.tripInk)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(isSelected ? Color.tripLake : Color.tripSurface, in: Capsule())
        .overlay {
            if !isSelected {
                Capsule().stroke(Color.tripLake.opacity(0.18), lineWidth: 0.8)
            }
        }
    }

    private var dayDateSignature: [Date] {
        trip.sortedDays.map(\.date)
    }

    private var itemEndTimeSignature: [Date] {
        trip.allItems.map(\.endTime)
    }

    private func requestScreenshotSelection() {
        Task { @MainActor in
            let authorization = await PhotoLibraryService.requestReadWriteAccessIfNeeded()
            if authorization == .authorized || authorization == .limited {
                showsScreenshotPicker = true
            } else {
                offersPhotoSettingsForScreenshot = authorization == .denied || authorization == .restricted
                screenshotImportMessage = PhotoLibraryService.permissionGuidance
            }
        }
    }

    @MainActor
    private func recognizeScreenshots(_ items: [PhotosPickerItem]) async {
        isReadingScreenshot = true
        defer {
            isReadingScreenshot = false
            screenshotPickerItems = []
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
            let recognizedDraft = try await SmartItineraryRecognitionService.recognizeJourney(
                imageDatas: imageDatas,
                referenceDate: selectedDaySelection?.day.date ?? trip.startDate,
                sourceAssetIdentifiers: assetIdentifiers
            )
            retryScreenshotPickerItems = recognizedDraft.recognitionNotice == nil ? [] : items
            screenshotDraft = recognizedDraft
        } catch {
            retryScreenshotPickerItems = items
            screenshotImportMessage = error.localizedDescription
        }
    }

    private func retryScreenshotRecognition() {
        let items = retryScreenshotPickerItems
        guard !items.isEmpty, !isReadingScreenshot else { return }
        screenshotImportMessage = nil
        offersPhotoSettingsForScreenshot = false
        screenshotDraft = nil
        Task { await recognizeScreenshots(items) }
    }

    private func daySection(_ day: TripDay) -> some View {
        let displayedItems = day.displayItems

        return VStack(alignment: .leading, spacing: 14) {
            if displayedItems.isEmpty {
                Menu {
                    addArrangementActions(for: day)
                } label: {
                    Label("添加安排", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.tripLake)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.tripLake.opacity(0.09), in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                ForEach(displayedItems) { item in
                    CardSwipeActionContainer(
                        cornerRadius: 16,
                        editTitle: "编辑安排",
                        deleteTitle: "删除安排",
                        onEdit: {
                            itemToEdit = item
                        },
                        onDelete: {
                            itemToDelete = item
                        }
                    ) {
                        ItineraryCard(item: item) {
                            itemToEdit = item
                        } onNavigate: {
                            navigationRequest = ItineraryNavigationRequest(
                                item: item,
                                target: $0
                            )
                        } onDragStart: {
                            beginItineraryDrag(item)
                        } onDragCancel: {
                            cancelItineraryDragIfNeeded(itemID: item.id)
                        }
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.tripSurface)
                        .onDrop(
                            of: [UTType.plainText],
                            delegate: ItineraryReorderDropDelegate(
                                onEntered: {
                                    cancelPendingDragCleanup()
                                    if dayDrag != nil {
                                        previewDayDrag(over: day)
                                    } else {
                                        previewItineraryDrag(over: item)
                                    }
                                },
                                onExited: { scheduleDragCleanup() },
                                onDrop: {
                                    if dayDrag != nil {
                                        finishDayDrag(over: day)
                                    } else {
                                        finishItineraryDrag(at: .item(item.id))
                                    }
                                }
                            )
                        )
                    }
                    // Keep the source visible while the system presents its drag preview.
                    // A cancelled or timed-out drag must never make the card disappear.
                    .opacity(itineraryDrag?.itemID == item.id ? 0.82 : 1)
                    .overlay {
                        if itineraryDrag?.itemID == item.id {
                            DragPlacementPlaceholder(cornerRadius: 16)
                        }
                    }
                }
                .animation(.snappy(duration: 0.22), value: displayedItems.map(\.id))
                .animation(.snappy(duration: 0.22), value: itineraryDragRevision)
                Menu {
                    addArrangementActions(for: day)
                } label: {
                    Label("添加安排", systemImage: "plus")
                }
                .font(.subheadline.bold())
            }
        }
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.plainText],
            delegate: ItineraryReorderDropDelegate(
                onEntered: {
                    cancelPendingDragCleanup()
                    if dayDrag != nil {
                        previewDayDrag(over: day)
                    } else if day.sortedItems.isEmpty {
                        previewItineraryDrag(toEndOf: day)
                    }
                },
                onExited: { scheduleDragCleanup() },
                onDrop: {
                    if dayDrag != nil {
                        finishDayDrag(over: day)
                    } else {
                        finishItineraryDrag(at: .endOfDay(day.id))
                    }
                }
            )
        )
    }

    @ViewBuilder
    private func addArrangementActions(for day: TripDay) -> some View {
        Button("手动", systemImage: "square.and.pencil") {
            dayForNewItem = day
        }
        Button("从收藏导入", systemImage: "heart") {
            dayForFavoriteImport = day
        }
        Button("文字录入", systemImage: "text.badge.plus") {
            dayForTextItemImport = day
        }
        Button("图片录入", systemImage: "photo.stack") {
            dayForImageItemImport = day
        }
    }

    private func displayTitle(for day: TripDay) -> String {
        if !day.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return day.title
        }
        let index = trip.sortedDays.firstIndex { $0.id == day.id } ?? 0
        return "第 \(index + 1) 天"
    }

    private func completeElapsedItems(relativeTo date: Date = Date()) {
        for day in trip.days {
            day.completeElapsedItems(relativeTo: date)
        }
    }

    private func handleMove(_ result: ItineraryMoveResult) -> Bool {
        if !result.timeAdjustments.isEmpty {
            timeReviewRequest = ItineraryTimeReviewRequest(adjustments: result.timeAdjustments)
        }
        return result.didMove
    }

    private func beginDayDrag(_ day: TripDay) {
        cancelPendingDragCleanup()
        if let itineraryDrag {
            restoreItineraryDrag(itineraryDrag)
            self.itineraryDrag = nil
        }
        if let dayDrag {
            restoreDayDrag(dayDrag)
        }
        dayDrag = TripDayDragState(
            dayID: day.id,
            originalDayIDs: trip.sortedDays.map(\.id),
            destinationDayID: nil
        )
    }

    private func previewDayDrag(over day: TripDay) {
        guard var dayDrag, dayDrag.dayID != day.id else { return }
        guard dayDrag.destinationDayID != day.id else { return }

        var didMove = false
        withAnimation(.snappy(duration: 0.22)) {
            didMove = JourneyHierarchyService.previewMoveTripDay(
                id: dayDrag.dayID,
                to: day.id,
                in: trip.days
            )
        }
        guard didMove else { return }
        dayDrag.destinationDayID = day.id
        self.dayDrag = dayDrag
        dayDragRevision &+= 1
    }

    private func finishDayDrag(over day: TripDay) -> Bool {
        guard let dayDrag else { return false }
        cancelPendingDragCleanup()

        if hasOriginalTripDayOrder(dayDrag.originalDayIDs, in: trip.days) {
            withTransaction(Transaction(animation: nil)) {
                restoreDayDrag(dayDrag)
            }
            self.dayDrag = nil
            dayDragRevision &+= 1
            return false
        }

        let committedDayID = resolvedTripDayDropDestination(
            lastPreviewDayID: dayDrag.destinationDayID,
            reportedDayID: day.id
        )
        withTransaction(Transaction(animation: nil)) {
            restoreDayDrag(dayDrag)
        }
        self.dayDrag = nil
        dayDragRevision &+= 1

        guard let plan = JourneyHierarchyService.tripDayScheduleMovePlan(
            id: dayDrag.dayID,
            to: committedDayID,
            in: trip.days
        ) else { return false }
        return commitDayMove(plan, shiftFollowingDays: false)
    }

    @discardableResult
    private func commitDayMove(
        _ plan: TripDayScheduleMovePlan,
        shiftFollowingDays: Bool
    ) -> Bool {
        let calendar = Calendar.current
        var didMove = false
        withTransaction(Transaction(animation: nil)) {
            didMove = JourneyHierarchyService.applyTripDayScheduleMovePlan(
                plan,
                in: trip.days,
                shiftFollowingDays: shiftFollowingDays,
                calendar: calendar
            )
        }
        guard didMove else { return false }
        JourneyHierarchyService.normalizeTripDaySchedule(trip, calendar: calendar)
        completeElapsedItems()
        return true
    }

    private func restoreDayDrag(_ drag: TripDayDragState) {
        let daysByID = Dictionary(uniqueKeysWithValues: trip.days.map { ($0.id, $0) })
        for (index, dayID) in drag.originalDayIDs.enumerated() {
            daysByID[dayID]?.sortOrder = index
        }
    }

    private func cancelDayDragIfNeeded(dayID: UUID) {
        guard let dayDrag, dayDrag.dayID == dayID else { return }
        cancelPendingDragCleanup()
        withTransaction(Transaction(animation: nil)) {
            restoreDayDrag(dayDrag)
        }
        self.dayDrag = nil
        dayDragRevision &+= 1
    }

    private func beginItineraryDrag(_ item: ItineraryItem) {
        cancelPendingDragCleanup()
        if let dayDrag {
            restoreDayDrag(dayDrag)
            self.dayDrag = nil
        }
        if let itineraryDrag {
            restoreItineraryDrag(itineraryDrag)
        }
        guard let sourceDay = trip.days.first(where: { day in day.items.contains(where: { $0.id == item.id }) }) else {
            return
        }
        itineraryDrag = ItineraryDragState(
            itemID: item.id,
            sourceDayID: sourceDay.id,
            originalItemIDsByDay: Dictionary(
                uniqueKeysWithValues: trip.days.map { ($0.id, $0.sortedItems.map(\.id)) }
            ),
            destination: nil
        )
    }

    private func previewItineraryDrag(over targetItem: ItineraryItem) {
        guard var itineraryDrag, itineraryDrag.itemID != targetItem.id else { return }
        let destination = ItineraryDropDestination.item(targetItem.id)
        guard itineraryDrag.destination != destination else { return }

        var didMove = false
        withAnimation(.snappy(duration: 0.22)) {
            didMove = JourneyHierarchyService.previewMoveItineraryItem(
                id: itineraryDrag.itemID,
                to: targetItem.id,
                in: trip.days
            )
        }
        guard didMove else { return }
        itineraryDrag.destination = destination
        self.itineraryDrag = itineraryDrag
        itineraryDragRevision &+= 1
    }

    private func previewItineraryDrag(toEndOf day: TripDay) {
        guard var itineraryDrag else { return }
        let destination = ItineraryDropDestination.endOfDay(day.id)
        guard itineraryDrag.destination != destination else { return }

        var didMove = false
        withAnimation(.snappy(duration: 0.22)) {
            didMove = JourneyHierarchyService.previewMoveItineraryItem(
                id: itineraryDrag.itemID,
                toEndOf: day,
                in: trip.days
            )
        }
        guard didMove else { return }
        itineraryDrag.destination = destination
        self.itineraryDrag = itineraryDrag
        itineraryDragRevision &+= 1
    }

    private func finishItineraryDrag(at destination: ItineraryDropDestination) -> Bool {
        guard let itineraryDrag else { return false }
        cancelPendingDragCleanup()

        if hasOriginalItineraryOrder(
            itineraryDrag.originalItemIDsByDay,
            in: trip.days
        ) {
            withTransaction(Transaction(animation: nil)) {
                restoreItineraryDrag(itineraryDrag)
            }
            self.itineraryDrag = nil
            itineraryDragRevision &+= 1
            return false
        }

        // Reordering the live cards can move the drop view underneath the pointer. In that
        // case SwiftUI reports the dragged card itself (or its parent day) on release. The
        // last preview destination is the stable representation of the position the user saw.
        let committedDestination = resolvedItineraryDropDestination(
            lastPreview: itineraryDrag.destination,
            reported: destination
        )

        var result = ItineraryMoveResult.unchanged
        withTransaction(Transaction(animation: nil)) {
            restoreItineraryDrag(itineraryDrag)
            switch committedDestination {
            case let .item(targetItemID):
                result = JourneyHierarchyService.moveItineraryItemResult(
                    id: itineraryDrag.itemID,
                    to: targetItemID,
                    in: trip.days
                )
            case let .endOfDay(dayID):
                guard let day = trip.days.first(where: { $0.id == dayID }) else { return }
                result = JourneyHierarchyService.moveItineraryItemResult(
                    id: itineraryDrag.itemID,
                    toEndOf: day,
                    in: trip.days
                )
            }
        }
        self.itineraryDrag = nil
        itineraryDragRevision &+= 1
        return handleMove(result)
    }

    private func restoreItineraryDrag(_ drag: ItineraryDragState) {
        let allItems = Dictionary(
            uniqueKeysWithValues: trip.days.flatMap(\.items).map { ($0.id, $0) }
        )
        guard
            let draggedItem = allItems[drag.itemID],
            let sourceDay = trip.days.first(where: { $0.id == drag.sourceDayID })
        else { return }

        for day in trip.days {
            day.items.removeAll { $0.id == drag.itemID }
        }
        draggedItem.day = sourceDay
        sourceDay.items.append(draggedItem)

        for day in trip.days {
            guard let originalIDs = drag.originalItemIDsByDay[day.id] else { continue }
            for (index, itemID) in originalIDs.enumerated() {
                allItems[itemID]?.sortOrder = index
            }
        }
    }

    private func cancelItineraryDragIfNeeded(itemID: UUID) {
        guard let itineraryDrag, itineraryDrag.itemID == itemID else { return }
        cancelPendingDragCleanup()
        withTransaction(Transaction(animation: nil)) {
            restoreItineraryDrag(itineraryDrag)
        }
        self.itineraryDrag = nil
        itineraryDragRevision &+= 1
    }

    private func cancelPendingDragCleanup() {
        dragCleanupTask?.cancel()
        dragCleanupTask = nil
    }

    private func scheduleDragCleanup() {
        cancelPendingDragCleanup()
        dragCleanupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            cancelActiveDragIfNeeded()
        }
    }

    private func cancelActiveDragIfNeeded() {
        cancelPendingDragCleanup()
        if let dayDrag {
            withTransaction(Transaction(animation: nil)) {
                restoreDayDrag(dayDrag)
            }
            self.dayDrag = nil
            dayDragRevision &+= 1
        }
        if let itineraryDrag {
            withTransaction(Transaction(animation: nil)) {
                restoreItineraryDrag(itineraryDrag)
            }
            self.itineraryDrag = nil
            itineraryDragRevision &+= 1
        }
    }

    private func requestRoutePlanning(for days: [TripDay], title: String) {
        let points = ItineraryRoutePlanning.points(in: days)
        let missingLocationCount = days
            .flatMap(\.items)
            .filter { $0.locationTargets.isEmpty }
            .count
        guard points.count >= 2 else {
            placeMessage = "至少需要两个已填写地点，才能生成高德地图路线规划。"
            return
        }
        routePlanningRequest = ItineraryRoutePlanningRequest(
            title: title,
            points: points,
            missingLocationCount: missingLocationCount
        )
    }

    private func open(_ request: ItineraryNavigationRequest) {
        let item = request.item
        Task {
            let result = await AmapService.openPlace(
                name: request.target.name,
                address: request.target.address,
                mode: item.transport
            )
            placeMessage = result.message(destinationName: request.target.displayName)
        }
    }

    private func openDiscovery(_ platform: PlaceDiscoveryPlatform, for request: ItineraryNavigationRequest) {
        Task {
            let opened = await PlaceDiscoveryService.open(
                platform,
                name: request.target.name,
                address: request.target.address
            )
            if !opened {
                placeMessage = "暂时无法打开\(platform.displayName)，请检查网络或稍后重试。"
            }
        }
    }

    private func addDay() {
        let day = JourneyHierarchyService.appendDay(to: trip)
        selectDay(day)
    }

    private func ensureSelectedDay() {
        let days = trip.sortedDays
        guard !days.isEmpty else {
            selectedDayID = nil
            return
        }
        if let selectedDayID, days.contains(where: { $0.id == selectedDayID }) {
            return
        }
        let calendar = Calendar.current
        let preferredDay = days.first {
            calendar.isDate($0.date, inSameDayAs: progressReferenceDate)
        } ?? days[0]
        selectDay(preferredDay)
    }

    private func selectDay(_ day: TripDay) {
        cancelActiveDragIfNeeded()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedDayID = day.id
        }
    }

    private func deleteDay(_ day: TripDay) {
        let days = trip.sortedDays
        if selectedDayID == day.id, let index = days.firstIndex(where: { $0.id == day.id }) {
            let nextDay = days.dropFirst(index + 1).first ?? days.prefix(index).last
            selectedDayID = nextDay?.id
        }
        trip.days.removeAll { $0.id == day.id }
        modelContext.delete(day)
        JourneyHierarchyService.normalizeTripDaySchedule(trip)
    }
}

enum ItineraryDropDestination: Equatable {
    case item(UUID)
    case endOfDay(UUID)
}

func resolvedItineraryDropDestination(
    lastPreview: ItineraryDropDestination?,
    reported: ItineraryDropDestination
) -> ItineraryDropDestination {
    lastPreview ?? reported
}

func hasOriginalItineraryOrder(
    _ originalItemIDsByDay: [UUID: [UUID]],
    in days: [TripDay]
) -> Bool {
    days.allSatisfy { day in
        guard let originalItemIDs = originalItemIDsByDay[day.id] else { return false }
        return day.sortedItems.map(\.id) == originalItemIDs
    }
}

private struct ItineraryDragState {
    let itemID: UUID
    let sourceDayID: UUID
    let originalItemIDsByDay: [UUID: [UUID]]
    var destination: ItineraryDropDestination?
}

private struct TripDayDragState {
    let dayID: UUID
    let originalDayIDs: [UUID]
    var destinationDayID: UUID?
}

func resolvedTripDayDropDestination(
    lastPreviewDayID: UUID?,
    reportedDayID: UUID
) -> UUID {
    lastPreviewDayID ?? reportedDayID
}

func hasOriginalTripDayOrder(
    _ originalDayIDs: [UUID],
    in days: [TripDay]
) -> Bool {
    JourneyHierarchyService.sortedDays(days).map(\.id) == originalDayIDs
}

private final class DragSessionCleanupToken {
    private let onSessionEnd: () -> Void

    init(onSessionEnd: @escaping () -> Void) {
        self.onSessionEnd = onSessionEnd
    }

    deinit {
        let cleanup = onSessionEnd
        DispatchQueue.main.async(execute: cleanup)
    }
}

private func dragItemProvider(
    payload: String,
    onSessionEnd: @escaping () -> Void
) -> NSItemProvider {
    let provider = NSItemProvider()
    let cleanupToken = DragSessionCleanupToken(onSessionEnd: onSessionEnd)
    provider.registerDataRepresentation(
        forTypeIdentifier: UTType.plainText.identifier,
        visibility: .all
    ) { completion in
        _ = cleanupToken
        completion(payload.data(using: .utf8), nil)
        return nil
    }
    return provider
}

private struct ItineraryReorderDropDelegate: DropDelegate {
    let onEntered: () -> Void
    var onExited: (() -> Void)? = nil
    let onDrop: () -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        onEntered()
    }

    func dropExited(info: DropInfo) {
        onExited?()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onDrop()
    }
}

private struct TripShareRequest: Identifiable {
    let id = UUID()
    let scopeID: UUID
}

struct ItineraryRoutePlanningRequest: Identifiable {
    let id = UUID()
    let title: String
    let points: [ItineraryRoutePoint]
    let missingLocationCount: Int
}

private struct ItineraryNavigationRequest: Identifiable {
    let id = UUID()
    let item: ItineraryItem
    let target: JourneyLocationTarget
}

private struct ItineraryTimeReviewRequest: Identifiable {
    let id = UUID()
    let adjustments: [ItineraryTimeAdjustment]
}

func hasOverlappingItineraryTimeRanges(_ ranges: [(start: Date, end: Date)]) -> Bool {
    let sortedRanges = ranges.sorted { lhs, rhs in
        lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
    }
    return zip(sortedRanges, sortedRanges.dropFirst()).contains { current, next in
        current.end > next.start
    }
}

private struct ItineraryTimeReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let request: ItineraryTimeReviewRequest
    @State private var drafts: [TimeDraft]

    init(request: ItineraryTimeReviewRequest) {
        self.request = request
        _drafts = State(initialValue: request.adjustments.map(TimeDraft.init))
    }

    var body: some View {
        TripNavigationStack {
            Form {
                Section {
                    Text("安排时长不同，已按新顺序预填时间，请确认或修改。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach($drafts) { $draft in
                    Section(draft.item.title) {
                        UnifiedTimeRangePicker(
                            startTime: $draft.startTime,
                            endTime: $draft.endTime
                        )
                        if draft.endTime < draft.startTime {
                            Label("结束时间不能早于开始时间", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if hasOverlap {
                    Section {
                        Label("调整后的安排存在时间重叠，请继续修改。", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("调整旅程时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("稍后修改") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存时间") { save() }
                        .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private var canSave: Bool {
        drafts.allSatisfy { $0.endTime >= $0.startTime } && !hasOverlap
    }

    private var hasOverlap: Bool {
        let draftValues = Dictionary(uniqueKeysWithValues: drafts.map { ($0.item.id, ($0.startTime, $0.endTime)) })
        let days = Dictionary(grouping: drafts.compactMap(\.item.day), by: \.id).values.compactMap(\.first)
        return days.contains { day in
            let ranges = day.items.map { item in
                let draftRange = draftValues[item.id]
                return (
                    start: draftRange?.0 ?? item.startTime,
                    end: draftRange?.1 ?? item.endTime
                )
            }
            return hasOverlappingItineraryTimeRanges(ranges)
        }
    }

    private func save() {
        for draft in drafts {
            draft.item.startTime = draft.startTime
            draft.item.endTime = draft.endTime
        }
        dismiss()
    }

    private struct TimeDraft: Identifiable {
        var id: UUID { item.id }
        let item: ItineraryItem
        var startTime: Date
        var endTime: Date

        init(_ adjustment: ItineraryTimeAdjustment) {
            item = adjustment.item
            startTime = adjustment.suggestedStartTime
            endTime = adjustment.suggestedEndTime
        }
    }
}

private struct ItineraryCard: View {
    @Bindable var item: ItineraryItem
    let onEdit: () -> Void
    let onNavigate: (JourneyLocationTarget) -> Void
    let onDragStart: () -> Void
    let onDragCancel: () -> Void
    var isDragEnabled = true
    @State private var mediaPreview: AssetMediaPreviewRequest?

    @ViewBuilder
    var body: some View {
        if isDragEnabled {
            cardSurface
                .contentShape(Rectangle())
                .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture(perform: onEdit)
                .onDrag {
                    onDragStart()
                    return dragItemProvider(payload: item.id.uuidString, onSessionEnd: onDragCancel)
                } preview: {
                    cardSurface
                        .frame(width: 330)
                }
                .accessibilityHint("长按并拖动可调整顺序")
                .fullScreenCover(item: $mediaPreview) { AssetMediaViewer(request: $0) }
        } else {
            cardSurface
                .allowsHitTesting(false)
        }
    }

    private var cardSurface: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.executionStatus.symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(item.executionStatus == .inProgress ? Color.white : statusColor)
                .frame(width: 36, height: 36)
                .background(
                    item.executionStatus == .inProgress ? statusColor : statusColor.opacity(0.10),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(statusColor.opacity(item.executionStatus == .inProgress ? 0.95 : 0.20), lineWidth: 1)
                }
                .accessibilityLabel("执行状态：\(item.executionStatus.rawValue)")

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 12) {
                    itineraryTitle
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(item.startTime.timeText)–\(item.endTime.timeText)")
                        .font(.caption.bold())
                        .monospacedDigit()
                        .padding(.horizontal, 11)
                        .frame(minHeight: 34)
                        .foregroundStyle(item.executionStatus == .inProgress ? Color.white : Color.primary)
                        .background(
                            item.executionStatus == .inProgress ? statusColor : statusColor.opacity(0.12),
                            in: Capsule()
                        )
                        .fixedSize()
                        .accessibilityLabel("时间，开始 \(item.startTime.timeText)，结束 \(item.endTime.timeText)")
                        .highPriorityGesture(TapGesture().onEnded {})
                }

                locationRows
                VStack(alignment: .leading, spacing: 9) {
                    if !item.reservationInfo.isEmpty {
                        Label(item.reservationInfo, systemImage: "ticket")
                    }
                    if !item.distanceText.isEmpty || item.cost > 0 {
                        HStack(spacing: 12) {
                            if !item.distanceText.isEmpty {
                                Label(item.distanceText, systemImage: "arrow.triangle.swap")
                            }
                            if item.cost > 0 {
                                Label {
                                    Text(item.cost, format: .currency(code: "CNY"))
                                } icon: {
                                    Image(systemName: "yensign.circle")
                                }
                            }
                        }
                    }
                    if !item.note.isEmpty {
                        Text(item.note)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.caption)
                .fontWeight(detailFontWeight)
                .foregroundStyle(detailForegroundColor)

                InlineItineraryMediaGallery(item: item) { media in
                    mediaPreview = AssetMediaPreviewRequest(
                        items: item.media
                            .sorted { $0.sortOrder < $1.sortOrder }
                            .map { AssetMediaPreviewItem(identifier: $0.localIdentifier, kind: $0.kind) },
                        initialIdentifier: media.localIdentifier
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(item.executionStatus == .completed ? 0.82 : 1)
        .padding(12)
        .background(
            statusBackgroundColor,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(statusBorderColor, lineWidth: statusBorderWidth)
        }
        .overlay(alignment: .leading) {
            if item.executionStatus == .inProgress {
                Capsule()
                    .fill(Color.tripLake)
                    .frame(width: 5)
                    .padding(.vertical, 12)
                    .padding(.leading, 2)
            }
        }
        .shadow(
            color: statusShadowColor,
            radius: item.executionStatus == .inProgress ? 13 : 7,
            y: item.executionStatus == .inProgress ? 6 : 3
        )
        .animation(.easeInOut(duration: 0.18), value: item.executionStatus)
    }

    @ViewBuilder
    private var itineraryTitle: some View {
        HStack(spacing: 7) {
            Image(systemName: item.category.symbol)
                .accessibilityHidden(true)
            MarqueeTitleText(
                text: item.title.isEmpty ? "未命名安排" : item.title,
                font: item.executionStatus == .inProgress ? .headline.bold() : .headline
            )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(item.executionStatus == .completed ? .secondary : .primary)
        .layoutPriority(1)
    }

    @ViewBuilder
    private var locationRows: some View {
        if item.locationTargets.isEmpty {
            Label("还没有填写地点", systemImage: "mappin.slash")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            ForEach(item.locationTargets) { target in
                Button {
                    onNavigate(target)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: target.role == .origin ? "location.circle" : "mappin.circle.fill")
                        Text("\(target.role.displayName)：\(target.displayName)")
                            .lineLimit(2)
                    }
                    .font(.subheadline.weight(locationFontWeight))
                    .foregroundStyle(locationForegroundColor)
                }
                .buttonStyle(.plain)
                .accessibilityHint("可选择高德地图、小红书或抖音")
            }
        }
    }

    private var statusColor: Color {
        switch item.executionStatus {
        case .notStarted: Color(red: 0.56, green: 0.40, blue: 0.18)
        case .inProgress: Color.tripLake
        case .completed: Color.tripSage
        }
    }

    private var statusBackgroundColor: Color {
        switch item.executionStatus {
        case .notStarted, .inProgress: Color.tripSurface
        case .completed: Color.tripSage.opacity(0.14)
        }
    }

    private var statusBorderColor: Color {
        switch item.executionStatus {
        case .notStarted: Color.tripSand.opacity(0.82)
        case .inProgress: Color.tripLake.opacity(0.92)
        case .completed: Color.tripSage.opacity(0.46)
        }
    }

    private var statusBorderWidth: CGFloat {
        switch item.executionStatus {
        case .notStarted: 1.2
        case .inProgress: 2
        case .completed: 0.8
        }
    }

    private var detailFontWeight: Font.Weight {
        switch item.executionStatus {
        case .notStarted: .medium
        case .inProgress: .semibold
        case .completed: .regular
        }
    }

    private var detailForegroundColor: Color {
        switch item.executionStatus {
        case .notStarted: Color.tripInk.opacity(0.70)
        case .inProgress: Color.tripInk.opacity(0.82)
        case .completed: Color.secondary
        }
    }

    private var locationFontWeight: Font.Weight {
        switch item.executionStatus {
        case .notStarted: .medium
        case .inProgress: .semibold
        case .completed: .regular
        }
    }

    private var locationForegroundColor: Color {
        switch item.executionStatus {
        case .notStarted: Color.tripLakeText.opacity(0.86)
        case .inProgress: Color.tripLakeText
        case .completed: Color.tripLake
        }
    }

    private var statusShadowColor: Color {
        switch item.executionStatus {
        case .notStarted: Color.tripSand.opacity(0.12)
        case .inProgress: Color.tripLake.opacity(0.24)
        case .completed: Color.tripInk.opacity(0.055)
        }
    }

}

private struct DragPlacementPlaceholder: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.tripLake.opacity(0.035))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        Color.tripLake.opacity(0.62),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                    )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct DayNavigatorPlacementPlaceholder: View {
    var body: some View {
        Capsule()
            .fill(Color.tripLake.opacity(0.035))
            .overlay {
                Capsule()
                    .stroke(
                        Color.tripLake.opacity(0.62),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct NavigationOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAmap: () -> Void
    let onXiaohongshu: () -> Void
    let onDouyin: () -> Void

    private let amapBlue = Color(red: 0.10, green: 0.45, blue: 0.95)
    private let xiaohongshuRed = Color(red: 1.00, green: 0.14, blue: 0.25)
    private let douyinInk = Color(red: 0.08, green: 0.09, blue: 0.12)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            optionButton(
                title: "高德地图导航",
                subtitle: "打开 App 并规划路线",
                systemImage: "location.fill",
                foreground: amapBlue,
                background: amapBlue.opacity(0.12),
                action: onAmap
            )
            optionButton(
                title: "小红书搜攻略",
                subtitle: "搜索地点相关笔记",
                systemImage: "book.pages.fill",
                foreground: xiaohongshuRed,
                background: xiaohongshuRed.opacity(0.11),
                action: onXiaohongshu
            )
            optionButton(
                title: "抖音搜攻略",
                subtitle: "搜索地点相关视频",
                systemImage: "music.note",
                foreground: .white,
                background: douyinInk,
                action: onDouyin
            )
        }
        .padding(20)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }

    private func optionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            dismiss()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.bold())
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).opacity(0.78)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.subheadline.bold())
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(background, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AmapRoutePlanningView: View {
    @Environment(\.dismiss) private var dismiss
    let request: ItineraryRoutePlanningRequest
    @State private var selectedPointIDs: Set<String>
    @State private var transport: TransportMode = .car
    @State private var isOpening = false
    @State private var errorMessage: String?

    private let routeModes: [TransportMode] = [.car, .walk, .ride, .bus]

    init(request: ItineraryRoutePlanningRequest) {
        self.request = request
        _selectedPointIDs = State(initialValue: Set(request.points.map(\.id)))
    }

    var body: some View {
        TripNavigationStack {
            List {
                Section {
                    Picker("出行方式", selection: $transport) {
                        ForEach(routeModes) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("高德地图会按下方顺序设置起点、途经点和终点。")
                }

                Section {
                    HStack {
                        Button("全选") {
                            selectedPointIDs = Set(request.points.map(\.id))
                        }
                        Spacer()
                        Button("取消全选") {
                            selectedPointIDs.removeAll()
                        }
                    }
                    .buttonStyle(.borderless)

                    ForEach(request.points) { point in
                        Button {
                            toggle(point)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: selectedPointIDs.contains(point.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedPointIDs.contains(point.id) ? Color.tripLake : .secondary)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 7) {
                                        Text(point.target.displayName)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        if selectedPointIDs.contains(point.id) {
                                            Text(routeRole(for: point))
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(Color.tripLake)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(Color.tripLake.opacity(0.10), in: Capsule())
                                        }
                                    }
                                    Text("\(point.startTime.timeText)～\(point.endTime.timeText) · \(point.arrangementTitle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !point.target.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(point.target.address)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("选择地点（默认全选）")
                } footer: {
                    let selectionText = selectedPoints.count < 2
                        ? "至少选择两个地点。"
                        : "已选择 \(selectedPoints.count) 个地点，其中 \(max(0, selectedPoints.count - 2)) 个途经点。"
                    let missingText = request.missingLocationCount > 0
                        ? "另有 \(request.missingLocationCount) 个安排未填写地点，未加入规划。"
                        : ""
                    Text([selectionText, missingText].filter { !$0.isEmpty }.joined(separator: " "))
                }
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        openRoute()
                    } label: {
                        if isOpening {
                            ProgressView()
                        } else {
                            Text("生成路线")
                        }
                    }
                    .disabled(selectedPoints.count < 2 || isOpening)
                }
            }
            .interactiveDismissDisabled(isOpening)
            .alert("路线规划提示", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var selectedPoints: [ItineraryRoutePoint] {
        request.points.filter { selectedPointIDs.contains($0.id) }
    }

    private func toggle(_ point: ItineraryRoutePoint) {
        if selectedPointIDs.contains(point.id) {
            selectedPointIDs.remove(point.id)
        } else {
            selectedPointIDs.insert(point.id)
        }
    }

    private func routeRole(for point: ItineraryRoutePoint) -> String {
        guard let index = selectedPoints.firstIndex(where: { $0.id == point.id }) else { return "" }
        if index == 0 { return "起点" }
        if index == selectedPoints.count - 1 { return "终点" }
        return "途经点 \(index)"
    }

    private func openRoute() {
        let selected = selectedPoints
        guard selected.count >= 2 else { return }
        isOpening = true
        Task {
            let result = await AmapService.openRoute(
                stops: selected.map {
                    AmapStop(name: $0.target.name, address: $0.target.address)
                },
                mode: transport
            )
            isOpening = false
            if result == .opened {
                dismiss()
            } else {
                errorMessage = result.message(
                    destinationName: selected.map(\.target.displayName).joined(separator: "、")
                )
            }
        }
    }
}

private struct MarqueeTitleText: View {
    let text: String
    var font: Font = .headline
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animationStart = Date.now

    private let speed: CGFloat = 24
    private let gap: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let safeWidth = normalizedWidth(proxy.size.width)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !needsScrolling)) { timeline in
                HStack(spacing: gap) {
                    titleText
                        .background {
                            GeometryReader { textProxy in
                                Color.clear.preference(
                                    key: MarqueeTextWidthKey.self,
                                    value: normalizedWidth(textProxy.size.width)
                                )
                            }
                        }
                    if needsScrolling {
                        titleText.accessibilityHidden(true)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: scrollingOffset(at: timeline.date))
                .frame(width: safeWidth, alignment: .leading)
                .clipped()
            }
            .onAppear {
                containerWidth = safeWidth
                animationStart = .now
            }
            .onChange(of: safeWidth) { _, newWidth in
                containerWidth = newWidth
                animationStart = .now
            }
        }
        .frame(height: 22)
        .contentShape(Rectangle())
        .onPreferenceChange(MarqueeTextWidthKey.self) { newWidth in
            guard abs(textWidth - newWidth) > 0.5 else { return }
            textWidth = newWidth
            animationStart = .now
        }
        .onChange(of: text) { _, _ in
            animationStart = .now
        }
        .accessibilityLabel(text)
    }

    private var titleText: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var needsScrolling: Bool {
        containerWidth > 0 && textWidth.isFinite && textWidth > containerWidth + 1
    }

    private func normalizedWidth(_ width: CGFloat) -> CGFloat {
        width.isFinite ? max(0, width) : 0
    }

    private func scrollingOffset(at date: Date) -> CGFloat {
        guard needsScrolling else { return 0 }
        let cycleWidth = textWidth + gap
        guard cycleWidth.isFinite, cycleWidth > 0 else { return 0 }
        let distance = max(0, date.timeIntervalSince(animationStart)) * Double(speed)
        return -CGFloat(distance.truncatingRemainder(dividingBy: Double(cycleWidth)))
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct InlineItineraryMediaGallery: View {
    let item: ItineraryItem
    let onPlay: (MediaReference) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var sortedMedia: [MediaReference] {
        item.media.sorted { $0.sortOrder < $1.sortOrder }
    }

    @ViewBuilder
    var body: some View {
        if !sortedMedia.isEmpty {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(sortedMedia) { media in
                    Button {
                        onPlay(media)
                    } label: {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                AssetThumbnail(
                                    identifier: media.localIdentifier,
                                    showsVideoBadge: media.kind == .video
                                )
                            }
                            .clipped()
                    }
                    .buttonStyle(.plain)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel(media.kind == .video ? "查看视频" : "查看图片")
                    .accessibilityHint("打开大图，可左右滑动切换")
                }
            }
        }
    }
}

private struct DayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var day: TripDay

    var body: some View {
        TripNavigationStack {
            Form {
                TextField("当天标题", text: $day.title)
                LabeledContent("日期", value: day.date.chineseDateText)
                TextField("当天备注", text: $day.note, axis: .vertical).lineLimit(3...8)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("编辑当天")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
