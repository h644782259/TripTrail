import Combine
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var trip: Trip
    @State private var editingTrip = false
    @State private var dayForNewItem: TripDay?
    @State private var itemToEdit: ItineraryItem?
    @State private var dayToEdit: TripDay?
    @State private var dayToDelete: TripDay?
    @State private var itemToDelete: ItineraryItem?
    @State private var isConfirmingTripDeletion = false
    @State private var showsArchive = false
    @State private var shareRequest: TripShareRequest?
    @State private var placeMessage: String?
    @State private var navigationRequest: ItineraryNavigationRequest?
    @State private var timeReviewRequest: ItineraryTimeReviewRequest?
    @State private var showsScreenshotPicker = false
    @State private var screenshotPickerItems: [PhotosPickerItem] = []
    @State private var screenshotDraft: ItineraryJourneyDraft?
    @State private var showsTextImport = false
    @State private var screenshotImportMessage: String?
    @State private var isReadingScreenshot = false
    @State private var dayExpansionOverrides: [UUID: Bool] = [:]
    @State private var itineraryDrag: ItineraryDragState?
    @State private var dayDrag: TripDayDragState?
    @State private var progressReferenceDate = Date()
    private let completionTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                summaryCard
                quickActions
                itineraryDays
                addDayButton
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.tripCanvas)
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑旅程", systemImage: "pencil") { editingTrip = true }
                    Button("收进足迹", systemImage: "book.closed") { archiveWholeTrip() }
                    Button("分享行程", systemImage: "square.and.arrow.up") {
                        shareRequest = TripShareRequest(scopeID: trip.id)
                    }
                    Divider()
                    Button("删除行程", systemImage: "trash", role: .destructive) {
                        isConfirmingTripDeletion = true
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editingTrip) { TripEditorView(trip: trip) }
        .sheet(item: $dayForNewItem) { ItemEditorView(day: $0) }
        .sheet(item: $itemToEdit) { ItemEditorView(day: $0.day, item: $0) }
        .sheet(item: $dayToEdit, onDismiss: { completeElapsedItems() }) { DayEditorView(day: $0) }
        .sheet(item: $timeReviewRequest) { ItineraryTimeReviewView(request: $0) }
        .sheet(item: $screenshotDraft) { ScreenshotItineraryImportView(trip: trip, draft: $0) }
        .sheet(isPresented: $showsTextImport) { TextItineraryImportView(trip: trip) }
        .sheet(isPresented: $showsArchive) { ArchiveTripView(trip: trip) }
        .sheet(item: $shareRequest) { request in
            ShareExportView(trip: trip, initialScopeID: request.scopeID)
        }
        .sheet(item: $navigationRequest) { request in
            NavigationOptionsSheet(
                onAmap: { open(request) },
                onXiaohongshu: { openDiscovery(.xiaohongshu, for: request) },
                onDouyin: { openDiscovery(.douyin, for: request) }
            )
        }
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
            set: { if !$0 { screenshotImportMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { screenshotImportMessage = nil }
        } message: {
            Text(screenshotImportMessage ?? "")
        }
        .alert(HierarchyDeletionCopy.tripTitle, isPresented: $isConfirmingTripDeletion) {
            Button(HierarchyDeletionCopy.confirmationButtonTitle, role: .destructive) {
                modelContext.delete(trip)
                dismiss()
            }
            Button(HierarchyDeletionCopy.cancelButtonTitle, role: .cancel) {}
        } message: {
            Text(HierarchyDeletionCopy.tripMessage(title: trip.title))
        }
        .alert(
            HierarchyDeletionCopy.tripDayTitle,
            isPresented: Binding(
                get: { dayToDelete != nil },
                set: { if !$0 { dayToDelete = nil } }
            ),
            presenting: dayToDelete
        ) { day in
            Button(HierarchyDeletionCopy.confirmationButtonTitle, role: .destructive) {
                modelContext.delete(day)
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
        .onChange(of: screenshotPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await recognizeScreenshots(items) }
        }
        .onAppear { completeElapsedItems() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                completeElapsedItems()
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
    }

    @ViewBuilder
    private var itineraryDays: some View {
        if trip.sortedDays.isEmpty {
            ContentUnavailableView("还没有日程", systemImage: "calendar.badge.plus", description: Text("先添加一天。"))
                .frame(height: 260)
        } else {
            ForEach(Array(trip.sortedDays.enumerated()), id: \.element.id) { index, day in
                daySection(day, index: index)
            }
        }
    }

    private var dayDateSignature: [Date] {
        trip.sortedDays.map(\.date)
    }

    private var itemEndTimeSignature: [Date] {
        trip.allItems.map(\.endTime)
    }

    private var addDayButton: some View {
        Button { addDay() } label: {
            Label("继续添加一天", systemImage: "calendar.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .padding(.bottom, 20)
    }

    private var summaryCard: some View {
        let dayProgress = TripCalendarProgress.make(for: trip, relativeTo: progressReferenceDate)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(trip.destination.isEmpty ? "目的地待定" : trip.destination)
                        .font(.title.bold())
                    TwoTapDateRangePicker(
                        title: "旅行日期",
                        startTitle: "出发",
                        endTitle: "返程",
                        startDate: tripStartDateSelection,
                        endDate: tripEndDateSelection,
                        displayStyle: .compactOnColor
                    )
                }
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: dayProgress.fraction)
                        .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text(dayProgress.statusText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                        Text("\(dayProgress.currentDay) / \(dayProgress.totalDays)")
                            .font(.headline.bold())
                            .monospacedDigit()
                    }
                }
                .frame(width: 74, height: 74)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("行程进度，\(dayProgress.statusText)，\(dayProgress.currentDay) / \(dayProgress.totalDays) 天")
            }
            if !trip.note.isEmpty {
                Text(trip.note).font(.subheadline).foregroundStyle(.white.opacity(0.9))
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .background(
            LinearGradient(colors: [.tripInk, .tripLake], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }

    private var tripStartDateSelection: Binding<Date> {
        Binding(
            get: { trip.startDate },
            set: { newStartDate in
                let shiftedEndDate = JourneyHierarchyService.shiftedDate(
                    trip.endDate,
                    whenTripStartMovesFrom: trip.startDate,
                    to: newStartDate
                )
                JourneyHierarchyService.updateTripDateRange(
                    trip,
                    startDate: newStartDate,
                    endDate: shiftedEndDate
                )
            }
        )
    }

    private var tripEndDateSelection: Binding<Date> {
        Binding(
            get: { trip.endDate },
            set: { newEndDate in
                JourneyHierarchyService.updateTripDateRange(
                    trip,
                    startDate: trip.startDate,
                    endDate: newEndDate
                )
            }
        )
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button { requestNextPlaceNavigation() } label: {
                Label("下一个地点", systemImage: "location.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(trip.nextUnfinishedItem == nil)

            Menu {
                Button { showsScreenshotPicker = true } label: {
                    Label("选择截图", systemImage: "photo.stack")
                }

                Button { showsTextImport = true } label: {
                    Label("输入文本", systemImage: "text.badge.plus")
                }
            } label: {
                HStack(spacing: 7) {
                    if isReadingScreenshot {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(isReadingScreenshot ? "识别中…" : "智能录入")
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .disabled(isReadingScreenshot)
        }
        .controlSize(.large)
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
            screenshotDraft = try await ScreenshotItineraryImportService.recognizeJourney(
                imageDatas: imageDatas,
                referenceDate: trip.startDate,
                sourceAssetIdentifiers: assetIdentifiers
            )
        } catch {
            screenshotImportMessage = error.localizedDescription
        }
    }

    private func daySection(_ day: TripDay, index: Int) -> some View {
        let isExpanded = isDayExpanded(day)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    toggleDay(day)
                } label: {
                    HStack(spacing: 10) {
                        (
                            Text(day.title.isEmpty ? "第 \(index + 1) 天" : day.title)
                                .font(.headline)
                            + Text(" · \(day.date.formatted(.dateTime.month().day().weekday(.wide)))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                        Spacer(minLength: 8)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.title.isEmpty ? "第 \(index + 1) 天" : day.title)，\(isExpanded ? "已展开" : "已收起")")
                .accessibilityHint(isExpanded ? "点击收起当天安排" : "点击展开当天安排")

                Menu {
                    Button("编辑当天", systemImage: "pencil") {
                        dayToEdit = day
                    }
                    Button("分享当天", systemImage: "square.and.arrow.up") {
                        shareRequest = TripShareRequest(scopeID: day.id)
                    }
                    Divider()
                    Button("删除当天", systemImage: "trash", role: .destructive) {
                        dayToDelete = day
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 32, height: 32)
                }
                .accessibilityLabel("当天更多操作")

                Image(systemName: "line.3.horizontal")
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .onDrag {
                        beginDayDrag(day)
                        return NSItemProvider(object: "trip-day:\(day.id.uuidString)" as NSString)
                    } preview: {
                        Label(displayTitle(for: day), systemImage: "calendar")
                            .font(.headline)
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityLabel("拖动调整\(displayTitle(for: day))的顺序")
            }

            if isExpanded {
                if day.displayItems.isEmpty {
                    Button { dayForNewItem = day } label: {
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
                    ForEach(day.displayItems) { item in
                        ItemSwipeActionContainer {
                            itemToEdit = item
                        } onDelete: {
                            itemToDelete = item
                        } content: {
                            ItineraryCard(item: item) {
                                itemToEdit = item
                            } onNavigate: {
                                navigationRequest = ItineraryNavigationRequest(item: item, action: .place)
                            } onDragStart: {
                                beginItineraryDrag(item)
                            }
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.tripSurface)
                            .onDrop(
                                of: [UTType.plainText],
                                delegate: ItineraryReorderDropDelegate(
                                    onEntered: {
                                        if dayDrag != nil {
                                            previewDayDrag(over: day)
                                        } else {
                                            previewItineraryDrag(over: item)
                                        }
                                    },
                                    onExited: { clearDayDragDestination(day) },
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
                    }
                    .animation(.snappy(duration: 0.22), value: day.displayItems.map(\.id))
                    Button { dayForNewItem = day } label: {
                        Label("添加安排", systemImage: "plus")
                    }
                    .font(.subheadline.bold())
                }
            } else {
                collapsedDaySummary(day)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .cardSurface()
        .overlay {
            if dayDrag?.destinationDayID == day.id {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.tripLake, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: ItineraryReorderDropDelegate(
                onEntered: {
                    if dayDrag != nil {
                        previewDayDrag(over: day)
                    } else if day.sortedItems.isEmpty {
                        previewItineraryDrag(toEndOf: day)
                    }
                },
                onExited: { clearDayDragDestination(day) },
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

    private func displayTitle(for day: TripDay) -> String {
        if !day.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return day.title
        }
        let index = trip.sortedDays.firstIndex { $0.id == day.id } ?? 0
        return "第 \(index + 1) 天"
    }

    private func isDayExpanded(_ day: TripDay) -> Bool {
        dayExpansionOverrides[day.id] ?? !day.shouldAutomaticallyCollapse()
    }

    private func toggleDay(_ day: TripDay) {
        withAnimation(.easeInOut(duration: 0.2)) {
            dayExpansionOverrides[day.id] = !isDayExpanded(day)
        }
    }

    @ViewBuilder
    private func collapsedDaySummary(_ day: TripDay) -> some View {
        if day.hasCompletedAllItems {
            collapsedDayStatus(
                icon: "checkmark.circle.fill",
                text: "\(day.sortedItems.count) 项安排已完成",
                color: Color.tripSage
            )
        } else if day.isPast(relativeTo: progressReferenceDate) {
            collapsedDayStatus(icon: "clock.arrow.circlepath", text: "当天已过去", color: .secondary)
        } else if Calendar.current.isDate(day.date, inSameDayAs: progressReferenceDate) {
            collapsedDayStatus(icon: "clock.fill", text: "今天进行中", color: Color.tripLake)
        } else {
            collapsedDayStatus(icon: "calendar", text: "尚未开始", color: .secondary)
        }
    }

    private func collapsedDayStatus(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(color)
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
        if let itineraryDrag {
            restoreItineraryDrag(itineraryDrag)
            self.itineraryDrag = nil
        }
        dayDrag = TripDayDragState(dayID: day.id, destinationDayID: nil)
    }

    private func previewDayDrag(over day: TripDay) {
        guard var dayDrag, dayDrag.dayID != day.id else { return }
        dayDrag.destinationDayID = day.id
        self.dayDrag = dayDrag
    }

    private func clearDayDragDestination(_ day: TripDay) {
        guard var dayDrag, dayDrag.destinationDayID == day.id else { return }
        dayDrag.destinationDayID = nil
        self.dayDrag = dayDrag
    }

    private func finishDayDrag(over day: TripDay) -> Bool {
        guard let dayDrag else { return false }
        var didMove = false
        withAnimation(.snappy(duration: 0.22)) {
            didMove = JourneyHierarchyService.moveTripDaySchedule(
                id: dayDrag.dayID,
                to: day.id,
                in: trip.days
            )
        }
        self.dayDrag = nil
        if didMove {
            completeElapsedItems()
        }
        return didMove
    }

    private func beginItineraryDrag(_ item: ItineraryItem) {
        dayDrag = nil
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
    }

    private func finishItineraryDrag(at destination: ItineraryDropDestination) -> Bool {
        guard let itineraryDrag else { return false }

        var result = ItineraryMoveResult.unchanged
        withTransaction(Transaction(animation: nil)) {
            restoreItineraryDrag(itineraryDrag)
            switch destination {
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

    private func requestNextPlaceNavigation() {
        guard let item = trip.nextUnfinishedItem else {
            placeMessage = "当前没有下一个未完成地点。"
            return
        }
        navigationRequest = ItineraryNavigationRequest(item: item, action: .nextPlace)
    }

    private func open(_ request: ItineraryNavigationRequest) {
        let item = request.item
        let stop = AmapStop(
            name: item.title,
            address: "",
            latitude: item.latitude,
            longitude: item.longitude
        )
        Task {
            let opened: Bool
            switch request.action {
            case .place:
                opened = await AmapService.openPlace(
                    name: item.title,
                    address: "",
                    latitude: item.latitude,
                    longitude: item.longitude,
                    mode: item.transport
                )
            case .nextPlace:
                opened = await AmapService.openNextPlace(stop, mode: item.transport)
            }
            if !opened {
                #if targetEnvironment(simulator)
                placeMessage = "当前 iPhone 模拟器没有安装高德地图 App。模拟器与手机是独立环境，请在已安装高德地图的真机上测试。"
                #else
                placeMessage = "未检测到高德地图 App，请确认已安装或更新到最新版本后重试。"
                #endif
            }
        }
    }

    private func openDiscovery(_ platform: PlaceDiscoveryPlatform, for request: ItineraryNavigationRequest) {
        let item = request.item
        Task {
            let opened = await PlaceDiscoveryService.open(
                platform,
                name: item.title,
                address: ""
            )
            if !opened {
                placeMessage = "暂时无法打开\(platform.displayName)，请检查网络或稍后重试。"
            }
        }
    }

    private func addDay() {
        let seed = JourneyHierarchyService.nextDaySeed(after: trip.days, fallbackDate: trip.startDate)
        let day = TripDay(date: seed.date, title: seed.title, sortOrder: seed.sortOrder, trip: trip)
        trip.days.append(day)
    }

    private func archiveWholeTrip() {
        showsArchive = true
    }
}

private enum ItineraryDropDestination: Equatable {
    case item(UUID)
    case endOfDay(UUID)
}

private struct ItineraryDragState {
    let itemID: UUID
    let sourceDayID: UUID
    let originalItemIDsByDay: [UUID: [UUID]]
    var destination: ItineraryDropDestination?
}

private struct TripDayDragState {
    let dayID: UUID
    var destinationDayID: UUID?
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

private struct ItineraryNavigationRequest: Identifiable {
    enum Action {
        case place
        case nextPlace
    }

    let id = UUID()
    let item: ItineraryItem
    let action: Action
}

private struct ItineraryTimeReviewRequest: Identifiable {
    let id = UUID()
    let adjustments: [ItineraryTimeAdjustment]
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
        NavigationStack {
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
            .navigationTitle("调整行程时间")
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
            let items = day.sortedItems
            return zip(items, items.dropFirst()).contains { first, second in
                let firstEnd = draftValues[first.id]?.1 ?? first.endTime
                let secondStart = draftValues[second.id]?.0 ?? second.startTime
                return firstEnd > secondStart
            }
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
    let onNavigate: () -> Void
    let onDragStart: () -> Void
    @State private var mediaPreview: AssetMediaPreviewRequest?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { item.toggleCompletionManually() } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isCompleted ? Color.tripSage : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 12) {
                    itineraryTitle
                        .frame(maxWidth: .infinity, alignment: .leading)

                    UnifiedTimeRangePicker(
                        title: "修改时间",
                        startTime: $item.startTime,
                        endTime: $item.endTime,
                        displayStyle: .capsule
                    )
                    .fixedSize()
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                InlineItineraryMediaRecorder(item: item) { media in
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
        .opacity(item.isCompleted ? 0.72 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .onDrag {
            onDragStart()
            return NSItemProvider(object: item.id.uuidString as NSString)
        } preview: {
            Label(item.title, systemImage: item.category.symbol)
                .font(.headline)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityHint("长按并拖动可调整顺序")
        .fullScreenCover(item: $mediaPreview) { AssetMediaViewer(request: $0) }
    }

    @ViewBuilder
    private var itineraryTitle: some View {
        HStack(spacing: 7) {
            Image(systemName: item.category.symbol)
                .accessibilityHidden(true)
            Button(action: onNavigate) {
                MarqueeTitleText(text: item.title.isEmpty ? "地点" : item.title)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("打开\(item.title.isEmpty ? "当前地点" : item.title)的导航选项")
            .accessibilityHint("可选择高德地图、小红书或抖音")
        }
        .foregroundStyle(item.isCompleted ? .secondary : .primary)
        .layoutPriority(1)
    }

}

private struct NavigationOptionsSheet: View {
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

private struct MarqueeTitleText: View {
    let text: String
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animationStart = Date.now

    private let speed: CGFloat = 24
    private let gap: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !needsScrolling)) { timeline in
                HStack(spacing: gap) {
                    titleText
                        .background {
                            GeometryReader { textProxy in
                                Color.clear
                                    .preference(key: MarqueeTextWidthKey.self, value: textProxy.size.width)
                            }
                        }
                    if needsScrolling {
                        titleText
                            .accessibilityHidden(true)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: scrollingOffset(at: timeline.date))
                .frame(width: proxy.size.width, alignment: .leading)
                .clipped()
            }
            .onAppear {
                containerWidth = proxy.size.width
                animationStart = .now
            }
            .onChange(of: proxy.size.width) { _, newWidth in
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
    }

    private var titleText: some View {
        Text(text)
            .font(.headline)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var needsScrolling: Bool {
        containerWidth > 0 && textWidth > containerWidth + 1
    }

    private func scrollingOffset(at date: Date) -> CGFloat {
        guard needsScrolling else { return 0 }
        let cycleWidth = textWidth + gap
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

private struct InlineItineraryMediaRecorder: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: ItineraryItem
    let onPlay: (MediaReference) -> Void
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var mediaWarning: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(item.media.sorted { $0.sortOrder < $1.sortOrder }) { media in
                    ZStack(alignment: .topTrailing) {
                        AssetThumbnail(identifier: media.localIdentifier, showsVideoBadge: media.kind == .video)
                            .frame(width: 76, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .onTapGesture { onPlay(media) }
                        Button {
                            item.media.removeAll { $0.id == media.id }
                            modelContext.delete(media)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.58))
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .accessibilityLabel("移除这项图片或视频")
                    }
                }

                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: 20,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
                ) {
                    Image(systemName: "plus")
                        .font(.title3.bold())
                        .frame(width: 62, height: 62)
                        .background(Color.tripLake.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.tripLake.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.tripLake)
                .accessibilityLabel("给\(item.title)添加图片或视频")
            }
        }
        .onChange(of: pickerItems) { _, newValue in
            addMedia(from: newValue)
        }
        .alert("相簿提示", isPresented: Binding(
            get: { mediaWarning != nil },
            set: { if !$0 { mediaWarning = nil } }
        )) {
            Button("知道了", role: .cancel) { mediaWarning = nil }
        } message: {
            Text(mediaWarning ?? "")
        }
    }

    private func addMedia(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let converted = PhotoLibraryService.pickedAssets(from: items)
        if converted.count != items.count {
                mediaWarning = "有 \(items.count - converted.count) 项无法读取相簿标识，请从系统“照片”中重选。当前权限：\(PhotoLibraryService.readableStatusText)。"
        }

        let existingIDs = Set(item.media.map(\.localIdentifier))
        let newAssets = converted.filter { !existingIDs.contains($0.id) }
        let firstSortOrder = (item.media.map(\.sortOrder).max() ?? -1) + 1
        for (index, picked) in newAssets.enumerated() {
            let reference = MediaReference(
                localIdentifier: picked.id,
                kind: picked.kind,
                sortOrder: firstSortOrder + index
            )
            reference.itineraryItem = item
            item.media.append(reference)
        }
        pickerItems = []
    }
}

private struct ItemSwipeActionContainer<Content: View>: View {
    private let actionWidth: CGFloat = 74
    private let onEdit: () -> Void
    private let onDelete: () -> Void
    private let content: Content
    @State private var isOpen = false
    @GestureState private var dragOffset: CGFloat = 0

    init(
        _ onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.content = content()
    }

    private var actionPanelWidth: CGFloat { actionWidth * 2 }

    private var visibleOffset: CGFloat {
        let settledOffset = isOpen ? -actionPanelWidth : 0
        return min(0, max(-actionPanelWidth, settledOffset + dragOffset))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                actionButton("编辑", systemImage: "pencil", color: .tripLake) {
                    closeActions()
                    onEdit()
                }
                actionButton("删除", systemImage: "trash", color: .red) {
                    closeActions()
                    onDelete()
                }
            }
            .frame(width: actionPanelWidth)
            .frame(maxHeight: .infinity)
            .zIndex(isOpen ? 2 : 0)
            .allowsHitTesting(isOpen)
            .accessibilityHidden(!isOpen)

            content
                .offset(x: visibleOffset)
                .contentShape(Rectangle())
                .simultaneousGesture(swipeGesture)
                .zIndex(1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityAction(named: "编辑安排", onEdit)
        .accessibilityAction(named: "删除安排", onDelete)
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.headline)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color)
        }
        .buttonStyle(.plain)
        .frame(width: actionWidth)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .updating($dragOffset) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let settledOffset = isOpen ? -actionPanelWidth : 0
                let finalOffset = min(0, max(-actionPanelWidth, settledOffset + value.translation.width))
                let shouldOpen = finalOffset < -(actionPanelWidth * 0.32)
                withAnimation(.snappy(duration: 0.22)) {
                    isOpen = shouldOpen
                }
            }
    }

    private func closeActions() {
        withAnimation(.snappy(duration: 0.18)) {
            isOpen = false
        }
    }
}

private struct DayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var day: TripDay

    var body: some View {
        NavigationStack {
            Form {
                TextField("当天标题", text: $day.title)
                DatePicker("日期", selection: $day.date, displayedComponents: .date)
                TextField("当天备注", text: $day.note, axis: .vertical).lineLimit(3...8)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("编辑当天")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
