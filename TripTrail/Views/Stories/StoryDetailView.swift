import PhotosUI
import SwiftData
import SwiftUI
import UIKit

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
    @State private var placeMessage: String?

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
        .sheet(item: $entryToNavigate) { entry in
            NavigationOptionsSheet(
                onAmap: { openNavigation(for: entry) },
                onXiaohongshu: { openDiscovery(.xiaohongshu, for: entry) },
                onDouyin: { openDiscovery(.douyin, for: entry) }
            )
        }
        .fullScreenCover(item: $mediaPreview) { AssetMediaViewer(request: $0) }
        .alert("地点提示", isPresented: Binding(
            get: { placeMessage != nil },
            set: { if !$0 { placeMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { placeMessage = nil }
        } message: {
            Text(placeMessage ?? "")
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

            if !entry.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(entry.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StoryEntryMediaGallery(entry: entry) { media in
                mediaPreview = AssetMediaPreviewRequest(
                    items: entry.sortedMedia.map {
                        AssetMediaPreviewItem(identifier: $0.localIdentifier, kind: $0.kind)
                    },
                    initialIdentifier: media.localIdentifier
                )
            }
        }
        .storyEntrySurface()
    }

    private func storyEntryTitle(_ entry: StoryEntry) -> some View {
        Button { entryToNavigate = entry } label: {
            Label(entry.title, systemImage: entry.category.symbol).font(.headline)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel("打开\(entry.title)的地点选项")
        .accessibilityHint("可选择高德地图、小红书或抖音")
    }

    private func addDay() {
        let seed = JourneyHierarchyService.nextDaySeed(after: story.days, fallbackDate: story.startDate)
        let day = StoryDay(date: seed.date, title: seed.title, sortOrder: seed.sortOrder, story: story)
        story.days.append(day)
        dayToEdit = day
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
        for entry in day.entries { modelContext.delete(entry) }
        modelContext.delete(day)
    }

    private func openNavigation(for entry: StoryEntry) {
        Task {
            let opened = await AmapService.openPlace(
                name: entry.title,
                address: entry.address
            )
            if !opened {
                #if targetEnvironment(simulator)
                placeMessage = "当前 iPhone 模拟器没有安装高德地图 App。模拟器与手机是独立环境，请在已安装高德地图的真机上测试。"
                #else
                placeMessage = "未检测到高德地图 App，请确认已安装或更新到最新版本后重试。"
                #endif
            }
        }
    }

    private func openDiscovery(_ platform: PlaceDiscoveryPlatform, for entry: StoryEntry) {
        Task {
            let opened = await PlaceDiscoveryService.open(
                platform,
                name: entry.title,
                address: entry.address
            )
            if !opened {
                placeMessage = "暂时无法打开\(platform.displayName)，请检查网络或稍后重试。"
            }
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
            .background(Color.tripSurface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(Color.tripLake.opacity(0.22), lineWidth: 1)
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
                .offset(x: isOpen ? -actionPanelWidth : 0)
                .contentShape(Rectangle())
                .zIndex(1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .background {
            HorizontalSwipePanGesture { translation, velocity in
                finishDrag(translation: translation, velocity: velocity)
            }
        }
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

    private func finishDrag(translation: CGFloat, velocity: CGFloat) {
        let settledOffset = isOpen ? -actionPanelWidth : 0
        let projectedOffset = settledOffset + translation + velocity * 0.12
        let shouldOpen = projectedOffset < -(actionPanelWidth * 0.32)
        withAnimation(.snappy(duration: 0.22)) {
            isOpen = shouldOpen
        }
    }

    private func closeActions() {
        withAnimation(.snappy(duration: 0.18)) {
            isOpen = false
        }
    }
}

private struct HorizontalSwipePanGesture: UIViewRepresentable {
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEnded: onEnded)
    }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: AttachmentView, context: Context) {
        context.coordinator.onEnded = onEnded
        context.coordinator.install(on: uiView.window, attachment: uiView)
    }

    static func dismantleUIView(_ uiView: AttachmentView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: AttachmentView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    final class AttachmentView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.install(on: window, attachment: self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onEnded: (CGFloat, CGFloat) -> Void
        weak var attachment: AttachmentView?

        private lazy var panRecognizer: DirectionLockedPanGestureRecognizer = {
            let recognizer = DirectionLockedPanGestureRecognizer(
                target: self,
                action: #selector(handlePan(_:))
            )
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.maximumNumberOfTouches = 1
            return recognizer
        }()

        init(onEnded: @escaping (CGFloat, CGFloat) -> Void) {
            self.onEnded = onEnded
        }

        func install(on window: UIWindow?, attachment: AttachmentView) {
            self.attachment = attachment
            guard let window, panRecognizer.view !== window else { return }
            panRecognizer.view?.removeGestureRecognizer(panRecognizer)
            window.addGestureRecognizer(panRecognizer)
        }

        func uninstall() {
            panRecognizer.view?.removeGestureRecognizer(panRecognizer)
            attachment = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard
                let pan = gestureRecognizer as? UIPanGestureRecognizer,
                let attachment,
                let window = attachment.window,
                pan.view === window,
                window.rootViewController?.presentedViewController == nil
            else { return false }

            let location = pan.location(in: attachment)
            guard attachment.bounds.insetBy(dx: -1, dy: -1).contains(location) else { return false }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let window = recognizer.view else { return }
            let translation = recognizer.translation(in: window).x

            switch recognizer.state {
            case .ended:
                onEnded(translation, recognizer.velocity(in: window).x)
            default:
                break
            }
        }
    }

    /// Decides the axis while the recognizer is still `.possible`.
    /// A vertical move explicitly fails this recognizer, so the enclosing
    /// ScrollView receives the same touch sequence without waiting for a
    /// card-level pan gesture to finish.
    final class DirectionLockedPanGestureRecognizer: UIPanGestureRecognizer {
        private let decisionDistance: CGFloat = 5
        private var initialLocation: CGPoint?
        private var didChooseHorizontalAxis = false

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            initialLocation = touches.first?.location(in: view)
            didChooseHorizontalAxis = false
            super.touchesBegan(touches, with: event)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard !didChooseHorizontalAxis,
                  state == .possible,
                  let initialLocation,
                  let currentLocation = touches.first?.location(in: view)
            else {
                super.touchesMoved(touches, with: event)
                return
            }

            let horizontalDistance = abs(currentLocation.x - initialLocation.x)
            let verticalDistance = abs(currentLocation.y - initialLocation.y)
            guard max(horizontalDistance, verticalDistance) >= decisionDistance else { return }

            guard horizontalDistance > verticalDistance else {
                state = .failed
                return
            }

            didChooseHorizontalAxis = true
            super.touchesMoved(touches, with: event)
        }

        override func reset() {
            initialLocation = nil
            didChooseHorizontalAxis = false
            super.reset()
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
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
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
        _hasTime = State(initialValue: entry.startTime != nil || !entry.timeLabel.isEmpty)
        _startTime = State(initialValue: initialTimeRange.start)
        _endTime = State(initialValue: initialTimeRange.end)
        _note = State(initialValue: entry.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("安排") {
                    VStack(alignment: .leading, spacing: 6) {
                        editorFieldLabel("地点")
                        TextField("例如：湖滨酒店", text: $title)
                            .accessibilityLabel("地点")
                    }

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

    private func editorFieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var optionalTimeRow: some View {
        if hasTime {
            HStack(spacing: 8) {
                UnifiedTimeRangePicker(
                    title: "时间",
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
                    Text("时间").foregroundStyle(.primary)
                    Spacer()
                    Text("选填").foregroundStyle(.secondary)
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
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: remainingMediaSlots,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
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
            warnings.append("每个足迹安排最多可以添加 \(FootprintMediaPolicy.maximumCount) 个照片或视频，超出的素材未添加。")
        }
        mediaWarning = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        pickerItems = []
    }

    private func save() {
        entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
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
