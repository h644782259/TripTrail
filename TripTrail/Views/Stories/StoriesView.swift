import SwiftData
import SwiftUI

struct StoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TravelStory.startDate, order: .reverse) private var stories: [TravelStory]
    @Query(sort: \Trip.startDate, order: .forward) private var trips: [Trip]
    @State private var storyToEdit: TravelStory?
    @State private var storyToShare: TravelStory?
    @State private var storyToDelete: TravelStory?
    @State private var creatingStory = false
    @State private var syncMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                if stories.isEmpty {
                    ContentUnavailableView {
                        Label("足迹还空着", systemImage: "book.closed")
                    } description: {
                        Text("新建足迹，或从旅程中收录。")
                    } actions: {
                        Button("新建足迹", systemImage: "plus") { creatingStory = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(minHeight: 360)
                } else {
                    header
                    ForEach(stories) { story in
                        StoryCard(
                            story: story,
                            canSync: sourceTrip(for: story) != nil,
                            onSync: { sync(story) },
                            onEdit: { storyToEdit = story },
                            onShare: { storyToShare = story },
                            onDelete: { storyToDelete = story }
                        )
                            .contextMenu {
                                if sourceTrip(for: story) != nil {
                                    Button("同步足迹", systemImage: "arrow.triangle.2.circlepath") { sync(story) }
                                }
                                Button("编辑足迹", systemImage: "pencil") { storyToEdit = story }
                                Button("分享足迹", systemImage: "square.and.arrow.up") { storyToShare = story }
                                Divider()
                                Button("删除足迹", systemImage: "trash", role: .destructive) { storyToDelete = story }
                            }
                    }
                }
            }
            .padding()
        }
        .background(Color.tripCanvas)
        .navigationTitle("旅行足迹")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新建足迹", systemImage: "plus") { creatingStory = true }
            }
        }
        .navigationDestination(for: TravelStory.self) { StoryDetailView(story: $0) }
        .sheet(isPresented: $creatingStory) { NewFootprintView() }
        .sheet(item: $storyToEdit) { StoryEditorView(story: $0) }
        .sheet(item: $storyToShare) { ShareExportView(story: $0) }
        .alert("足迹同步", isPresented: Binding(
            get: { syncMessage != nil },
            set: { if !$0 { syncMessage = nil } }
        )) {
            Button("好", role: .cancel) { syncMessage = nil }
        } message: {
            Text(syncMessage ?? "")
        }
        .alert(
            HierarchyDeletionCopy.storyTitle,
            isPresented: Binding(
                get: { storyToDelete != nil },
                set: { if !$0 { storyToDelete = nil } }
            ),
            presenting: storyToDelete
        ) { story in
            Button(HierarchyDeletionCopy.confirmationButtonTitle, role: .destructive) { delete(story) }
            Button(HierarchyDeletionCopy.cancelButtonTitle, role: .cancel) { storyToDelete = nil }
        } message: { story in
            Text(HierarchyDeletionCopy.storyMessage(title: story.title))
        }
        .task { stories.forEach { StorySyncService.ensureHierarchy(for: $0) } }
    }

    private func delete(_ story: TravelStory) {
        if storyToEdit?.id == story.id { storyToEdit = nil }
        modelContext.delete(story)
        storyToDelete = nil
    }

    private func sourceTrip(for story: TravelStory) -> Trip? {
        guard let sourceTripID = story.sourceTripID else { return nil }
        return trips.first { $0.id == sourceTripID }
    }

    private func sync(_ story: TravelStory) {
        guard let trip = sourceTrip(for: story) else { return }
        syncMessage = StorySyncService.sync(story: story, from: trip, modelContext: modelContext).message
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("走过的路，会留下来").font(.title2.bold())
                Text("\(stories.count) 段足迹").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "map.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color.tripLake, Color.tripMist)
        }
        .cardSurface()
    }
}

