import Combine
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var trip: Trip
    @State private var showsTripInfo = false
    @State private var tripInfoScrollOrigin: CGFloat?
    @State private var infoDraftStart: Date?
    @State private var activeInfoField: String?
    @State private var dayForNewItem: TripDay?
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
    @State private var itemDragOrder: [UUID] = []
    @State private var itemDragFrames: [UUID: CGRect] = [:]
    @State private var itemDragLocation: CGPoint?
    @State private var itemDragGrabOffset: CGSize = .zero
    @State private var itemDragSize: CGSize = .zero
    @State private var dayDrag: TripDayDragState?
    @State private var dayDragRevision = 0
    @State private var previewDayIDs: [UUID] = []
    @State private var dayTabFrames: [UUID: CGRect] = [:]
    @State private var dayTabFingerX: CGFloat?
    @State private var dayTabGrabOffset: CGFloat = 0
    @State private var dayTabViewport: CGRect = .zero
    private let dayTabScrollTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    @State private var dragCleanupTask: Task<Void, Never>?
    @State private var progressReferenceDate = Date()
    private let completionTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        lifecycleContent
    }

    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                CloudSaveNotice(id: trip.id, kind: "trip")
                selectedDayHeader
                if let selection = selectedDaySelection,
                   selection.day.date >= Calendar.current.startOfDay(for: Date()) {
                    JourneyWeatherView(dayID: selection.day.id, date: selection.day.date,
                        suggestedCity: selection.day.city)
                }
                itineraryDays
            }
            .padding()
            .padding(.bottom, 84)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: TripInfoPullOffsetKey.self, value: geometry.frame(in: .named("tripDetailScroll")).minY)
            })
            .background(Color.tripCanvas.contentShape(Rectangle()).onTapGesture { activeInfoField = nil })
        }
        .coordinateSpace(name: "tripDetailScroll")
        .scrollBounceBehavior(.always)
        .onPreferenceChange(TripInfoPullOffsetKey.self) { offset in
            guard !showsTripInfo, itineraryDrag == nil else { return }
            guard let origin = tripInfoScrollOrigin else { tripInfoScrollOrigin = offset; return }
            if offset - origin > 48 {
                withAnimation(.easeInOut(duration: 0.2)) { showsTripInfo = true }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if showsTripInfo { tripInfoPanel }
                dayNavigator
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.tripCanvas.contentShape(Rectangle()).onTapGesture { activeInfoField = nil })
        .task(id: trip.id) { await CloudSyncService.shared.sync(context: modelContext, kind: "trip", recordID: trip.id, automatic: true) }
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.tripCanvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { toggleTripInfo() } label: {
                    HStack(spacing: 5) {
                        Text(trip.title).font(.headline).lineLimit(1)
                        Image(systemName: showsTripInfo ? "chevron.up" : "chevron.down").font(.caption2)
                    }
                    .foregroundStyle(Color.tripInk)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("旅程信息")
                .accessibilityValue(showsTripInfo ? "已展开" : "已收起")
                .simultaneousGesture(DragGesture(minimumDistance: 18).onEnded { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { showsTripInfo = value.translation.height > 0 }
                })
            }
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    CloudBadge(id: trip.id, kind: "trip").font(.tripSystem(size: 20))
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    CloudBadge(id: trip.id, kind: "trip").font(.tripSystem(size: 20))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let selection = selectedDaySelection {
                        let day = selection.day
                        Button("新建安排", systemImage: "plus") { dayForNewItem = day }
                        .disabled(isReadingScreenshot)
                        Button("编辑当天", systemImage: "pencil") {
                            dayToEdit = day
                        }
                        Button("分享当天", systemImage: "square.and.arrow.up") {
                            shareRequest = TripShareRequest(scopeID: day.id)
                        }
                        Button("规划路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
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
                } label: { Image(systemName: "ellipsis") }
                .font(.tripSystem(size: 20))
                .accessibilityLabel("当天更多操作")
            }
        }
    }

    private func toggleTripInfo() {
        withAnimation(.easeInOut(duration: 0.2)) { showsTripInfo.toggle() }
    }

    private var tripInfoPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    TripInfoEditableField(title: "目的地", value: trip.destination, activeField: $activeInfoField, icon: "mappin.and.ellipse") { value in
                        trip.destination = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        return saveTripInfo()
                    }
                    TripInfoEditableField(title: "车牌号", value: trip.licensePlateDisplay, activeField: $activeInfoField, icon: "car") { value in
                        trip.licensePlate = value.formattedLicensePlate
                        return saveTripInfo()
                    }
                }
                TwoTapDateRangePicker(
                    title: "旅行日期", startTitle: "出发", endTitle: "返程",
                    startDate: Binding(get: { trip.startDate }, set: { infoDraftStart = $0 }),
                    endDate: Binding(get: { trip.endDate }, set: { end in
                        JourneyHierarchyService.updateTripDateRange(trip, startDate: infoDraftStart ?? trip.startDate, endDate: end)
                        infoDraftStart = nil
                        if let error = saveTripInfo() { placeMessage = error }
                    }),
                    displayStyle: .compact, showsEndpointTitles: false, onOpen: { activeInfoField = nil }
                )
                TripInfoEditableField(title: "旅程备注", value: trip.note, activeField: $activeInfoField, multiline: true) { value in
                    trip.note = value
                    return saveTripInfo()
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: 170)
        .simultaneousGesture(DragGesture(minimumDistance: 18).onEnded { value in
            guard activeInfoField == nil,
                  value.translation.height < -32,
                  abs(value.translation.height) > abs(value.translation.width) else { return }
            withAnimation(.easeInOut(duration: 0.2)) { showsTripInfo = false }
        })
        .background {
            LinearGradient(colors: [Color.tripLake.opacity(0.14), Color.tripSage.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(Color.tripCanvas)
                .onTapGesture { activeInfoField = nil }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.tripLake.opacity(0.16), lineWidth: 0.5).allowsHitTesting(false))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private static let infoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    private func saveTripInfo() -> String? {
        do { try modelContext.save(); Task { await CloudSyncService.shared.uploadPending(context: modelContext, key: "trip:\(trip.id.uuidString.lowercased())", entityID: trip.id) }; return nil }
        catch { return "保存失败，请重试" }
    }

    private func saveTripInfoDate(_ value: String, isStart: Bool) -> String? {
        guard let date = Self.infoDateFormatter.date(from: value), Self.infoDateFormatter.string(from: date) == value else {
            return "请按 YYYY-MM-DD 输入日期"
        }
        let start = isStart ? date : Calendar.current.startOfDay(for: trip.startDate)
        let end = isStart ? Calendar.current.startOfDay(for: trip.endDate) : date
        guard start <= end else { return "开始日期不能晚于结束日期" }
        JourneyHierarchyService.updateTripDateRange(trip, startDate: start, endDate: end)
        return saveTripInfo()
    }

    private var sheetContent: some View {
        mainContent
        .cloudEditSheet(item: $dayForNewItem) { ItemEditorView(day: $0) }


        .cloudEditSheet(item: $dayForFavoriteImport) { FavoriteImportSelectionView(day: $0) }
        .cloudEditSheet(item: $itemToEdit) { ItemEditorView(day: $0.day, item: $0) }
        .cloudEditSheet(item: $dayToEdit, onDismiss: {
            JourneyHierarchyService.normalizeTripDaySchedule(trip)
            completeElapsedItems()
        }) { DayEditorView(day: $0) }
        .cloudEditSheet(item: $timeReviewRequest) { ItineraryTimeReviewView(request: $0) }
        .cloudEditSheet(item: $screenshotDraft) { draft in
            ScreenshotItineraryImportView(
                trip: trip,
                draft: draft,
                targetDay: selectedDaySelection?.day,
                onRetryRecognition: draft.recognitionNotice == nil ? nil : {
                    retryScreenshotRecognition()
                }
            )
        }
        .cloudEditSheet(isPresented: $showsTextImport) {
            TextItineraryImportView(
                trip: trip,
                referenceDate: selectedDaySelection?.day.date ?? trip.startDate,
                targetDay: selectedDaySelection?.day
            )
        }
        .cloudEditSheet(item: $shareRequest) { request in
            ShareExportView(trip: trip, initialScopeID: request.scopeID)
        }
        .cloudEditSheet(item: $routePlanningRequest) { request in
            AmapRoutePlanningView(request: request)
        }
        .tripBottomSheet(item: $navigationRequest) { request in
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
            maxSelectionCount: 3,
            selectionBehavior: .ordered,
            matching: .images,
            photoLibrary: .shared()
        )
        .overlay {
            screenshotRecognitionOverlay
        }
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
                let id = item.id
                modelContext.delete(item)
                Task { await CloudSyncService.shared.uploadPending(context: modelContext,
                    key: "trip:\(trip.id.uuidString.lowercased())", entityID: id) }
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
            Button { dayToEdit = selection.day } label: {
            Text(selection.day.title.isEmpty ? "第 \(selection.index + 1) 天" : selection.day.title)
                .font(.title2.bold())
                .foregroundStyle(Color.tripInk)
                .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("编辑当天：" + (selection.day.title.isEmpty ? "第 \(selection.index + 1) 天" : selection.day.title))
        }
    }

    private var previewDays: [TripDay] {
        guard dayDrag != nil else { return trip.sortedDays }
        let lookup = Dictionary(uniqueKeysWithValues: trip.days.map { ($0.id, $0) })
        return previewDayIDs.compactMap { lookup[$0] }
    }

    private var dayNavigator: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(previewDays.enumerated()), id: \.element.id) { index, day in
                            dayNavigatorItem(index: index, day: day)
                        }
                    }
                    .onPreferenceChange(DayTabFramesKey.self) { dayTabFrames = $0 }
                    .contentShape(Rectangle())
                    .background(ScrollLongPressBridge { phase, point in
                        switch phase {
                        case .began:
                            guard let id = dayTabFrames.first(where: { $0.value.contains(point) })?.key,
                                  let day = previewDays.first(where: { $0.id == id }) else { return }
                            dayTabGrabOffset = point.x - (dayTabFrames[id]?.midX ?? point.x)
                            beginDayDrag(day)
                            dayTabFingerX = point.x
                        case .changed:
                            guard dayDrag != nil else { return }
                            dayTabFingerX = point.x
                            updateDayTabDragTarget()
                        case .ended:
                            if let active = dayDrag,
                               let day = previewDays.first(where: { $0.id == active.destinationDayID }) {
                                _ = finishDayDrag(over: day)
                            } else if let active = dayDrag { cancelDayDragIfNeeded(dayID: active.dayID) }
                            dayTabFingerX = nil
                        case .cancelled, .failed:
                            if let active = dayDrag { cancelDayDragIfNeeded(dayID: active.dayID) }
                            dayTabFingerX = nil
                        default: break
                        }
                    })
                    .padding(.leading, 16)
                    .padding(.vertical, 8)
                    .animation(.snappy(duration: 0.22), value: previewDays.map(\.id))
                    .animation(.snappy(duration: 0.22), value: dayDragRevision)
                }
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: DayTabViewportKey.self, value: geometry.frame(in: .global))
                })
                .onPreferenceChange(DayTabViewportKey.self) { dayTabViewport = $0 }
                .onReceive(dayTabScrollTimer) { _ in
                    guard dayDrag != nil, let x = dayTabFingerX, dayTabViewport.width > 0 else { return }
                    updateDayTabDragTarget()
                    let center = x - dayTabGrabOffset
                    let halfWidth = (dayDrag.flatMap { dayTabFrames[$0.dayID]?.width } ?? 74) / 2
                    let right = center + halfWidth >= dayTabViewport.maxX - 4
                    let left = center - halfWidth <= dayTabViewport.minX + 4
                    guard right || left else { return }
                    let days = right ? previewDays : Array(previewDays.reversed())
                    guard let next = days.first(where: { day in
                        guard let frame = dayTabFrames[day.id] else { return false }
                        return right ? frame.maxX > dayTabViewport.maxX + 1 : frame.minX < dayTabViewport.minX - 1
                    }) else { return }
                    withAnimation(.linear(duration: 0.18)) {
                        proxy.scrollTo(next.id, anchor: right ? .trailing : .leading)
                    }
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

    private func updateDayTabDragTarget() {
        guard let active = dayDrag, let fingerX = dayTabFingerX,
              let source = dayTabFrames[active.dayID] else { return }
        // Preserve the grab point: compare the dragged pill's center with each slot's center.
        let centerX = fingerX - dayTabGrabOffset
        let right = centerX > source.midX
        let candidates = previewDays.filter { day in
            guard day.id != active.dayID, let frame = dayTabFrames[day.id] else { return false }
            return right
                ? frame.midX > source.midX && centerX >= frame.midX
                : frame.midX < source.midX && centerX <= frame.midX
        }
        if let target = candidates.min(by: {
            abs((dayTabFrames[$0.id]?.midX ?? centerX) - centerX) < abs((dayTabFrames[$1.id]?.midX ?? centerX) - centerX)
        }) { previewDayDrag(over: target) }
    }

    private func dayNavigatorItem(index: Int, day: TripDay) -> some View {
        let isSelected = selectedDaySelection?.day.id == day.id

        return Group {
            if dayDrag?.dayID == day.id {
                DayNavigatorPlacementPlaceholder()
                    .frame(width: dayTabFrames[day.id]?.width ?? 74, height: dayTabFrames[day.id]?.height ?? 46)
            } else {
                dayNavigatorPill(index: index, day: day, isSelected: isSelected)
                    .onTapGesture { if dayDrag == nil { selectDay(day) } }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { selectDay(day) }
            }
        }
        .id(day.id)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: DayTabFramesKey.self, value: [day.id: geometry.frame(in: .global)])
        })
        .overlay {
            if dayDrag?.dayID == day.id {
                dayNavigatorPill(index: dayDrag?.originalDayIDs.firstIndex(of: day.id) ?? index, day: day, isSelected: isSelected)
                    .fixedSize()
                    .offset(x: (dayTabFingerX.map { $0 - dayTabGrabOffset } ?? dayTabFrames[day.id]?.midX ?? 0) - (dayTabFrames[day.id]?.midX ?? 0))
                    .allowsHitTesting(false)
                    .animation(nil, value: dayTabFingerX)
            }
        }
        .zIndex(dayDrag?.dayID == day.id ? 1 : 0)
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
            presentScreenshotDraft(recognizedDraft)
        } catch {
            retryScreenshotPickerItems = items
            presentScreenshotImportMessage(error.localizedDescription)
        }
    }

    private var screenshotRecognitionOverlay: some View {
        Group {
            if isReadingScreenshot {
                ZStack {
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("正在识别截图…")
                            .font(.headline)
                            .foregroundStyle(Color.tripInk)
                        Text("识别后预览，确认后保存。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                }
                .allowsHitTesting(true)
                .transition(.opacity)
            }
        }
    }

    private func presentScreenshotDraft(_ draft: ItineraryJourneyDraft) {
        Task { @MainActor in
            // PhotosPicker is itself a sheet. Wait for it to finish dismissing
            // before presenting the editable recognition result sheet.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            screenshotDraft = draft
        }
    }

    private func presentScreenshotImportMessage(_ message: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            screenshotImportMessage = message
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
        let active = itineraryDrag?.sourceDayID == day.id
        let order = active ? itemDragOrder : day.displayItems.map(\.id)
        let lookup = Dictionary(uniqueKeysWithValues: day.items.map { ($0.id, $0) })
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(order, id: \.self) { id in
                if let item = lookup[id] {
                    Group {
                        if itineraryDrag?.itemID == id {
                            DragPlacementPlaceholder(cornerRadius: 16)
                                .frame(height: itemDragSize.height)
                        } else {
                            CardSwipeActionContainer(cornerRadius: 16, editTitle: "编辑安排", deleteTitle: "删除安排",
                                onEdit: { itemToEdit = item }, onDelete: { itemToDelete = item }) {
                                ItineraryCard(item: item, onEdit: { itemToEdit = item }, onNavigate: {
                                    navigationRequest = ItineraryNavigationRequest(item: item, target: $0)
                                }, onDragStart: {}, onDragCancel: {})
                                    .padding(.vertical, 2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .id(id)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: ItemDragFramesKey.self, value: [id: geometry.frame(in: .global)])
                    })
                }
            }
            Button { dayForNewItem = day } label: { Label("添加安排", systemImage: "plus") }
                .font(.subheadline.bold())
        }
        .onPreferenceChange(ItemDragFramesKey.self) { itemDragFrames = $0 }
        .contentShape(Rectangle())
        .background(ScrollLongPressBridge { phase, point in
            switch phase {
            case .began:
                guard let id = itemDragFrames.first(where: { $0.value.contains(point) })?.key,
                      let item = lookup[id], let frame = itemDragFrames[id] else { return }
                itemDragOrder = day.displayItems.map(\.id)
                itemDragSize = frame.size
                itemDragGrabOffset = CGSize(width: point.x - frame.midX, height: point.y - frame.midY)
                beginItineraryDrag(item)
                itemDragLocation = point
            case .changed:
                guard itineraryDrag != nil else { return }
                itemDragLocation = point
                updateItemDragTarget()
            case .ended:
                commitItemDrag()
            case .cancelled, .failed:
                if let drag = itineraryDrag { cancelItineraryDragIfNeeded(itemID: drag.itemID) }
                itemDragLocation = nil
            default: break
            }
        })
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if let drag = itineraryDrag, let item = lookup[drag.itemID], let location = itemDragLocation {
                    let bounds = geometry.frame(in: .global)
                    ItineraryCard(item: item, onEdit: {}, onNavigate: { _ in }, onDragStart: {}, onDragCancel: {}, isDragEnabled: false)
                        .frame(width: itemDragSize.width, height: itemDragSize.height)
                        .scaleEffect(0.94)
                        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                        .position(x: location.x - itemDragGrabOffset.width - bounds.minX,
                                  y: location.y - itemDragGrabOffset.height - bounds.minY)
                        .animation(nil, value: location)
                }
            }.allowsHitTesting(false)
        }
        .animation(.snappy(duration: 0.22), value: itemDragOrder)
    }

    private func updateItemDragTarget() {
        guard let drag = itineraryDrag, let point = itemDragLocation,
              let from = itemDragOrder.firstIndex(of: drag.itemID),
              let source = itemDragFrames[drag.itemID] else { return }
        let center = point.y - itemDragGrabOffset.height
        let down = center > source.midY
        let candidates = itemDragOrder.filter { id in
            guard id != drag.itemID, let frame = itemDragFrames[id] else { return false }
            return down ? frame.midY > source.midY && center >= frame.midY : frame.midY < source.midY && center <= frame.midY
        }
        guard let target = candidates.min(by: { abs((itemDragFrames[$0]?.midY ?? center) - center) < abs((itemDragFrames[$1]?.midY ?? center) - center) }),
              let to = itemDragOrder.firstIndex(of: target) else { return }
        itemDragOrder.insert(itemDragOrder.remove(at: from), at: to)
    }

    private func commitItemDrag() {
        guard let drag = itineraryDrag else { return }
        let original = drag.originalItemIDsByDay[drag.sourceDayID] ?? []
        let finalIndex = itemDragOrder.firstIndex(of: drag.itemID)
        itineraryDrag = nil
        itemDragLocation = nil
        guard itemDragOrder != original, let index = finalIndex, original.indices.contains(index) else { return }
        let result = JourneyHierarchyService.moveItineraryItemResult(id: drag.itemID, to: original[index], in: trip.days)
        _ = handleMove(result)
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
        itineraryDrag = nil
        itemDragLocation = nil
        previewDayIDs = trip.sortedDays.map(\.id)
        dayDrag = TripDayDragState(
            dayID: day.id,
            originalDayIDs: trip.sortedDays.map(\.id),
            destinationDayID: nil
        )
    }

    private func previewDayDrag(over day: TripDay) {
        guard var dayDrag, dayDrag.dayID != day.id else { return }

        guard let from = previewDayIDs.firstIndex(of: dayDrag.dayID),
              let to = previewDayIDs.firstIndex(of: day.id), from != to else { return }
        withAnimation(.snappy(duration: 0.22)) {
            previewDayIDs.insert(previewDayIDs.remove(at: from), at: to)
        }
        dayDrag.destinationDayID = day.id
        self.dayDrag = dayDrag
        dayDragRevision &+= 1
    }

    private func finishDayDrag(over day: TripDay) -> Bool {
        guard let dayDrag else { return false }
        cancelPendingDragCleanup()

        if previewDayIDs == dayDrag.originalDayIDs {
                self.dayDrag = nil
            dayDragRevision &+= 1
            return false
        }

        // Commit the current insertion slot, even after reversing direction repeatedly.
        guard let finalIndex = previewDayIDs.firstIndex(of: dayDrag.dayID),
              dayDrag.originalDayIDs.indices.contains(finalIndex) else { return false }
        let committedDayID = dayDrag.originalDayIDs[finalIndex]
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

    private func cancelDayDragIfNeeded(dayID: UUID) {
        guard let dayDrag, dayDrag.dayID == dayID else { return }
        cancelPendingDragCleanup()
        self.dayDrag = nil
        dayDragRevision &+= 1
    }

    private func beginItineraryDrag(_ item: ItineraryItem) {
        cancelPendingDragCleanup()
        dayDrag = nil
        dayTabFingerX = nil
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

    private func cancelItineraryDragIfNeeded(itemID: UUID) {
        guard let itineraryDrag, itineraryDrag.itemID == itemID else { return }
        cancelPendingDragCleanup()
        self.itineraryDrag = nil
        itineraryDragRevision &+= 1
    }

    private func cancelPendingDragCleanup() {
        dragCleanupTask?.cancel()
        dragCleanupTask = nil
    }

    private func cancelActiveDragIfNeeded() {
        cancelPendingDragCleanup()
        dayDrag = nil
        itineraryDrag = nil
        dayTabFingerX = nil
        itemDragLocation = nil
        previewDayIDs = []
        itemDragOrder = []
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
        Task {
            let result = await AmapService.openPlace(
                name: request.target.name,
                address: request.target.address
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
        let dayID = day.id
        let days = trip.sortedDays
        if selectedDayID == day.id, let index = days.firstIndex(where: { $0.id == day.id }) {
            let nextDay = days.dropFirst(index + 1).first ?? days.prefix(index).last
            selectedDayID = nextDay?.id
        }
        trip.days.removeAll { $0.id == day.id }
        modelContext.delete(day)
        JourneyHierarchyService.normalizeTripDaySchedule(trip)
        do {
            try UnifiedJourneyService.reconcile(context: modelContext)
            try modelContext.save()
            let tripID = trip.id
            Task { await CloudSyncService.shared.uploadPending(context: modelContext,
                key: "trip:\(tripID.uuidString.lowercased())", entityID: dayID) }
        } catch { placeMessage = "删除未保存：\(error.localizedDescription)" }
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
        return day.displayItems.map(\.id) == originalItemIDs
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
    var onUpdated: ((CGPoint) -> Void)? = nil
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
        onUpdated?(info.location)
        return DropProposal(operation: .move)
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
    @Environment(\.modelContext) private var modelContext
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
                        if draft.endTime <= draft.startTime {
                            Label("结束时间必须晚于开始时间", systemImage: "exclamationmark.triangle.fill")
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
        drafts.allSatisfy { $0.endTime > $0.startTime } && !hasOverlap
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
        let targets = drafts.compactMap { draft -> (UUID, UUID)? in
            guard let trip = draft.item.day?.trip else { return nil }
            return (trip.id, draft.item.id)
        }
        Task {
            for (tripID, itemID) in targets {
                await CloudSyncService.shared.uploadPending(context: modelContext,
                    key: "trip:\(tripID.uuidString.lowercased())", entityID: itemID)
            }
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
                .accessibilityHint("长按并拖动可调整顺序")
                .fullScreenCover(item: $mediaPreview) { AssetMediaViewer(request: $0) }
        } else {
            cardSurface
                .allowsHitTesting(false)
        }
    }

    private var cardSurface: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 12) {
                    itineraryTitle
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(item.timeRangeText)
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
                        .accessibilityLabel(item.timeRangeText)
                        .highPriorityGesture(TapGesture().onEnded {})
                }

                locationRows
                VStack(alignment: .leading, spacing: 9) {
                    if item.cost > 0 {
                        HStack(spacing: 12) {
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
        .accessibilityValue("执行状态：\(item.executionStatus.rawValue)")
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.tripSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(statusBackgroundColor)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(statusBorderColor, lineWidth: statusBorderWidth)
        }
        .overlay(alignment: .leading) {
            if item.executionStatus == .inProgress {
                Capsule()
                    .fill(Color.tripLake)
                    .frame(width: 3)
                    .padding(.vertical, 16)
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
            Image(systemName: item.arrangementSymbol)
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
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Button {
                        onNavigate(target)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: target.role == .origin ? "location.circle" : "mappin.circle.fill")
                            Text("\(target.role.displayName)：\(target.displayName)")
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .font(.subheadline.weight(locationFontWeight))
                        .foregroundStyle(locationForegroundColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("可选择高德地图、小红书或抖音")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    LocationCopyButton(text: target.displayName)
                }
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
        case .notStarted: Color.clear
        case .inProgress: Color.tripLake.opacity(0.07)
        case .completed: Color.tripSage.opacity(0.06)
        }
    }

    private var statusBorderColor: Color {
        switch item.executionStatus {
        case .notStarted: Color.tripMist.opacity(0.45)
        case .inProgress: Color.tripLake.opacity(0.62)
        case .completed: Color.tripSage.opacity(0.25)
        }
    }

    private var statusBorderWidth: CGFloat {
        switch item.executionStatus {
        case .notStarted: 0.8
        case .inProgress: 1.4
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
        let points = ItineraryRoutePlanning.removingAdjacentDuplicates(request.points)
        self.request = ItineraryRoutePlanningRequest(title: request.title, points: points, missingLocationCount: request.missingLocationCount)
        let pending = points.filter { !$0.isCompleted }
        let firstPending = points.firstIndex { !$0.isCompleted }
        let previous = firstPending.flatMap { $0 > 0 ? points[$0 - 1] : nil }
        _selectedPointIDs = State(initialValue: Set((pending + [previous].compactMap { $0 }).map(\.id)))
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
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
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
                                        Text("\(point.isTimePending ? "时间待定" : "\(point.startTime.timeText)～\(point.endTime.timeText)") · \(point.arrangementTitle)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            LocationCopyButton(text: point.target.displayName)
                        }
                        let address = point.target.address.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !address.isEmpty, address != point.target.displayName {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(address).font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
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
        ItineraryRoutePlanning.removingAdjacentDuplicates(request.points.filter { selectedPointIDs.contains($0.id) })
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
        item.media.sorted(by: MediaReference.precedes)
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
    @Environment(\.modelContext) private var modelContext
    @Bindable var day: TripDay

    var body: some View {
        TripNavigationStack {
            Form {
                TextField("当天标题", text: $day.title).clearableText($day.title)
                TextField("城市", text: $day.city).clearableText($day.city)
                LabeledContent("日期", value: day.date.chineseDateText)
                TextField("当天备注", text: $day.note, axis: .vertical).clearableText($day.note).lineLimit(3...8)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("编辑当天")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") {
                try? modelContext.save()
                if let trip = day.trip { Task { await CloudSyncService.shared.uploadPending(context: modelContext,
                    key: "trip:\(trip.id.uuidString.lowercased())", entityID: day.id) } }
                dismiss()
            } } }
        }
    }
}


private struct TripInfoEditableField: View {
    let title: String
    let value: String
    @Binding var activeField: String?
    var multiline = false
    var icon: String? = nil
    var displayValue: String? = nil
    let onSave: (String) -> String?
    private var editing: Bool {
        get { activeField == title }
        nonmutating set { if newValue { activeField = title } else if activeField == title { activeField = nil } }
    }
    @State private var draft = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private func beginEditing() { draft = value; error = nil; editing = true; focused = true }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let icon {
                Image(systemName: icon).resizable().scaledToFit()
                    .frame(width: 16, height: 16).foregroundStyle(title == "车牌号" ? Color.tripSage : Color.tripLakeText).padding(.top, 2)
            }
            if editing {
                TextField("添加\(title)", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .lineLimit(multiline ? 1...3 : 1...2)
                    .focused($focused)
                    .onAppear { focused = true }
                    .onChange(of: draft) { _, value in
                        guard editing else { return }
                        error = onSave(value)
                    }
                    .onChange(of: focused) { _, hasFocus in
                        if !hasFocus { editing = false }
                    }
                    .onSubmit { if error == nil { editing = false; focused = false } }
                    .accessibilityLabel(title)
                    .accessibilityHint(error ?? "修改后自动保存")
            } else {
                Text(value.isEmpty ? "添加\(title)" : (displayValue ?? value))
                    .font(.subheadline)
                    .lineLimit(multiline ? 3 : 2)
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: beginEditing)
                    .accessibilityLabel(title + "，" + value)
                    .accessibilityHint("双击编辑")
                    .accessibilityAction(named: "编辑", beginEditing)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }
}

private struct TripInfoPullOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct DayTabFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct DayTabViewportKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct ItemDragFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// A native long press can coexist with the scroll view's pan recognizer. Unlike a
// sequenced SwiftUI zero-distance drag, it does not claim ordinary scroll gestures.
private struct ScrollLongPressBridge: UIViewRepresentable {
    let onEvent: (UIGestureRecognizer.State, CGPoint) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.attach = { [weak coordinator = context.coordinator] view in coordinator?.attach(to: view) }
        return view
    }
    func updateUIView(_ uiView: Probe, context: Context) {
        context.coordinator.onEvent = onEvent
        DispatchQueue.main.async { [weak uiView, weak coordinator = context.coordinator] in
            if let uiView { coordinator?.attach(to: uiView) }
        }
    }
    static func dismantleUIView(_ uiView: Probe, coordinator: Coordinator) { coordinator.detach() }
    final class Probe: UIView {
        var attach: ((UIView) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in if let self { self.attach?(self) } }
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onEvent: (UIGestureRecognizer.State, CGPoint) -> Void
        weak var scrollView: UIScrollView?
        private weak var hostView: UIView?
        private var savedPanEnabled: Bool?
        private var suspendedNavigationGestures: [(UIGestureRecognizer, Bool)] = []
        lazy var recognizer: UILongPressGestureRecognizer = {
            let value = UILongPressGestureRecognizer(target: self, action: #selector(handle(_:)))
            value.minimumPressDuration = 0.3
            value.allowableMovement = 12
            value.cancelsTouchesInView = false
            value.delaysTouchesBegan = false
            value.delaysTouchesEnded = false
            value.delegate = self
            return value
        }()
        init(onEvent: @escaping (UIGestureRecognizer.State, CGPoint) -> Void) { self.onEvent = onEvent }
        func attach(to view: UIView) {
            hostView = view
            var ancestor = view.superview
            while let current = ancestor {
                if let scroll = current as? UIScrollView {
                    if scrollView !== scroll { detach(); scrollView = scroll; scroll.addGestureRecognizer(recognizer) }
                    return
                }
                ancestor = current.superview
            }
        }
        private func suspendNavigationGestures(from view: UIView) {
            var responder: UIResponder? = view
            while let current = responder {
                if let controller = current as? UIViewController,
                   let navigation = (controller as? UINavigationController) ?? controller.navigationController {
                    var gestures = [navigation.interactivePopGestureRecognizer].compactMap { $0 }
                    if #available(iOS 26.0, *), let contentPop = navigation.interactiveContentPopGestureRecognizer {
                        gestures.append(contentPop)
                    }
                    for gesture in gestures where !suspendedNavigationGestures.contains(where: { $0.0 === gesture }) {
                        suspendedNavigationGestures.append((gesture, gesture.isEnabled))
                        gesture.isEnabled = false
                    }
                    return
                }
                responder = current.next
            }
        }
        private func restorePan() {
            for (gesture, wasEnabled) in suspendedNavigationGestures { gesture.isEnabled = wasEnabled }
            suspendedNavigationGestures.removeAll()
            if let savedPanEnabled { scrollView?.panGestureRecognizer.isEnabled = savedPanEnabled }
            savedPanEnabled = nil
        }
        func detach() {
            restorePan()
            scrollView?.removeGestureRecognizer(recognizer)
            scrollView = nil
        }
        @objc func handle(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began, let scrollView {
                suspendNavigationGestures(from: scrollView)
                savedPanEnabled = scrollView.panGestureRecognizer.isEnabled
                // Stop finger-driven panning only. Programmatic edge scrolling remains enabled.
                scrollView.panGestureRecognizer.isEnabled = false
            }
            onEvent(gesture.state, gesture.location(in: gesture.view?.window))
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                restorePan()
            }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let hostView, hostView.window != nil else { return false }
            return hostView.bounds.contains(touch.location(in: hostView))
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer === scrollView?.panGestureRecognizer
        }
    }
}

// Weather is supplementary information; a failed request never blocks the itinerary.
private struct JourneyWeatherDay: Codable {
    let fxDate: String
    let tempMax: String
    let tempMin: String
    let textDay: String
    let iconDay: String?
    let textNight: String
    let windDirDay: String
    let windScaleDay: String
    let humidity: String
    let precip: String
}

private extension JourneyWeatherDay {
    var symbol: String {
        switch Int(iconDay ?? "") ?? -1 {
        case 100: return "sun.max"
        case 150: return "moon.stars"
        case 101, 102, 103: return "cloud.sun"
        case 151, 152, 153: return "cloud.moon"
        case 104: return "cloud"
        case 302...304: return "cloud.bolt.rain"
        case 404...406, 456: return "cloud.sleet"
        case 300...399: return "cloud.rain"
        case 400...499: return "cloud.snow"
        case 503, 504, 507, 508: return "sun.dust"
        case 500...515: return "cloud.fog"
        case 900: return "sun.max"
        case 901: return "snowflake"
        default: return "questionmark.circle"
        }
    }
}

private actor JourneyWeatherService {
    static let shared = JourneyWeatherService()
    struct Forecast: Codable {
        let city: String
        let updated: String
        let daily: [JourneyWeatherDay]
        let fetched: Date
    }
    private var cache: [String: Forecast] = {
        guard let data = UserDefaults.standard.data(forKey: "journey.weather.cache"),
              let saved = try? JSONDecoder().decode([String: Forecast].self, from: data) else { return [:] }
        return saved
    }()

    private func request(_ path: String, _ items: [URLQueryItem]) async throws -> Data {
        let host = Bundle.main.object(forInfoDictionaryKey: "HeFengWeatherHost") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "HeFengWeatherKey") as? String ?? ""
        guard !key.isEmpty, !key.hasPrefix("$("), !host.isEmpty else { throw URLError(.userAuthenticationRequired) }
        var components = URLComponents()
        components.scheme = "https"; components.host = host; components.path = path; components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "X-QW-Api-Key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    func forecast(city: String) async throws -> Forecast {
        if let saved = cache[city], Date().timeIntervalSince(saved.fetched) < 3600 { return saved }
        struct Lookup: Decodable {
            struct Location: Decodable { let id: String; let name: String; let adm1: String; let adm2: String }
            let code: String
            let location: [Location]?
        }
        let lookup = try JSONDecoder().decode(Lookup.self, from: await request("/geo/v2/city/lookup", [.init(name: "location", value: city), .init(name: "number", value: "1")]))
        guard lookup.code == "200", let place = lookup.location?.first else { throw URLError(.cannotFindHost) }
        struct Response: Decodable { let code: String; let updateTime: String?; let daily: [JourneyWeatherDay]? }
        let response = try JSONDecoder().decode(Response.self, from: await request("/v7/weather/7d", [.init(name: "location", value: place.id)]))
        guard response.code == "200", let daily = response.daily else { throw URLError(.badServerResponse) }
        let result = Forecast(city: [place.adm1, place.adm2, place.name].reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: " · "), updated: response.updateTime ?? "", daily: daily, fetched: Date())
        cache[city] = result
        cache = cache.filter { Date().timeIntervalSince($0.value.fetched) < 86400 }
        if let data = try? JSONEncoder().encode(cache) { UserDefaults.standard.set(data, forKey: "journey.weather.cache") }
        return result
    }
}

private struct JourneyWeatherView: View {
    let dayID: UUID
    let date: Date
    let suggestedCity: String
    @State private var city = ""
    @State private var draft = ""
    @State private var forecast: JourneyWeatherService.Forecast?
    @State private var message = "查看天气"
    @State private var loading = false
    @State private var details = false
    @State private var retry = 0
    private var dateKey: String { let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX"); return formatter.string(from: date) }
    private var weather: JourneyWeatherDay? { forecast?.daily.first { $0.fxDate == dateKey } }
    private var eligible: Bool { let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? -1; return (0...6).contains(days) }
    var body: some View {
        Button { draft = city; details = true } label: {
            HStack(spacing: 8) {
                Image(systemName: weather?.symbol ?? "questionmark.circle")
                    .frame(width: 24, height: 24)
                if loading { ProgressView() }
                VStack(alignment: .leading, spacing: 3) {
                    Text(weather.map { "\($0.textDay) · \($0.tempMin)–\($0.tempMax)℃" } ?? message)
                    if let forecast { Text(forecast.city).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .font(.subheadline)
            .padding(12)
            .background(Color.tripLake.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .task(id: dayID.uuidString + suggestedCity) {
            city = suggestedCity
        }
        .task(id: city + dateKey + String(retry)) {
            forecast = nil
            guard eligible else { message = date < Calendar.current.startOfDay(for: Date()) ? "不提供历史天气" : "暂未进入预报范围"; return }
            guard !city.isEmpty else { message = "选择城市查看天气"; return }
            loading = true; message = "正在获取天气…"
            defer { loading = false }
            do {
                let result = try await JourneyWeatherService.shared.forecast(city: city)
                try Task.checkCancellation()
                forecast = result
                message = result.daily.contains { $0.fxDate == dateKey } ? "" : "暂无当天预报"
            } catch is CancellationError { } catch { message = "天气暂不可用，点击重试或更换城市" }
        }
        .sheet(isPresented: $details) {
            NavigationStack {
                Form {
                    Section("查询城市") {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(.secondary)
                            TextField("输入城市，例如杭州", text: $draft)
                                .submitLabel(.search)
                                .onSubmit { queryWeather() }
                            Button(action: queryWeather) {
                                Text("查询")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.tripLake.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.tripLake)
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading)
                        }
                        .padding(.vertical, 4)
                    }
                    Section {
                        if loading {
                            ProgressView("正在获取天气…")
                                .padding(.vertical, 20)
                        } else if let weather {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(forecast?.city ?? city)
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Text("\(weather.tempMin)–\(weather.tempMax)℃")
                                        .font(.largeTitle.weight(.semibold))
                                    Text(weather.textDay)
                                        .font(.headline).foregroundStyle(Color.tripLake)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: weather.symbol)
                                    .font(.system(size: 36)).foregroundStyle(Color.tripLake)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 12)
                            LabeledContent("白天 / 夜间", value: "\(weather.textDay) / \(weather.textNight)")
                            LabeledContent("风", value: "\(weather.windDirDay) \(weather.windScaleDay)级")
                            LabeledContent("湿度", value: "\(weather.humidity)%")
                            LabeledContent("降水量", value: "\(weather.precip) mm")
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "cloud").font(.largeTitle)
                                Text(message).font(.subheadline).multilineTextAlignment(.center)
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                    } header: {
                        Text(date.formatted(.dateTime.month().day().weekday(.wide)))
                    } footer: {
                        if !loading, weather != nil, let updated = forecast?.updated, !updated.isEmpty {
                            Text("更新于 \(formattedUpdateTime(updated))")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("天气")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { details = false } } }
            }
        }

    }

    private func queryWeather() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !loading else { return }
        city = value
        retry += 1
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func formattedUpdateTime(_ value: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let parsed else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: parsed)
    }
}
