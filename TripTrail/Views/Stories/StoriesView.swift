import SwiftData
import SwiftUI

struct FootprintYearSection: Identifiable {
    let year: Int
    let stories: [TravelStory]

    var id: Int { year }
}

enum FootprintBrowseService {
    static func filtered(
        _ stories: [TravelStory],
        searchText: String,
        year: Int?,
        calendar: Calendar = .current
    ) -> [TravelStory] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return stories
            .filter { story in
                if let year, calendar.component(.year, from: story.startDate) != year {
                    return false
                }
                return query.isEmpty || searchableText(for: story).localizedCaseInsensitiveContains(query)
            }
            .sorted {
                if $0.startDate != $1.startDate { return $0.startDate > $1.startDate }
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    static func groupedByYear(
        _ stories: [TravelStory],
        calendar: Calendar = .current
    ) -> [FootprintYearSection] {
        Dictionary(grouping: stories) { calendar.component(.year, from: $0.startDate) }
            .map { FootprintYearSection(year: $0.key, stories: $0.value) }
            .sorted { $0.year > $1.year }
    }

    private static func searchableText(for story: TravelStory) -> String {
        var parts = [story.title, story.destination, story.summary]
        for day in story.sortedDays {
            parts.append(contentsOf: [day.title, day.note, day.details])
        }
        for entry in story.sortedEntries {
            parts.append(contentsOf: [
                entry.title,
                entry.note,
                entry.supplementalInfo,
                entry.address,
                entry.placeName,
                entry.placeAddress,
                entry.originName,
                entry.originAddress,
                entry.destinationName,
                entry.destinationAddress
            ])
        }
        return parts.joined(separator: " ")
    }
}

struct StoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TravelStory.startDate, order: .reverse) private var stories: [TravelStory]
    @Query(sort: \Trip.startDate, order: .forward) private var trips: [Trip]
    @State private var storyToEdit: TravelStory?
    @State private var storyToShare: TravelStory?
    @State private var storyToDelete: TravelStory?
    @State private var creatingStory = false
    @State private var searchText = ""
    @State private var selectedYear: Int?
    @State private var collapsedYears: Set<Int> = []
    @State private var didInitializeCollapsedYears = false

    private var filteredStories: [TravelStory] {
        FootprintBrowseService.filtered(
            stories,
            searchText: searchText,
            year: selectedYear
        )
    }

    private var yearSections: [FootprintYearSection] {
        FootprintBrowseService.groupedByYear(filteredStories)
    }

    private var availableYears: [Int] {
        Array(Set(stories.map { Calendar.current.component(.year, from: $0.startDate) })).sorted(by: >)
    }

    private var hasActiveConditions: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedYear != nil
    }

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
                    if hasActiveConditions {
                        HStack {
                            Text("找到 \(filteredStories.count) / \(stories.count) 段足迹")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("清除条件", action: clearConditions)
                                .font(.subheadline.bold())
                        }
                    }
                    if filteredStories.isEmpty {
                        ContentUnavailableView {
                            Label("没有找到足迹", systemImage: "magnifyingglass")
                        } description: {
                            Text("试试其他关键词，或清除筛选条件。")
                        } actions: {
                            Button("清除条件", action: clearConditions)
                                .buttonStyle(.bordered)
                        }
                        .frame(minHeight: 280)
                    } else {
                        ForEach(yearSections) { section in
                            yearGroup(section)
                        }
                    }
                }
            }
            .padding()
            .padding(.bottom, 96)
        }
        .background(Color.tripCanvas)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索名称、城市、地点或摘要"
        )
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                filterMenu
                Button("新建足迹", systemImage: "plus") { creatingStory = true }
            }
        }
        .navigationDestination(for: TravelStory.self) { StoryDetailView(story: $0) }
        .sheet(isPresented: $creatingStory) { NewFootprintView() }
        .sheet(item: $storyToEdit) { StoryEditorView(story: $0) }
        .sheet(item: $storyToShare) { ShareExportView(story: $0) }
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
        .task {
            for story in stories {
                StorySyncService.ensureHierarchy(for: story)
                _ = StorySyncService.migrateLegacyLocations(
                    for: story,
                    from: sourceTrip(for: story)
                )
            }
            initializeCollapsedYearsIfNeeded()
        }
        .onChange(of: hasActiveConditions) { _, isActive in
            if isActive {
                collapsedYears.removeAll()
            }
        }
    }

    private func storyCard(_ story: TravelStory) -> some View {
        StoryCard(
            story: story,
            onEdit: { storyToEdit = story },
            onShare: { storyToShare = story },
            onDelete: { storyToDelete = story }
        )
        .contextMenu {
            Button("编辑足迹", systemImage: "pencil") { storyToEdit = story }
            Button("分享足迹", systemImage: "square.and.arrow.up") { storyToShare = story }
            Divider()
            Button("删除足迹", systemImage: "trash", role: .destructive) { storyToDelete = story }
        }
    }

    private func yearGroup(_ section: FootprintYearSection) -> some View {
        LazyVStack(spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    if collapsedYears.contains(section.year) {
                        collapsedYears.remove(section.year)
                    } else {
                        collapsedYears.insert(section.year)
                    }
                }
            } label: {
                HStack {
                    Text("\(section.year) 年")
                        .font(.headline)
                        .foregroundStyle(Color.tripInk)
                    Text("\(section.stories.count) 段")
                        .font(.caption.bold())
                        .foregroundStyle(Color.tripLake)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.tripLake.opacity(0.1), in: Capsule())
                    Spacer()
                    Image(systemName: collapsedYears.contains(section.year) ? "chevron.down" : "chevron.up")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(section.year) 年，\(section.stories.count) 段足迹")
            .accessibilityValue(collapsedYears.contains(section.year) ? "已收起" : "已展开")

            if !collapsedYears.contains(section.year) {
                ForEach(section.stories) { story in
                    storyCard(story)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("年份", selection: $selectedYear) {
                Text("全部年份").tag(nil as Int?)
                ForEach(availableYears, id: \.self) { year in
                    Text("\(year) 年").tag(Optional(year))
                }
            }
        } label: {
            Image(systemName: selectedYear == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel(selectedYear == nil ? "按年份筛选足迹" : "按年份筛选足迹，已有条件")
    }

    private func initializeCollapsedYearsIfNeeded() {
        guard !didInitializeCollapsedYears else { return }
        collapsedYears = Set(availableYears.dropFirst())
        didInitializeCollapsedYears = true
    }

    private func clearConditions() {
        searchText = ""
        selectedYear = nil
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
        TripNavigationStack {
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
    let onEdit: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    @State private var mediaPreview: AssetMediaPreviewRequest?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            thumbnail

            NavigationLink(value: story) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(story.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if !story.destination.isEmpty {
                        Label(story.destination, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if !story.summary.isEmpty {
                        Text(story.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Text("\(story.startDate.compactDayText) — \(story.endDate.compactDayText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(story.sortedDays.count) 天 · \(story.sortedEntries.count) 个记录")
                        .font(.caption.bold())
                        .foregroundStyle(Color.tripLake)
                }
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("进入足迹详情")

            Menu {
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
        .cardSurface()
        .fullScreenCover(item: $mediaPreview) { AssetMediaViewer(request: $0) }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if story.coverMedia != nil {
            NavigationLink(value: story) {
                StoryCoverArtwork(
                    story: story,
                    targetSize: CGSize(width: 360, height: 360)
                )
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看\(story.title)")
            .accessibilityHint("进入足迹详情")
        } else if let media = story.allMedia.first {
            Button {
                showMedia(media)
            } label: {
                AssetThumbnail(
                    identifier: media.localIdentifier,
                    showsVideoBadge: media.kind == .video
                )
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if story.allMedia.count > 1 {
                        Label("\(story.allMedia.count)", systemImage: "photo.on.rectangle.angled")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.58), in: Capsule())
                            .padding(7)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(media.kind == .video ? "查看足迹视频" : "查看足迹照片")
            .accessibilityValue("共 \(story.allMedia.count) 个媒体")
        } else {
            NavigationLink(value: story) {
                VStack(spacing: 7) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                    Text("暂无图片")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(width: 112, height: 112)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("进入足迹详情")
        }
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
        TripNavigationStack {
            Form {
                Section {
                    LabeledContent("保存位置", value: existingStory == nil ? "新建“\(trip.title)”足迹" : "更新“\(trip.title)”足迹")
                    LabeledContent("已选择", value: "\(selectedDaysCount) 天 · \(selectedItemIDs.count) 个记录")
                }
                Section("选择内容") {
                    selectionRow(
                        title: trip.title,
                        subtitle: "全部 \(trip.sortedDays.count) 天 · \(trip.allItems.count) 个记录",
                        state: rootSelectionState,
                        level: 0,
                        action: toggleAll
                    )
                    ForEach(trip.sortedDays) { day in
                        selectionRow(
                            title: day.title.isEmpty ? day.date.chineseDateText : day.title,
                            subtitle: "\(day.date.compactDayText) · \(day.items.count) 个记录",
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
            .navigationTitle("整理成足迹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingStory == nil ? "创建足迹" : "更新足迹框架") { archive() }
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
