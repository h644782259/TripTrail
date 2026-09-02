import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private struct StoryDaySectionValue: Identifiable {
    let id: UUID
    let index: Int
    let day: StoryDay
}

struct StoryDetailView: View {
    private struct StoryNavigationRequest: Identifiable {
        let id = UUID()
        let entry: StoryEntry
        let target: JourneyLocationTarget
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.startDate, order: .forward) private var trips: [Trip]
    @Bindable var story: TravelStory
    @State private var editingStory = false
    @State private var shareRequest: StoryShareRequest?
    @State private var entryEditRequest: StoryEntryEditRequest?
    @State private var dayEditRequest: StoryDayEditRequest?
    @State private var dayToDelete: StoryDay?
    @State private var entryToDelete: StoryEntry?
    @State private var isConfirmingStoryDeletion = false
    @State private var mediaPreview: AssetMediaPreviewRequest?
    @State private var entryNavigationRequest: StoryNavigationRequest?
    @State private var placeMessage: String?
    @State private var selectedDayID: UUID?
    @State private var expandedDayID: UUID?
    @State private var coverPickerItems: [PhotosPickerItem] = []
    @State private var showsCoverActions = false
    @State private var showsCoverPicker = false
    @State private var coverCropRequest: StoryCoverCropRequest?
    @State private var coverMessage: String?
    @State private var syncMessage: String?
    @State private var offersPhotoSettingsForCover = false

    private var sourceTrip: Trip? {
        guard let sourceTripID = story.sourceTripID else { return nil }
        return trips.first { $0.id == sourceTripID }
    }

    private var daySectionValues: [StoryDaySectionValue] {
        story.sortedDays.enumerated().map { index, day in
            StoryDaySectionValue(id: day.id, index: index, day: day)
        }
    }

    var body: some View {
        deletionAlertContent
            .task {
                StorySyncService.ensureHierarchy(for: story)
                _ = StorySyncService.migrateLegacyLocations(for: story, from: sourceTrip)
                if selectedDayID == nil, let firstDay = story.sortedDays.first {
                    selectedDayID = firstDay.id
                    expandedDayID = firstDay.id
                }
            }
    }