private struct NewFootprintView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title = ""
    @State private var destination = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    @State private var summary = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("这段足迹") {
                    TextField("例如：初秋杭州三日", text: $title)
                    TextField("目的地（选填）", text: $destination)
                    TwoTapDateRangePicker(
                        title: "足迹日期",
                        startTitle: "开始",
                        endTitle: "结束",
                        startDate: $startDate,
                        endDate: $endDate
                    )
                }
                Section("足迹摘要") {
                    TextField("选填，之后也可以补充", text: $summary, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("新建足迹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { create() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func create() {
        _ = FootprintCreationService.create(
            title: title,
            destination: destination,
            startDate: startDate,
            endDate: endDate,
            summary: summary,
            modelContext: modelContext
        )
        dismiss()
    }
}

private struct StoryCard: View {
    let story: TravelStory
    let canSync: Bool
    let onSync: () -> Void
    let onEdit: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    @State private var mediaPreview: AssetMediaPreviewRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if story.allMedia.isEmpty {
                NavigationLink(value: story) {
                    ContentUnavailableView("还没有图片", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity, minHeight: 116)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("进入足迹详情")
            } else {
                StoryMediaCarousel(
                    media: story.allMedia,
                    height: 196,
                    onSelect: showMedia
                )
            }

            HStack(alignment: .top) {
                NavigationLink(value: story) {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(story.title).font(.title3.bold()).foregroundStyle(.primary)
                            if !story.destination.isEmpty {
                                Label(story.destination, systemImage: "mappin.and.ellipse")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if !story.summary.isEmpty {
                            Text(story.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        HStack(spacing: 8) {
                            Text("\(story.startDate.compactDayText) — \(story.endDate.compactDayText)")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text("\(story.sortedDays.count) 天 · \(story.sortedEntries.count) 个安排")
                                .fontWeight(.bold)
                                .foregroundStyle(Color.tripLake)
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("进入足迹详情")

                Menu {
                    if canSync {
                        Button("同步足迹", systemImage: "arrow.triangle.2.circlepath", action: onSync)
                    }
                    Button("编辑足迹", systemImage: "pencil", action: onEdit)
                    Button("分享足迹", systemImage: "square.and.arrow.up", action: onShare)
                    Divider()
                    Button("删除足迹", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .background(Color.secondary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.tripInk.opacity(0.72))
                .accessibilityLabel("\(story.title)更多操作")
            }
        }
        .cardSurface()
        .fullScreenCover(item: $mediaPreview) { AssetMediaViewer(request: $0) }
    }

    private func showMedia(_ media: MediaReference) {
        mediaPreview = AssetMediaPreviewRequest(
            items: story.allMedia.map {
                AssetMediaPreviewItem(identifier: $0.localIdentifier, kind: $0.kind)
            },
            initialIdentifier: media.localIdentifier
        )
    }
}

struct ArchiveTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var stories: [TravelStory]
    let trip: Trip
    @State private var summary: String
    @State private var selectedDayIDs: Set<UUID>
    @State private var selectedItemIDs: Set<UUID>
    @State private var loadedExistingSelection = false
    @State private var archiveError: String?

    init(trip: Trip) {
        self.trip = trip
        _summary = State(initialValue: "")
        _selectedDayIDs = State(initialValue: Set(trip.days.map(\.id)))
        _selectedItemIDs = State(initialValue: Set(trip.allItems.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("保存位置", value: existingStory == nil ? "新建“\(trip.title)”足迹" : "合并到“\(trip.title)”足迹")
                    LabeledContent("已选择", value: "\(selectedDaysCount) 天 · \(selectedItemIDs.count) 个安排")
                }
                Section("选择内容") {
                    selectionRow(
                        title: trip.title,
                        subtitle: "全部 \(trip.sortedDays.count) 天 · \(trip.allItems.count) 个安排",
                        state: rootSelectionState,
                        level: 0,
                        action: toggleAll
                    )
                    ForEach(trip.sortedDays) { day in
                        selectionRow(
                            title: day.title.isEmpty ? day.date.chineseDateText : day.title,
                            subtitle: "\(day.date.compactDayText) · \(day.items.count) 个安排",
                            state: selectionState(for: day),
                            level: 1,
                            action: { toggle(day) }
                        )
                        ForEach(day.sortedItems) { item in
                            selectionRow(
                                title: item.title,
                                subtitle: item.category.rawValue,
                                state: selectedItemIDs.contains(item.id) ? .selected : .none,
                                level: 2,
                                action: { toggle(item, in: day) }
                            )
                        }
                    }
                }
                Section("足迹摘要") {
                    TextField("旅行摘要（选填）", text: $summary, axis: .vertical).lineLimit(4...10)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("收进足迹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingStory == nil ? "创建足迹" : "同步到足迹") { archive() }
                        .disabled(!hasSelection)
                }
            }
            .task { loadExistingSelectionIfNeeded() }
            .alert("无法加入足迹", isPresented: Binding(
                get: { archiveError != nil },
                set: { if !$0 { archiveError = nil } }
            )) {
                Button("好", role: .cancel) { archiveError = nil }
            } message: {
                Text(archiveError ?? "")
            }
        }
    }

    private var existingStory: TravelStory? {
        stories.first { $0.sourceTripID == trip.id }
    }

    private var selectedDaysCount: Int {
        trip.days.filter { selectionState(for: $0) != .none }.count
    }

    private var hasSelection: Bool {
        !selectedDayIDs.isEmpty || !selectedItemIDs.isEmpty
    }

    private var rootSelectionState: HierarchySelectionState {
        guard !trip.days.isEmpty else { return .none }
        let states = trip.days.map(selectionState(for:))
        if states.allSatisfy({ $0 == .selected }) { return .selected }
        return states.contains(where: { $0 != .none }) ? .partial : .none
    }

    @ViewBuilder
    private func selectionRow(
        title: String,
        subtitle: String,
        state: HierarchySelectionState,
        level: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: state.symbol)
                    .font(.title3)
                    .foregroundStyle(state == .none ? Color.secondary : Color.tripLake)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.leading, CGFloat(level * 22))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(state.accessibilityText)")
    }

    private func selectionState(for day: TripDay) -> HierarchySelectionState {
        if selectedDayIDs.contains(day.id) { return .selected }
        let itemIDs = Set(day.items.map(\.id))
        guard !itemIDs.isEmpty else { return .none }
        let selectedCount = itemIDs.intersection(selectedItemIDs).count
        if selectedCount == itemIDs.count { return .selected }
        return selectedCount > 0 ? .partial : .none
    }

    private func toggleAll() {
        if rootSelectionState == .selected {
            selectedDayIDs.removeAll()
            selectedItemIDs.removeAll()
        } else {
            selectedDayIDs = Set(trip.days.map(\.id))
            selectedItemIDs = Set(trip.allItems.map(\.id))
        }
    }

    private func toggle(_ day: TripDay) {
        let itemIDs = Set(day.items.map(\.id))
        if selectionState(for: day) == .selected {
            selectedDayIDs.remove(day.id)
            selectedItemIDs.subtract(itemIDs)
        } else {
            selectedDayIDs.insert(day.id)
            selectedItemIDs.formUnion(itemIDs)
        }
    }

    private func toggle(_ item: ItineraryItem, in day: TripDay) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
            selectedDayIDs.remove(day.id)
        } else {
            selectedItemIDs.insert(item.id)
            let allItemIDs = Set(day.items.map(\.id))
            if allItemIDs.isSubset(of: selectedItemIDs) {
                selectedDayIDs.insert(day.id)
            }
        }
    }

    private func loadExistingSelectionIfNeeded() {
        guard !loadedExistingSelection else { return }
        loadedExistingSelection = true
        guard let existingStory, existingStory.syncScope != .trip else { return }

        let sourceIDs = existingStory.sourceSelectionIDs
        selectedDayIDs.removeAll()
        selectedItemIDs.removeAll()
        for day in trip.sortedDays {
            if sourceIDs.contains(day.id) {
                selectedDayIDs.insert(day.id)
                selectedItemIDs.formUnion(day.items.map(\.id))
            } else {
                selectedItemIDs.formUnion(day.items.filter { sourceIDs.contains($0.id) }.map(\.id))
            }
        }
    }

    private func archive() {
        let selectedItems = trip.allItems.filter { selectedItemIDs.contains($0.id) }
        let isEntireTrip = rootSelectionState == .selected
        let sourceIDs = isEntireTrip ? [] : selectedDayIDs.union(selectedItemIDs)
        let scope: StorySyncScope = isEntireTrip ? .trip : (selectedDayIDs.isEmpty ? .item : .day)
        do {
            _ = try StoryArchiveService.archive(
                trip: trip,
                selectedItems: selectedItems,
                syncScope: scope,
                sourceIDs: sourceIDs,
                summary: summary,
                replacesSyncSelection: true,
                modelContext: modelContext
            )
            dismiss()
        } catch {
            archiveError = error.localizedDescription
        }
    }

}

private enum HierarchySelectionState: Equatable {
    case none
    case partial
    case selected

    var symbol: String {
        switch self {
        case .none: "square"
        case .partial: "minus.square.fill"
        case .selected: "checkmark.square.fill"
        }
    }

    var accessibilityText: String {
        switch self {
        case .none: "未选择"
        case .partial: "部分选择"
        case .selected: "已选择"
        }
    }
}
