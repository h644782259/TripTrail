import PhotosUI
import SwiftData
import SwiftUI

struct StoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.startDate, order: .forward) private var trips: [Trip]
    @Bindable var story: TravelStory
    @State private var editingStory = false
    @State private var shareRequest: StoryShareRequest?
    @State private var entryEditRequest: StoryEntryEditRequest?
    @State private var dayToEdit: StoryDay?
    @State private var dayToDelete: StoryDay?
    @State private var entryToDelete: StoryEntry?
    @State private var isConfirmingStoryDeletion = false
    @State private var mediaPreview: AssetMediaPreviewRequest?
    @State private var syncMessage: String?
    @State private var entryToNavigate: StoryEntry?

    private var sourceTrip: Trip? {
        guard let sourceTripID = story.sourceTripID else { return nil }
        return trips.first { $0.id == sourceTripID }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                cover
                ForEach(Array(story.sortedDays.enumerated()), id: \.element.id) { index, day in
                    storyDaySection(day, index: index)
                }
                Button { addDay() } label: {
                    Label("添加一天", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.tripCanvas)
        .navigationTitle("足迹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let sourceTrip {
                        Button("同步足迹", systemImage: "arrow.triangle.2.circlepath") { sync(from: sourceTrip) }
                    }
                    Button("编辑足迹", systemImage: "pencil") { editingStory = true }
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
        }
        .sheet(isPresented: $editingStory) { StoryEditorView(story: story) }
        .sheet(item: $shareRequest) { request in
            ShareExportView(story: story, initialScopeID: request.scopeID)
        }
        .sheet(item: $entryEditRequest) { request in
            StoryEntryEditorView(entry: request.entry, isNew: request.isNew)
        }
        .sheet(item: $dayToEdit) { StoryDayEditorView(day: $0) }
        .fullScreenCover(item: $mediaPreview) { AssetMediaViewer(request: $0) }
        .alert(item: $entryToNavigate) { entry in
            Alert(
                title: Text("是否打开高德地图前往\(entry.title)"),
                primaryButton: .default(Text("打开高德地图")) { openNavigation(for: entry) },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .alert("足迹同步", isPresented: Binding(get: { syncMessage != nil }, set: { if !$0 { syncMessage = nil } })) {
            Button("好", role: .cancel) { syncMessage = nil }
        } message: { Text(syncMessage ?? "") }
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
        .task { StorySyncService.ensureHierarchy(for: story) }
    }

    private func storyDaySection(_ day: StoryDay, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Capsule()
                    .fill(Color.tripLake)
                    .frame(width: 4, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(day.title.isEmpty ? "第 \(index + 1) 天" : day.title)
                        .font(.headline)
                        .foregroundStyle(Color.tripInk)
                    Text(day.date.formatted(.dateTime.year().month().day().weekday(.wide)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                Spacer()
                Menu {
                    Button("编辑当天", systemImage: "pencil") { dayToEdit = day }
                    Button("添加足迹", systemImage: "plus") { addEntry(to: day) }
                    Button("分享当天", systemImage: "square.and.arrow.up") {
                        shareRequest = StoryShareRequest(scopeID: day.id)
                    }
                    Divider()
                    Button("删除当天", systemImage: "trash", role: .destructive) { dayToDelete = day }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("当天更多操作")
            }

            if !day.cardSummary.isEmpty {
                Text(day.cardSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if day.sortedEntries.isEmpty {
                Button { addEntry(to: day) } label: {
                    Label("添加足迹", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
            } else {
                ForEach(day.sortedEntries) { entry in
                    StoryEntrySwipeActionContainer {
                        entryEditRequest = StoryEntryEditRequest(entry: entry, isNew: false)
                    } onDelete: {
                        entryToDelete = entry
                    } content: {
                        entryCard(entry)
                    }
                }
                Button { addEntry(to: day) } label: {
                    Label("添加足迹", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline.bold())
                .buttonStyle(.plain)
                .foregroundStyle(Color.tripLake)
                .padding(.top, 2)
            }
        }
        .storyDayGroupSurface()
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
        .background(
            LinearGradient(colors: [.tripInk, .tripLake], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }

    private func entryCard(_ entry: StoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                storyEntryTitle(entry)
                Spacer()
                if !entry.timeLabel.isEmpty {
                    Text(entry.timeLabel).font(.caption).foregroundStyle(.secondary)
                }
            }

            InlineStoryEntryRecorder(entry: entry)

            if !entry.sortedMedia.isEmpty {
                StoryEntryMediaGallery(entry: entry) { media in
                    mediaPreview = AssetMediaPreviewRequest(
                        items: entry.sortedMedia.map {
                            AssetMediaPreviewItem(identifier: $0.localIdentifier, kind: $0.kind)
                        },
                        initialIdentifier: media.localIdentifier
                    )
                }
            }
            if !entry.routeInfo.isEmpty { Label(entry.routeInfo, systemImage: "figure.walk").font(.caption).foregroundStyle(.secondary) }
        }
        .storyEntrySurface()
        .padding(.leading, 7)
    }

    @ViewBuilder
    private func storyEntryTitle(_ entry: StoryEntry) -> some View {
        if (entry.latitude != nil && entry.longitude != nil) || !entry.address.isEmpty {
            Button { entryToNavigate = entry } label: {
                Label(entry.title, systemImage: entry.category.symbol).font(.headline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityHint("打开高德地图")
        } else {
            Label(entry.title, systemImage: entry.category.symbol).font(.headline)
        }
    }

    private func addDay() {
        let seed = JourneyHierarchyService.nextDaySeed(after: story.days, fallbackDate: story.startDate)
        let day = StoryDay(date: seed.date, title: seed.title, sortOrder: seed.sortOrder, story: story)
        story.days.append(day)
        dayToEdit = day
    }

    private func addEntry(to day: StoryDay) {
        let entry = StoryEntry(title: "新安排", category: .attraction, sortOrder: day.entries.count)
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
        for entry in day.entries { modelContext.delete(entry) }
        modelContext.delete(day)
    }

    private func openNavigation(for entry: StoryEntry) {
        Task {
            _ = await AmapService.openPlace(
                name: entry.title,
                address: entry.address,
                latitude: entry.latitude,
                longitude: entry.longitude
            )
        }
    }

    private func sync(from trip: Trip) {
        let report = StorySyncService.sync(story: story, from: trip, modelContext: modelContext)
        syncMessage = report.message
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
            .padding(16)
            .padding(.leading, 5)
            .background(Color.tripSurface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(Color.tripLake.opacity(0.22), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.tripLake.opacity(0.82))
                    .frame(width: 4)
                    .padding(.vertical, 18)
                    .padding(.leading, 7)
            }
            .shadow(color: Color.tripInk.opacity(0.09), radius: 12, y: 5)
    }
}

private extension View {
    func storyDayGroupSurface() -> some View { modifier(StoryDayGroupSurface()) }
    func storyEntrySurface() -> some View { modifier(StoryEntrySurface()) }
}

private struct StoryEntrySwipeActionContainer<Content: View>: View {
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
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .accessibilityAction(named: "编辑足迹", onEdit)
        .accessibilityAction(named: "删除足迹", onDelete)
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

private struct StoryEntryMediaGallery: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var entry: StoryEntry
    let onSelect: (MediaReference) -> Void

    @State private var mediaToDelete: MediaReference?

    var body: some View {
        StoryMediaCarousel(
            media: entry.sortedMedia,
            height: 220,
            onSelect: onSelect,
            onDelete: { mediaToDelete = $0 }
        )
        .confirmationDialog(
            mediaToDelete?.kind == .video ? "删除这个视频？" : "删除这张照片？",
            isPresented: Binding(
                get: { mediaToDelete != nil },
                set: { if !$0 { mediaToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let media = mediaToDelete else { return }
                delete(media)
                mediaToDelete = nil
            }
            Button("取消", role: .cancel) { mediaToDelete = nil }
        } message: {
            Text("仅从当前足迹中移除，不会删除系统相簿中的原文件。")
        }
    }

    private func delete(_ media: MediaReference) {
        StoryMediaDeletionService.remove(media, from: entry, in: modelContext)
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

private struct InlineStoryEntryRecorder: View {
    @Bindable var entry: StoryEntry

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("写下这一刻…", text: $entry.note, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.plain)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("记录\(entry.title)的回忆")

            InlineStoryEntryMediaPicker(entry: entry)
        }
    }
}

private struct InlineStoryEntryMediaPicker: View {
    @Bindable var entry: StoryEntry
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var mediaWarning: String?

    var body: some View {
        Group {
            if remainingSlots > 0 {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: remainingSlots,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
                ) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.tripLake, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("给\(entry.title)添加照片或视频，还可添加 \(remainingSlots) 个")
            } else {
                Image(systemName: "checkmark")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.secondary, in: Circle())
                    .accessibilityLabel("已达到 9 个照片或视频的上限")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text("\(min(entry.media.count, FootprintMediaPolicy.maximumCount))/\(FootprintMediaPolicy.maximumCount)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.black.opacity(0.62), in: Capsule())
                .offset(x: 5, y: 4)
                .allowsHitTesting(false)
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

    private var remainingSlots: Int {
        FootprintMediaPolicy.remainingSlots(existingCount: entry.media.count)
    }

    private func addMedia(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let converted = PhotoLibraryService.pickedAssets(from: items)
        var warnings: [String] = []
        if converted.count != items.count {
            warnings.append("有 \(items.count - converted.count) 项无法读取相簿标识，请从系统“照片”中重选。当前权限：\(PhotoLibraryService.readableStatusText)。")
        }

        let existingIDs = Set(entry.media.map(\.localIdentifier))
        let newAssets = converted.filter { !existingIDs.contains($0.id) }
        let acceptedAssets = Array(newAssets.prefix(remainingSlots))
        if newAssets.count > acceptedAssets.count {
            warnings.append("每个足迹安排最多可以添加 \(FootprintMediaPolicy.maximumCount) 个照片或视频，超出的素材未添加。")
        }
        let firstSortOrder = entry.media.count
        for (index, picked) in acceptedAssets.enumerated() {
            let reference = MediaReference(
                localIdentifier: picked.id,
                kind: picked.kind,
                sortOrder: firstSortOrder + index
            )
            reference.storyEntry = entry
            entry.media.append(reference)
        }
        mediaWarning = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        pickerItems = []
    }
}

struct StoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var story: TravelStory

    var body: some View {
        NavigationStack {
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

    var body: some View {
        NavigationStack {
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

private struct StoryEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let entry: StoryEntry
    let isNew: Bool

    @State private var title: String
    @State private var category: PlaceCategory
    @State private var timeLabel: String
    @State private var address: String
    @State private var routeInfo: String
    @State private var note: String
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickedAssets: [PickedAsset] = []
    @State private var removedMediaIDs: Set<UUID> = []
    @State private var mediaWarning: String?
    @State private var mediaPreview: AssetMediaPreviewRequest?

    init(entry: StoryEntry, isNew: Bool = false) {
        self.entry = entry
        self.isNew = isNew
        _title = State(initialValue: entry.title)
        _category = State(initialValue: entry.category)
        _timeLabel = State(initialValue: entry.timeLabel)
        _address = State(initialValue: entry.address)
        _routeInfo = State(initialValue: entry.routeInfo)
        _note = State(initialValue: entry.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("足迹信息") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("足迹名称")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("例如：断桥晨光", text: $title)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("类型")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("类型", selection: $category) {
                            ForEach(PlaceCategory.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("时间")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("例如：09:00–11:30", text: $timeLabel)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("地点")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("输入景点或地址", text: $address)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("路程信息")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("例如：步行 10 分钟", text: $routeInfo)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("回忆")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("记录这段足迹的见闻和感受", text: $note, axis: .vertical)
                            .lineLimit(5...12)
                    }
                }

                Section("照片与视频") {
                    if !visibleExistingMedia.isEmpty || !pickedAssets.isEmpty {
                        mediaGrid(existing: visibleExistingMedia, picked: pickedAssets)
                    } else {
                        ContentUnavailableView("还没有图片", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity, minHeight: 100)
                    }

                    if remainingMediaSlots > 0 {
                        PhotosPicker(
                            selection: $pickerItems,
                            maxSelectionCount: remainingMediaSlots,
                            matching: .any(of: [.images, .videos]),
                            photoLibrary: .shared()
                        ) {
                            Label("从系统相簿添加（还可选 \(remainingMediaSlots) 个）", systemImage: "photo.badge.plus")
                        }
                    } else {
                        Label("已达到 \(FootprintMediaPolicy.maximumCount) 个素材的上限", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("编辑足迹")
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
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
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
        }
    }

    private func removableThumbnail(
        identifier: String,
        kind: MediaKind,
        onRemove: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            AssetThumbnail(identifier: identifier, showsVideoBadge: kind == .video)
                .frame(height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
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
            }
            .padding(5)
            .accessibilityLabel("移除这项素材")
        }
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
            warnings.append("每个足迹安排最多可以添加 \(FootprintMediaPolicy.maximumCount) 个照片或视频，超出的素材未添加。")
        }
        mediaWarning = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        pickerItems = []
    }

    private func save() {
        entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.category = category
        entry.timeLabel = timeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.routeInfo = routeInfo.trimmingCharacters(in: .whitespacesAndNewlines)
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