    private var storyContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    cover
                    storyDaySections
                }
                .padding()
                .padding(.bottom, 96)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                dayNavigator(proxy: proxy)
            }
        }
    }

    private var sheetContent: some View {
        storyContent
        .scrollDismissesKeyboard(.interactively)
        .background(Color.tripCanvas)
        .navigationTitle("足迹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                storyActionsMenu
            }
        }
        .sheet(isPresented: $editingStory) { StoryEditorView(story: story) }
        .sheet(item: $shareRequest) { request in
            ShareExportView(story: story, initialScopeID: request.scopeID)
        }
        .sheet(item: $entryEditRequest) { request in
            StoryEntryEditorView(entry: request.entry, isNew: request.isNew)
        }
        .sheet(item: $dayEditRequest) { request in
            StoryDayEditorView(
                day: request.day,
                isNew: request.isNew,
                onCancel: { cancelNewDay(request) }
            )
        }
        .sheet(item: $coverCropRequest) { request in
            StoryCoverCropView(request: request) { result in
                applyCoverCrop(result)
                coverCropRequest = nil
            }
        }
        .sheet(item: $entryNavigationRequest) { request in
            NavigationOptionsSheet(
                onAmap: { openNavigation(for: request) },
                onXiaohongshu: { openDiscovery(.xiaohongshu, for: request) },
                onDouyin: { openDiscovery(.douyin, for: request) }
            )
        }
    }

    private var coverPresentationContent: some View {
        sheetContent
        .fullScreenCover(item: $mediaPreview) { AssetMediaViewer(request: $0) }
        .confirmationDialog(
            "",
            isPresented: $showsCoverActions,
            titleVisibility: .hidden
        ) {
            Button("选择照片", systemImage: "photo.on.rectangle") {
                DispatchQueue.main.async { requestCoverPicker() }
            }
            if story.coverMedia != nil {
                Button("调整裁剪", systemImage: "crop") {
                    DispatchQueue.main.async { editCurrentCoverCrop() }
                }
                Button("恢复默认", systemImage: "arrow.counterclockwise") {
                    resetCover()
                }
            }
        }
        .photosPicker(
            isPresented: $showsCoverPicker,
            selection: $coverPickerItems,
            maxSelectionCount: 1,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: coverPickerItems) { _, items in
            consumeCoverPickerItems(items)
        }
    }

    private var informationalAlertContent: some View {
        coverPresentationContent
        .alert("地点提示", isPresented: Binding(
            get: { placeMessage != nil },
            set: { if !$0 { placeMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { placeMessage = nil }
        } message: {
            Text(placeMessage ?? "")
        }
        .alert("封面图片", isPresented: Binding(
            get: { coverMessage != nil },
            set: {
                if !$0 {
                    coverMessage = nil
                    offersPhotoSettingsForCover = false
                }
            }
        )) {
            Button("知道了", role: .cancel) {
                coverMessage = nil
                offersPhotoSettingsForCover = false
            }
            if offersPhotoSettingsForCover {
                Button("去设置") {
                    coverMessage = nil
                    offersPhotoSettingsForCover = false
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text(coverMessage ?? "")
        }
        .storySyncAlert($syncMessage)
    }

    private var deletionAlertContent: some View {
        informationalAlertContent
        .alert(HierarchyDeletionCopy.storyTitle, isPresented: $isConfirmingStoryDeletion) {
            Button(HierarchyDeletionCopy.confirmationButtonTitle, role: .destructive) {
                modelContext.delete(story)
                dismiss()
            }
            Button(HierarchyDeletionCopy.cancelButtonTitle, role: .cancel) {}
        } message: {
            Text(HierarchyDeletionCopy.storyMessage(title: story.title))
        }
        .alert(
            HierarchyDeletionCopy.storyDayTitle,
            isPresented: Binding(
                get: { dayToDelete != nil },
                set: { if !$0 { dayToDelete = nil } }
            ),
            presenting: dayToDelete
        ) { day in
            Button(HierarchyDeletionCopy.confirmationButtonTitle, role: .destructive) {
                delete(day: day)
                dayToDelete = nil
            }
            Button(HierarchyDeletionCopy.cancelButtonTitle, role: .cancel) { dayToDelete = nil }
        } message: { day in
            Text(HierarchyDeletionCopy.storyDayMessage(title: displayTitle(for: day)))
        }
        .alert(
            HierarchyDeletionCopy.storyEntryTitle,
            isPresented: Binding(
                get: { entryToDelete != nil },
                set: { if !$0 { entryToDelete = nil } }
            ),
            presenting: entryToDelete
        ) { entry in
            Button(HierarchyDeletionCopy.confirmationButtonTitle, role: .destructive) {
                modelContext.delete(entry)
                entryToDelete = nil
            }
            Button(HierarchyDeletionCopy.cancelButtonTitle, role: .cancel) { entryToDelete = nil }
        } message: { entry in
            Text(HierarchyDeletionCopy.storyEntryMessage(title: entry.title))
        }
    }

    private var storyActionsMenu: some View {
        Menu {
            Button("编辑足迹", systemImage: "pencil") { editingStory = true }
            if sourceTrip != nil {
                Button("同步最新旅程", systemImage: "arrow.triangle.2.circlepath", action: syncLatestTrip)
            }
            Button("分享足迹", systemImage: "square.and.arrow.up") {
                shareRequest = StoryShareRequest(scopeID: story.id)
            }
            Divider()
            Button("删除足迹", systemImage: "trash", role: .destructive) {
                isConfirmingStoryDeletion = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func syncLatestTrip() {
        guard let sourceTrip else { return }
        let report = StorySyncService.sync(
            story: story,
            from: sourceTrip,
            modelContext: modelContext
        )
        syncMessage = report.message
    }

    private var storyDaySections: some View {
        ForEach(daySectionValues) { value in
            storyDaySection(
                value.day,
                index: value.index,
                isExpanded: expandedDayID == value.id
            )
            .id(value.id)
        }
    }

    private func storyDaySection(_ day: StoryDay, index: Int, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Button {
                    selectedDayID = day.id
                    withAnimation(.snappy(duration: 0.22)) {
                        expandedDayID = isExpanded ? nil : day.id
                    }
                } label: {
                    HStack(spacing: 11) {
                        Capsule()
                            .fill(Color.tripLake)
                            .frame(width: 4, height: 34)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(day.title.isEmpty ? "第 \(index + 1) 天" : day.title)
                                .font(.headline)
                                .foregroundStyle(Color.tripInk)
                            Text("\(day.date.formatted(.dateTime.year().month().day().weekday(.wide))) · \(day.sortedEntries.count) 个记录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
                .accessibilityLabel("\(displayTitle(for: day))，\(day.sortedEntries.count) 个记录")
                .accessibilityValue(isExpanded ? "已展开" : "已收起")

                Menu {
                    Button("编辑当天", systemImage: "pencil") {
                        dayEditRequest = StoryDayEditRequest(day: day, isNew: false, previousDayID: nil)
                    }
                    Button("添加记录", systemImage: "plus") { addEntry(to: day) }
                    Button("分享当天", systemImage: "square.and.arrow.up") {
                        shareRequest = StoryShareRequest(scopeID: day.id)
                    }
                    Divider()
                    Button("删除当天", systemImage: "trash", role: .destructive) { dayToDelete = day }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("当天更多操作")
            }

            if isExpanded {
                if !day.cardSummary.isEmpty {
                    Text(day.cardSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if day.sortedEntries.isEmpty {
                    Button { addEntry(to: day) } label: {
                        Label("添加记录", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                } else {
                    ForEach(day.sortedEntries) { entry in
                        CardSwipeActionContainer(
                            cornerRadius: 19,
                            editTitle: "编辑记录",
                            deleteTitle: "删除记录",
                            onEdit: {
                                entryEditRequest = StoryEntryEditRequest(entry: entry, isNew: false)
                            },
                            onDelete: {
                                entryToDelete = entry
                            }
                        ) {
                            entryCard(entry)
                        }
                    }
                    Button { addEntry(to: day) } label: {
                        Label("添加记录", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.subheadline.bold())
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.tripLake)
                    .padding(.top, 2)
                }
            } else {
                if !day.cardSummary.isEmpty {
                    Text(day.cardSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .storyDayGroupSurface()
    }

    private func dayNavigator(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(daySectionValues) { value in
                        let day = value.day
                        let isSelected = (selectedDayID ?? daySectionValues.first?.id) == value.id
                        Button {
                            selectDay(day, proxy: proxy)
                        } label: {
                            VStack(spacing: 2) {
                                Text("第 \(value.index + 1) 天")
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
                        .buttonStyle(.plain)
                        .accessibilityLabel("第 \(value.index + 1) 天，\(day.date.chineseDateText)")
                        .accessibilityValue(isSelected ? "当前选择" : "")
                    }
                }
                .padding(.leading, 16)
                .padding(.vertical, 8)
            }

            Button { addDay() } label: {
                Image(systemName: "plus")
                    .font(.headline.bold())
                    .foregroundStyle(Color.tripLake)
                    .frame(width: 44, height: 44)
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

    private func selectDay(_ day: StoryDay, proxy: ScrollViewProxy) {
        let dayID = day.id

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedDayID = dayID
            expandedDayID = dayID
        }

        // Wait until the newly expanded day has completed one layout pass.
        // Scrolling while the old day collapses and the new day expands can
        // make SwiftUI repeatedly resolve a moving scroll target.
        Task { @MainActor in
            await Task.yield()
            guard selectedDayID == dayID else { return }

            var scrollTransaction = Transaction()
            scrollTransaction.disablesAnimations = true
            withTransaction(scrollTransaction) {
                proxy.scrollTo(dayID, anchor: .top)
            }
        }
    }

    private var cover: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !story.destination.isEmpty {
                Text(story.destination.uppercased())
                    .font(.caption.bold()).tracking(2).foregroundStyle(Color.tripSand)
            }
            Text(story.title).font(.largeTitle.bold())
            if !story.summary.isEmpty {
                Text(story.summary).font(.body).foregroundStyle(.white.opacity(0.88))
            }
            Text("\(story.startDate.chineseDateText) — \(story.endDate.chineseDateText)")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background {
            StoryCoverArtwork(story: story)
                .overlay(Color.black.opacity(story.coverMedia == nil ? 0 : 0.34))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onLongPressGesture(minimumDuration: 0.45) {
            showsCoverActions = true
        }
        .accessibilityHint("长按可以更换封面")
        .accessibilityAction(named: "更换封面") {
            showsCoverActions = true
        }
    }

    private func requestCoverPicker() {
        Task { @MainActor in
            let authorization = await PhotoLibraryService.requestReadWriteAccessIfNeeded()
            if authorization == .authorized || authorization == .limited {
                showsCoverPicker = true
            } else {
                offersPhotoSettingsForCover = authorization == .denied || authorization == .restricted
                coverMessage = PhotoLibraryService.permissionGuidance
            }
        }
    }

    private func consumeCoverPickerItems(_ items: [PhotosPickerItem]) {
        guard let item = items.first else { return }
        coverPickerItems = []
        Task { @MainActor in
            guard
                let identifier = item.itemIdentifier,
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                coverMessage = "无法读取这张图片，请重新选择。"
                return
            }
            coverCropRequest = StoryCoverCropRequest(
                assetIdentifier: identifier,
                image: image,
                zoom: 1,
                offsetX: 0,
                offsetY: 0
            )
        }
    }

    private func editCurrentCoverCrop() {
        guard let media = story.coverMedia else { return }
        Task { @MainActor in
            guard let image = await PhotoLibraryService.displayImage(identifier: media.localIdentifier) else {
                coverMessage = "封面原图已不可用，请重新选择。"
                return
            }
            coverCropRequest = StoryCoverCropRequest(
                assetIdentifier: media.localIdentifier,
                image: image,
                zoom: story.coverZoom,
                offsetX: story.coverOffsetX,
                offsetY: story.coverOffsetY
            )
        }
    }

    private func applyCoverCrop(_ result: StoryCoverCropResult) {
        if story.coverMedia?.localIdentifier != result.assetIdentifier {
            if let existing = story.coverMedia {
                story.coverMedia = nil
                modelContext.delete(existing)
            }
            let reference = MediaReference(localIdentifier: result.assetIdentifier, kind: .image)
            reference.storyCover = story
            story.coverMedia = reference
            modelContext.insert(reference)
        }
        story.coverZoom = result.zoom
        story.coverOffsetX = result.offsetX
        story.coverOffsetY = result.offsetY
    }

    private func resetCover() {
        if let media = story.coverMedia {
            story.coverMedia = nil
            modelContext.delete(media)
        }
        story.coverZoom = 1
        story.coverOffsetX = 0
        story.coverOffsetY = 0
    }

    private func entryCard(_ entry: StoryEntry) -> some View {
        let presentation = FootprintEntryPresentation(entry: entry)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                storyEntryTitle(entry)
                Spacer()
                if !entry.timeLabel.isEmpty {
                    Text(entry.timeLabel).font(.caption).foregroundStyle(.secondary)
                }
            }

            ForEach(entry.locationTargets) { target in
                Button {
                    entryNavigationRequest = StoryNavigationRequest(entry: entry, target: target)
                } label: {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: target.role == .origin ? "location.circle" : "mappin.circle.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(target.role.displayName)：\(target.displayName)")
                            let address = target.address.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !address.isEmpty, address != target.displayName {
                                Text(address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.tripLake)
                }
                .buttonStyle(.plain)
                .accessibilityHint("可选择高德地图、小红书或抖音")
            }

            StoryEntryMediaGallery(entry: entry) { media in
                mediaPreview = AssetMediaPreviewRequest(
                    items: entry.sortedMedia.map {
                        AssetMediaPreviewItem(identifier: $0.localIdentifier, kind: $0.kind)
                    },
                    initialIdentifier: media.localIdentifier
                )
            }

            if !presentation.memoryText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("回忆", systemImage: "quote.opening")
                        .font(.caption.bold())
                        .foregroundStyle(Color.tripLake)
                    Text(presentation.memoryText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !presentation.sourceDetailsText.isEmpty {
                DisclosureGroup {
                    Text(presentation.sourceDetailsText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                } label: {
                    Label("来自原旅程", systemImage: "link")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .tint(Color.tripLake)
            }
        }
        .storyEntrySurface()
    }

    private func storyEntryTitle(_ entry: StoryEntry) -> some View {
        Label(entry.title, systemImage: entry.category.symbol).font(.headline)
        .foregroundStyle(.primary)
    }

    private func addDay() {
        let previousDayID = selectedDayID
        let seed = JourneyHierarchyService.nextDaySeed(after: story.days, fallbackDate: story.startDate)
        let day = StoryDay(date: seed.date, title: seed.title, sortOrder: seed.sortOrder, story: story)
        story.days.append(day)
        selectedDayID = day.id
        expandedDayID = day.id
        dayEditRequest = StoryDayEditRequest(day: day, isNew: true, previousDayID: previousDayID)
    }

    private func cancelNewDay(_ request: StoryDayEditRequest) {
        guard request.isNew else { return }
        story.days.removeAll { $0.id == request.day.id }
        modelContext.delete(request.day)
        let fallbackID = request.previousDayID ?? story.sortedDays.first?.id
        selectedDayID = fallbackID
        expandedDayID = fallbackID
    }

    private func addEntry(to day: StoryDay) {
        let entry = StoryEntry(title: "", category: .attraction, sortOrder: day.entries.count)
        entry.story = story
        entry.storyDay = day
        story.entries.append(entry)
        day.entries.append(entry)
        entryEditRequest = StoryEntryEditRequest(entry: entry, isNew: true)
    }

    private func displayTitle(for day: StoryDay) -> String {
        if !day.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return day.title
        }
        let index = story.sortedDays.firstIndex { $0.id == day.id } ?? 0
        return "第 \(index + 1) 天"
    }

    private func delete(day: StoryDay) {
        let remainingDays = story.sortedDays.filter { $0.id != day.id }
        for entry in day.entries { modelContext.delete(entry) }
        modelContext.delete(day)
        if selectedDayID == day.id || expandedDayID == day.id {
            selectedDayID = remainingDays.first?.id
            expandedDayID = remainingDays.first?.id
        }
    }

    private func openNavigation(for request: StoryNavigationRequest) {
        Task {
            let result = await AmapService.openPlace(
                name: request.target.name,
                address: request.target.address
            )
            placeMessage = result.message(destinationName: request.target.displayName)
        }
    }

    private func openDiscovery(_ platform: PlaceDiscoveryPlatform, for request: StoryNavigationRequest) {
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

}

private struct StoryCoverCropRequest: Identifiable {
    let id = UUID()
    let assetIdentifier: String
    let image: UIImage
    let zoom: Double
    let offsetX: Double
    let offsetY: Double
}

private struct StoryCoverCropResult {
    let assetIdentifier: String
    let zoom: Double
    let offsetX: Double
    let offsetY: Double
}

struct StoryCoverArtwork: View {
    @Bindable var story: TravelStory
    var targetSize = CGSize(width: 2_000, height: 2_000)
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [.tripInk, .tripLake],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if let image {
                    CroppedStoryCoverImage(
                        image: image,
                        cropSize: proxy.size,
                        zoom: story.coverZoom,
                        offsetX: story.coverOffsetX,
                        offsetY: story.coverOffsetY
                    )
                }
            }
        }
        .task(id: "\(story.coverMedia?.localIdentifier ?? "")-\(Int(targetSize.width))x\(Int(targetSize.height))") {
            image = nil
            guard let identifier = story.coverMedia?.localIdentifier else { return }
            image = await PhotoLibraryService.displayImage(
                identifier: identifier,
                targetSize: targetSize
            )
        }
    }
}

private struct CroppedStoryCoverImage: View {
    let image: UIImage
    let cropSize: CGSize
    let zoom: Double
    let offsetX: Double
    let offsetY: Double

    var body: some View {
        let layout = StoryCoverCropGeometry.layout(
            imageSize: image.size,
            cropSize: cropSize,
            zoom: zoom
        )
        ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: layout.baseSize.width, height: layout.baseSize.height)
                .scaleEffect(layout.zoom)
                .offset(
                    x: layout.maximumOffset.width * CGFloat(max(-1, min(1, offsetX))),
                    y: layout.maximumOffset.height * CGFloat(max(-1, min(1, offsetY)))
                )
        }
        .frame(width: cropSize.width, height: cropSize.height)
        .clipped()
    }
}

private enum StoryCoverCropGeometry {
    struct Layout {
        let baseSize: CGSize
        let zoom: CGFloat
        let maximumOffset: CGSize
    }

    static func layout(imageSize: CGSize, cropSize: CGSize, zoom: Double) -> Layout {
        guard imageSize.width > 0, imageSize.height > 0, cropSize.width > 0, cropSize.height > 0 else {
            return Layout(baseSize: cropSize, zoom: 1, maximumOffset: .zero)
        }
        let fillScale = max(cropSize.width / imageSize.width, cropSize.height / imageSize.height)
        let baseSize = CGSize(width: imageSize.width * fillScale, height: imageSize.height * fillScale)
        let safeZoom = CGFloat(max(1, min(4, zoom)))
        return Layout(
            baseSize: baseSize,
            zoom: safeZoom,
            maximumOffset: CGSize(
                width: max(0, (baseSize.width * safeZoom - cropSize.width) / 2),
                height: max(0, (baseSize.height * safeZoom - cropSize.height) / 2)
            )
        )
    }
}

private struct StoryCoverCropView: View {
    @Environment(\.dismiss) private var dismiss
    let request: StoryCoverCropRequest
    let onConfirm: (StoryCoverCropResult) -> Void

    @State private var zoom: Double
    @State private var offsetX: Double
    @State private var offsetY: Double
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1

    init(request: StoryCoverCropRequest, onConfirm: @escaping (StoryCoverCropResult) -> Void) {
        self.request = request
        self.onConfirm = onConfirm
        _zoom = State(initialValue: max(1, min(4, request.zoom)))
        _offsetX = State(initialValue: max(-1, min(1, request.offsetX)))
        _offsetY = State(initialValue: max(-1, min(1, request.offsetY)))
    }

    var body: some View {
        TripNavigationStack {
            VStack(spacing: 22) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let cropSize = CGSize(width: width, height: width / 1.86)
                    let liveZoom = max(1, min(4, zoom * Double(magnification)))
                    let layout = StoryCoverCropGeometry.layout(
                        imageSize: request.image.size,
                        cropSize: cropSize,
                        zoom: liveZoom
                    )
                    let liveX = normalizedOffset(
                        stored: offsetX,
                        translation: dragTranslation.width,
                        maximum: layout.maximumOffset.width
                    )
                    let liveY = normalizedOffset(
                        stored: offsetY,
                        translation: dragTranslation.height,
                        maximum: layout.maximumOffset.height
                    )

                    CroppedStoryCoverImage(
                        image: request.image,
                        cropSize: cropSize,
                        zoom: liveZoom,
                        offsetX: liveX,
                        offsetY: liveY
                    )
                    .frame(width: cropSize.width, height: cropSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.75), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                    .gesture(dragGesture(cropSize: cropSize, zoom: liveZoom))
                    .simultaneousGesture(magnificationGesture)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(height: 220)

                VStack(alignment: .leading, spacing: 10) {
                    Label("拖动调整取景，双指或滑块缩放", systemImage: "crop")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: $zoom, in: 1...4)
                        Image(systemName: "plus.magnifyingglass")
                    }
                    Button("重置取景") {
                        withAnimation(.snappy) {
                            zoom = 1
                            offsetX = 0
                            offsetY = 0
                        }
                    }
                    .font(.subheadline.bold())
                }

                Spacer()
            }
            .padding()
            .background(Color.tripCanvas.ignoresSafeArea())
            .navigationTitle("裁剪封面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("使用") {
                        onConfirm(
                            StoryCoverCropResult(
                                assetIdentifier: request.assetIdentifier,
                                zoom: zoom,
                                offsetX: offsetX,
                                offsetY: offsetY
                            )
                        )
                        dismiss()
                    }
                }
            }
        }
    }

    private func normalizedOffset(stored: Double, translation: CGFloat, maximum: CGFloat) -> Double {
        guard maximum > 0.5 else { return 0 }
        return max(-1, min(1, stored + Double(translation / maximum)))
    }

    private func dragGesture(cropSize: CGSize, zoom: Double) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let layout = StoryCoverCropGeometry.layout(
                    imageSize: request.image.size,
                    cropSize: cropSize,
                    zoom: zoom
                )
                offsetX = normalizedOffset(
                    stored: offsetX,
                    translation: value.translation.width,
                    maximum: layout.maximumOffset.width
                )
                offsetY = normalizedOffset(
                    stored: offsetY,
                    translation: value.translation.height,
                    maximum: layout.maximumOffset.height
                )
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($magnification) { value, state, _ in
                state = value
            }
            .onEnded { value in
                zoom = max(1, min(4, zoom * Double(value)))
            }
    }
}

private struct StoryDayGroupSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                LinearGradient(
                    colors: [
                        Color.tripLake.opacity(0.11),
                        Color.tripMist.opacity(0.13),
                        Color.tripSurface.opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.tripLake.opacity(0.23), lineWidth: 1)
            }
    }
}

private struct StoryEntrySurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Color.tripSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.tripLake.opacity(0.18), lineWidth: 0.8)
            }
    }
}

private struct FootprintEntryPresentation {
    let sourceDetailsText: String
    let memoryText: String

    init(entry: StoryEntry) {
        let rawNote = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceText = entry.sourceMemoryPrefill?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var sourceParts: [String] = []
        if !sourceText.isEmpty {
            let segments = sourceText
                .split(separator: "；")
                .map {
                    String($0).trimmingCharacters(
                        in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "。；"))
                    )
                }
                .filter { !$0.isEmpty }

            for segment in segments {
                if segment.hasPrefix("类型：")
                    || segment.hasPrefix("地点：")
                    || segment.hasPrefix("地址：") {
                    continue
                }
                if segment.hasPrefix("补充：") {
                    let value = String(segment.dropFirst(3))
                    if !value.isEmpty { sourceParts.append("原说明：\(value)") }
                    continue
                }
                sourceParts.append(segment)
            }
        }

        sourceDetailsText = sourceParts.joined(separator: "\n")
        memoryText = rawNote == sourceText ? "" : rawNote
    }
}

private extension View {
    func storyDayGroupSurface() -> some View { modifier(StoryDayGroupSurface()) }
    func storyEntrySurface() -> some View { modifier(StoryEntrySurface()) }

    func storySyncAlert(_ message: Binding<String?>) -> some View {
        alert("同步最新旅程", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("知道了", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

private struct StoryEntryMediaGallery: View {
    let entry: StoryEntry
    let onSelect: (MediaReference) -> Void

    private var sortedMedia: [MediaReference] { entry.sortedMedia }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        if !sortedMedia.isEmpty {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(sortedMedia.enumerated()), id: \.element.id) { index, media in
                    Button {
                        onSelect(media)
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
                    // Constrain the control itself, not only its visible label. A tall
                    // PHAsset must not leave an invisible tappable area below the tile.
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel(media.kind == .video ? "第 \(index + 1) 个视频" : "第 \(index + 1) 张照片")
                    .accessibilityHint("打开大图，可左右滑动切换")
                }
            }
        }
    }
}

enum StoryMediaDeletionService {
    static func remove(_ media: MediaReference, from entry: StoryEntry, in modelContext: ModelContext) {
        entry.media.removeAll { $0.id == media.id }
        modelContext.delete(media)

        for (index, reference) in entry.sortedMedia.enumerated() {
            reference.sortOrder = index
        }
    }
}

private struct StoryShareRequest: Identifiable {
    let id = UUID()
    let scopeID: UUID
}

private struct StoryEntryEditRequest: Identifiable {
    let id = UUID()
    let entry: StoryEntry
    let isNew: Bool
}

private struct StoryDayEditRequest: Identifiable {
    let id = UUID()
    let day: StoryDay
    let isNew: Bool
    let previousDayID: UUID?
}

struct StoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var story: TravelStory

    var body: some View {
        TripNavigationStack {
            Form {
                TextField("游记标题", text: $story.title)
                TextField("目的地", text: $story.destination)
                TwoTapDateRangePicker(
                    title: "游记日期",
                    startTitle: "开始",
                    endTitle: "结束",
                    startDate: $story.startDate,
                    endDate: $story.endDate
                )
                TextField("旅行摘要", text: $story.summary, axis: .vertical).lineLimit(5...12)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("编辑足迹")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

private struct StoryDayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var day: StoryDay
    let isNew: Bool
    let onCancel: () -> Void
    @State private var didFinish = false

    var body: some View {
        TripNavigationStack {
            Form {
                Section("基本信息") {
                    TextField("当天标题", text: $day.title)
                    DatePicker("日期", selection: $day.date, displayedComponents: .date)
                }
                Section("当天摘要") {
                    TextField("简要记录当天内容", text: $day.note, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("细节补充") {
                    TextField("补充当天的见闻、感受或其他细节", text: $day.details, axis: .vertical)
                        .lineLimit(5...14)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("编辑足迹日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isNew {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            didFinish = true
                            onCancel()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        didFinish = true
                        dismiss()
                    }
                }
            }
            .onDisappear {
                guard isNew, !didFinish else { return }
                didFinish = true
                onCancel()
            }
        }
    }
}

private struct StoryEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let entry: StoryEntry
    let isNew: Bool

    @State private var title: String
    @State private var locationMode: ArrangementLocationMode
    @State private var placeName: String
    @State private var placeAddress: String
    @State private var originName: String
    @State private var originAddress: String
    @State private var destinationName: String
    @State private var destinationAddress: String
    @State private var hasTime: Bool
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var note: String
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickedAssets: [PickedAsset] = []
    @State private var removedMediaIDs: Set<UUID> = []
    @State private var mediaWarning: String?
    @State private var mediaPreview: AssetMediaPreviewRequest?

    init(entry: StoryEntry, isNew: Bool = false) {
        self.entry = entry
        self.isNew = isNew
        let initialTimeRange = Self.initialTimeRange(for: entry)
        _title = State(initialValue: entry.title)
        let isLegacyEntry = entry.locationModeRaw.isEmpty
        _locationMode = State(initialValue: entry.locationMode)
        _placeName = State(initialValue: entry.placeName.isEmpty && isLegacyEntry ? entry.title : entry.placeName)
        _placeAddress = State(initialValue: entry.placeAddress.isEmpty && isLegacyEntry ? entry.address : entry.placeAddress)
        _originName = State(initialValue: entry.originName)
        _originAddress = State(initialValue: entry.originAddress)
        _destinationName = State(initialValue: entry.destinationName)
        _destinationAddress = State(initialValue: entry.destinationAddress)
        _hasTime = State(initialValue: entry.startTime != nil || !entry.timeLabel.isEmpty)
        _startTime = State(initialValue: initialTimeRange.start)
        _endTime = State(initialValue: initialTimeRange.end)
        _note = State(initialValue: entry.note)
    }

    var body: some View {
        TripNavigationStack {
            Form {
                Section("地点") {
                    Picker("地点类型", selection: $locationMode) {
                        ForEach(ArrangementLocationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if locationMode == .single {
                        TextField("地点名称", text: $placeName)
                        TextField("地点详细地址（选填）", text: $placeAddress)
                    } else {
                        TextField("出发地", text: $originName)
                        TextField("出发地详细地址（选填）", text: $originAddress)
                        TextField("目的地", text: $destinationName)
                        TextField("目的地详细地址（选填）", text: $destinationAddress)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        editorFieldLabel("记录标题（选填）")
                        TextField("不填则使用地点名称", text: $title)
                            .accessibilityLabel("记录标题，选填")
                    }
                }

                Section("时间（选填）") {
                    optionalTimeRow
                }

                Section("回忆") {
                    TextField("记录这段足迹的见闻和感受", text: $note, axis: .vertical)
                        .lineLimit(5...12)
                        .accessibilityLabel("回忆")
                }

                Section("照片与视频") {
                    mediaGrid(existing: visibleExistingMedia, picked: pickedAssets)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if isNew { modelContext.delete(entry) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!hasRequiredLocation)
                }
            }
            .onChange(of: pickerItems) { _, newValue in
                consumePickerItems(newValue)
            }
            .alert("相簿提示", isPresented: Binding(
                get: { mediaWarning != nil },
                set: { if !$0 { mediaWarning = nil } }
            )) {
                Button("知道了", role: .cancel) { mediaWarning = nil }
            } message: {
                Text(mediaWarning ?? "")
            }
            .fullScreenCover(item: $mediaPreview) { AssetMediaViewer(request: $0) }
        }
    }

    private func editorFieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var hasRequiredLocation: Bool {
        switch locationMode {
        case .single:
            !placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .route:
            !originName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !destinationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    @ViewBuilder
    private var optionalTimeRow: some View {
        if hasTime {
            HStack(spacing: 8) {
                UnifiedTimeRangePicker(
                    title: "起止时间",
                    startTitle: "开始",
                    endTitle: "结束",
                    startTime: $startTime,
                    endTime: $endTime,
                    separator: "～"
                )
                Button {
                    hasTime = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除时间")
            }
        } else {
            Button {
                hasTime = true
            } label: {
                HStack {
                    Text("起止时间").foregroundStyle(.primary)
                    Spacer()
                    Text("添加").foregroundStyle(.secondary)
                    Image(systemName: "plus.circle").foregroundStyle(Color.tripLake)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("添加起止时间")
        }
    }

    private static func initialTimeRange(for entry: StoryEntry) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        if let start = entry.startTime {
            let fallbackEnd = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
            return (start, max(start, entry.endTime ?? fallbackEnd))
        }

        let baseDate = entry.storyDay?.date ?? entry.story?.startDate ?? Date()
        let timeParts = entry.timeLabel.split { "–—-~～至".contains($0) }

        func date(from part: Substring) -> Date? {
            let components = part
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ":")
            guard components.count == 2,
                  let hour = Int(components[0]),
                  let minute = Int(components[1]),
                  (0...23).contains(hour),
                  (0...59).contains(minute)
            else { return nil }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate)
        }

        let defaultStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: baseDate) ?? baseDate
        let start = timeParts.first.flatMap(date(from:)) ?? defaultStart
        let fallbackEnd = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        let end = timeParts.dropFirst().first.flatMap(date(from:)) ?? fallbackEnd
        return (start, max(start, end))
    }

    private var visibleExistingMedia: [MediaReference] {
        entry.sortedMedia.filter { !removedMediaIDs.contains($0.id) }
    }

    private var remainingMediaSlots: Int {
        FootprintMediaPolicy.remainingSlots(
            existingCount: visibleExistingMedia.count,
            pendingCount: pickedAssets.count
        )
    }

    private var previewMediaItems: [AssetMediaPreviewItem] {
        visibleExistingMedia
            .map { AssetMediaPreviewItem(identifier: $0.localIdentifier, kind: $0.kind) }
        + pickedAssets
            .map { AssetMediaPreviewItem(identifier: $0.id, kind: $0.kind) }
    }

    @ViewBuilder
    private func mediaGrid(existing: [MediaReference], picked: [PickedAsset]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(existing) { reference in
                removableThumbnail(
                    identifier: reference.localIdentifier,
                    kind: reference.kind
                ) {
                    removedMediaIDs.insert(reference.id)
                }
            }

            ForEach(picked) { asset in
                removableThumbnail(identifier: asset.id, kind: asset.kind) {
                    pickedAssets.removeAll { $0.id == asset.id }
                }
            }

            if remainingMediaSlots > 0 {
                PermissionAwarePhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: remainingMediaSlots,
                    matching: .any(of: [.images, .videos])
                ) {
                    addMediaTile
                }
                .buttonStyle(.plain)
                .accessibilityLabel("从系统相簿添加照片或视频，还可添加 \(remainingMediaSlots) 个")
            }
        }
    }

    private var addMediaTile: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.tripLake.opacity(0.045))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        Color.tripLake.opacity(0.52),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            }
            .overlay {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color.tripLake)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func removableThumbnail(
        identifier: String,
        kind: MediaKind,
        onRemove: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    AssetThumbnail(identifier: identifier, showsVideoBadge: kind == .video)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture {
                    mediaPreview = AssetMediaPreviewRequest(
                        items: previewMediaItems,
                        initialIdentifier: identifier
                    )
                }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.58))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(3)
            .accessibilityLabel("移除这项素材")
        }
        .buttonStyle(.plain)
    }

    private func consumePickerItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let converted = PhotoLibraryService.pickedAssets(from: items)
        var warnings: [String] = []
        if converted.count != items.count {
            warnings.append("有 \(items.count - converted.count) 项无法读取相簿标识，请从系统“照片”中重选。当前权限：\(PhotoLibraryService.readableStatusText)。")
        }

        let activeExistingIDs = Set(entry.media
            .filter { !removedMediaIDs.contains($0.id) }
            .map(\.localIdentifier))
        let alreadyPickedIDs = Set(pickedAssets.map(\.id))
        let newAssets = converted.filter {
            !activeExistingIDs.contains($0.id) && !alreadyPickedIDs.contains($0.id)
        }
        let acceptedAssets = Array(newAssets.prefix(remainingMediaSlots))
        pickedAssets.append(contentsOf: acceptedAssets)
        if newAssets.count > acceptedAssets.count {
            warnings.append("每条足迹记录最多可以添加 \(FootprintMediaPolicy.maximumCount) 个照片或视频，超出的素材未添加。")
        }
        mediaWarning = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        pickerItems = []
    }

    private func save() {
        let customTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPlaceName = JourneyLocationText.entityName(from: placeName)
        let normalizedOriginName = JourneyLocationText.entityName(from: originName, role: .origin)
        let normalizedDestinationName = JourneyLocationText.entityName(from: destinationName, role: .destination)

        entry.locationMode = locationMode
        entry.placeName = normalizedPlaceName
        entry.placeAddress = placeAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.originName = normalizedOriginName
        entry.originAddress = originAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.destinationName = normalizedDestinationName
        entry.destinationAddress = destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let automaticTitle: String
        switch locationMode {
        case .single:
            automaticTitle = normalizedPlaceName
        case .route:
            automaticTitle = [normalizedOriginName, normalizedDestinationName]
                .filter { !$0.isEmpty }
                .joined(separator: " → ")
        }
        entry.title = customTitle.isEmpty ? automaticTitle : customTitle
        entry.address = locationMode == .single ? entry.placeAddress : entry.destinationAddress
        if hasTime {
            entry.startTime = startTime
            entry.endTime = endTime
            entry.timeLabel = "\(startTime.timeText)～\(endTime.timeText)"
        } else {
            entry.startTime = nil
            entry.endTime = nil
            entry.timeLabel = ""
        }
        entry.note = note

        for reference in entry.media where removedMediaIDs.contains(reference.id) {
            modelContext.delete(reference)
        }

        let activeMedia = entry.sortedMedia.filter { !removedMediaIDs.contains($0.id) }
        let acceptedPendingAssets = pickedAssets.prefix(
            FootprintMediaPolicy.remainingSlots(existingCount: activeMedia.count)
        )
        for (index, picked) in acceptedPendingAssets.enumerated() {
            let reference = MediaReference(
                localIdentifier: picked.id,
                kind: picked.kind,
                sortOrder: activeMedia.count + index
            )
            reference.storyEntry = entry
            entry.media.append(reference)
        }

        dismiss()
    }
}
