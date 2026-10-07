import PhotosUI
import SwiftData
import SwiftUI
import UIKit

enum ItemEditorMode {
    case itinerary
    case favorite
}

struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let day: TripDay?
    let item: ItineraryItem?
    let mode: ItemEditorMode
    let isFootprint: Bool
    var onSaved: (() -> Void)? = nil

    @State private var favoriteCity: String
    @State private var title: String
    @State private var locationMode: ArrangementLocationMode
    @State private var placeName: String
    @State private var placeAddress: String
    @State private var originName: String
    @State private var originAddress: String
    @State private var destinationName: String
    @State private var destinationAddress: String
    @State private var attractionType: AttractionType
    @State private var transport: TransportMode
    @State private var category: PlaceCategory
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var isTimePending: Bool
    @State private var targetDayID: UUID?
    @State private var isFixedTime: Bool
    @State private var journalNote: String
    @State private var note: String
    @State private var costText: String
    @State private var showsFavoriteImport = false
    @State private var showsSmartImport = false
    @State private var creationMethod = "普通新建"
    @State private var smartImportMode: SingleSmartImportMode
    @State private var smartImportFeedback: String?
    @State private var smartImportUsedFallback = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickedAssets: [PickedAsset] = []
    @State private var mediaOrder: [String] = []
    @State private var removedMediaIDs: Set<UUID> = []
    @State private var mediaWarning: String?
    @State private var mediaPreview: AssetMediaPreviewRequest?

    init(
        day: TripDay?,
        item: ItineraryItem? = nil,
        mode: ItemEditorMode = .itinerary,
        isFootprint: Bool = false,
        startsWithSmartImport: Bool = false,
        initialSmartImportMode: SingleSmartImportMode = .text,
        onSaved: (() -> Void)? = nil
    ) {
        self.day = day
        self.item = item
        self.mode = mode
        self.isFootprint = isFootprint
        self.onSaved = onSaved
        let base = day?.date ?? item?.day?.date ?? Date()
        let calendar = Calendar.current
        let defaultStart = day?.suggestedStartTime(calendar: calendar)
            ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base)
            ?? base
        let initialStartTime = DateRangeDateService.applyingDay(
            base,
            to: item?.startTime ?? defaultStart,
            preservingTime: true,
            calendar: calendar
        )
        let initialEndTime = DateRangeDateService.applyingDay(
            base,
            to: item?.endTime ?? calendar.date(byAdding: .hour, value: 1, to: defaultStart)!,
            preservingTime: true,
            calendar: calendar
        )
        _title = State(initialValue: item?.title ?? "")
        _favoriteCity = State(initialValue: item?.favoriteCity ?? "")
        let isLegacyItem = item?.locationModeRaw.isEmpty != false
        _locationMode = State(initialValue: item?.locationMode ?? .single)
        _placeName = State(initialValue: item.map {
            $0.placeName
        } ?? "")
        _placeAddress = State(initialValue: item.map {
            $0.placeAddress.isEmpty && isLegacyItem ? $0.address : $0.placeAddress
        } ?? "")
        _originName = State(initialValue: item?.originName ?? "")
        _originAddress = State(initialValue: item?.originAddress ?? "")
        _destinationName = State(initialValue: item?.destinationName ?? "")
        _destinationAddress = State(initialValue: item?.destinationAddress ?? "")
        _attractionType = State(initialValue: AttractionType(rawValue: item?.attractionTypeRaw ?? "") ?? .automatic)
        _transport = State(initialValue: item?.transport ?? .car)
        _category = State(initialValue: item?.category ?? .attraction)
        _startTime = State(initialValue: initialStartTime)
        _endTime = State(initialValue: initialEndTime)
        _isFixedTime = State(initialValue: item?.isFixedTime ?? false)
        _isTimePending = State(initialValue: item?.isTimePending ?? false)
        _targetDayID = State(initialValue: day?.id ?? item?.day?.id)
        _journalNote = State(initialValue: item?.journalNote ?? "")
        _note = State(initialValue: item?.note ?? "")
        _costText = State(initialValue: item.map { $0.cost == 0 ? "" : String($0.cost) } ?? "")
        _showsSmartImport = State(initialValue: startsWithSmartImport && item == nil)
        _smartImportMode = State(initialValue: initialSmartImportMode)
    }

    private var locationModeSelection: Binding<ArrangementLocationMode> {
        Binding(get: { locationMode }, set: { selected in
            guard selected != locationMode else { return }
            locationMode = selected
            placeName = ""; placeAddress = ""
            originName = ""; originAddress = ""
            destinationName = ""; destinationAddress = ""
        })
    }

    var body: some View {
        TripNavigationStack {
            Form {
                if item == nil {
                    Section {
                        if mode == .favorite {
                            Picker("新建方式", selection: $creationMethod) {
                                Text("智能录入").tag("智能录入")
                                Text("普通新建").tag("普通新建")
                            }.pickerStyle(.segmented)
                        } else {
                            Button { showsSmartImport = true } label: { Label("智能录入", systemImage: "wand.and.stars") }
                        }
                        if mode == .itinerary, day != nil {
                            Button { showsFavoriteImport = true } label: { Label("从收藏导入", systemImage: "heart") }
                        }
                        if let smartImportFeedback {
                            Label(
                                smartImportFeedback,
                                systemImage: smartImportUsedFallback
                                    ? "exclamationmark.triangle.fill"
                                    : "checkmark.circle"
                            )
                                .font(.caption)
                                .foregroundStyle(smartImportUsedFallback ? Color.orange : Color.secondary)
                        }
                    }
                }

                if item == nil && mode == .favorite && creationMethod == "智能录入" {
                    Section {
                        Button { showsSmartImport = true } label: { Label("开始智能录入", systemImage: "wand.and.stars") }
                        Text("通过文字或截图识别收藏，识别后可继续编辑。").font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                Section(isFootprint ? "安排标题" : "安排名称") {
                    TextField("安排标题", text: $title).clearableText($title)
                        .accessibilityLabel("安排标题")
                }
                if mode == .itinerary && !isFootprint {
                    Section("补充说明") {
                        TextField("填写安排的补充说明", text: $note, axis: .vertical).clearableText($note).lineLimit(2...5)
                    }
                }
                if isFootprint {
                    memorySection
                    mediaSection
                }
                if isFootprint {
                    Section("时间") {
                        UnifiedTimeRangePicker(title: "时间", startTitle: "开始", endTitle: "结束",
                            startTime: $startTime, endTime: $endTime, isEmpty: isTimePending,
                            onCommit: { isTimePending = false }, onClear: { isTimePending = true })
                    }
                } else {
                Section {
                    Picker("类型", selection: $category) {
                        ForEach(PlaceCategory.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                    if mode == .favorite && category == .attraction {
                        Picker("景点类型", selection: $attractionType) {
                            ForEach(AttractionType.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    if category == .transport {
                        Picker("交通方式", selection: $transport) {
                            ForEach(TransportMode.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                    if mode == .itinerary {
                        if let trip = (day ?? item?.day)?.trip, trip.sortedDays.count > 1 {
                            Picker("安排日期", selection: $targetDayID) {
                                ForEach(trip.sortedDays) { value in
                                    Text(value.date.formatted(date: .abbreviated, time: .omitted)).tag(Optional(value.id))
                                }
                            }
                        }
                        Toggle("时间待定", isOn: $isTimePending)
                            .onChange(of: isTimePending) { _, pending in if pending { isFixedTime = false } }
                        if !isTimePending {
                            UnifiedTimeRangePicker(
                                title: "时间",
                                startTitle: "开始",
                                endTitle: "结束",
                                startTime: $startTime,
                                endTime: $endTime
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("固定时间", isOn: $isFixedTime)
                                Text("开启后，排序或拖拽时不会自动调整此安排的时间")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                }

                if mode == .favorite {
                    Section("补充说明") { TextField("补充说明", text: $note, axis: .vertical).clearableText($note) }
                    mediaSection
                }

                Section("地点") {
                    if mode == .favorite {
                        VStack(alignment: .leading, spacing: 6) {
                            editorFieldLabel("城市（选填）")
                            TextField("例如：杭州，用于筛选收藏", text: $favoriteCity).clearableText($favoriteCity)
                        }
                    }
                    Picker("地点类型", selection: locationModeSelection) {
                        ForEach(ArrangementLocationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if locationMode == .single {
                        VStack(alignment: .leading, spacing: 6) {
                            editorFieldLabel("地点名称")
                            TextField("例如：上海世纪公园", text: $placeName).clearableText($placeName)
                                .accessibilityLabel("地点名称")
                        }

                    } else {
                        locationFields(
                            title: "出发地",
                            name: $originName,
                            address: $originAddress
                        )
                        locationFields(
                            title: "目的地",
                            name: $destinationName,
                            address: $destinationAddress
                        )
                    }
                }

                Section("花费") {
                    HStack(spacing: 8) {
                        Text("¥")
                            .foregroundStyle(.secondary)
                        TextField("输入金额", text: $costText).clearableText($costText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("花费")
                    }
                }

                if mode != .favorite {
                    if !isFootprint {
                        memorySection
                        mediaSection
                    }
                    if isFootprint {
                        Section("补充说明") {
                            TextField("填写安排的补充说明", text: $note, axis: .vertical).clearableText($note).lineLimit(2...5)
                        }
                    }
                }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isFootprint ? "编辑记录" : navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(
                        (item == nil && mode == .favorite && creationMethod != "普通新建")
                            || title.trimmingCharacters(in: .whitespaces).isEmpty
                            || (mode == .itinerary && !isTimePending && endTime <= startTime)
                    )
                }
            }
            .onChange(of: pickerItems) { _, newValue in
                consumePickerItems(newValue)
            }
            .onChange(of: category) { _, newValue in
                guard item == nil else { return }
                locationMode = newValue == .transport ? .route : .single
            }
            .cloudEditSheet(isPresented: $showsFavoriteImport) {
                if let day { FavoriteImportSelectionView(day: day) }
            }
            .cloudEditSheet(isPresented: $showsSmartImport) {
                if mode == .itinerary, let day, let trip = day.trip {
                    TextItineraryImportView(trip: trip, referenceDate: day.date, targetDay: day, onCreated: { _ in dismiss() })
                } else {
                SingleItinerarySmartImportView(
                    initialMode: smartImportMode,
                    referenceDate: startTime,
                    purpose: mode == .favorite ? .favorite : .itinerary,
                    onCancel: { showsSmartImport = false },
                    onRecognized: { draft in
                        applyRecognizedDraft(draft)
                        creationMethod = "普通新建"
                        showsSmartImport = false
                    }
                )
                }
            }
            .alert("相簿提示", isPresented: Binding(get: { mediaWarning != nil }, set: { if !$0 { mediaWarning = nil } })) {
                Button("知道了", role: .cancel) { mediaWarning = nil }
            } message: { Text(mediaWarning ?? "") }
            .fullScreenCover(item: $mediaPreview) { AssetMediaViewer(request: $0) }
        }
    }

    private var navigationTitle: String {
        switch (mode, item == nil) {
        case (.favorite, true): "新建收藏"
        case (.favorite, false): "编辑收藏"
        case (.itinerary, true): "添加安排"
        case (.itinerary, false): "编辑安排"
        }
    }

    private func editorFieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var memorySection: some View {
        Section("回忆") {
            TextField("记录这段旅程的回忆", text: $journalNote, axis: .vertical)
                .clearableText($journalNote).lineLimit(3...8)
        }
    }

    private var mediaSection: some View {
        Section("照片与视频") {
            let visibleMedia = (item?.media ?? [])
                .filter { !removedMediaIDs.contains($0.id) }
                .sorted(by: MediaReference.precedes)
            mediaGrid(existing: visibleMedia, picked: pickedAssets)
                .listRowSeparator(.hidden)
        }
    }

    private func locationFields(
        title: String,
        name: Binding<String>,
        address: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            editorFieldLabel(title)
            TextField("\(title)名称", text: name).clearableText(name)
                .accessibilityLabel("\(title)名称")
        }
    }

    private var previewMediaItems: [AssetMediaPreviewItem] {
        ReorderableMediaGrid<EmptyView, EmptyView>.ordered(
            (item?.media ?? []).filter { !removedMediaIDs.contains($0.id) }.sorted(by: MediaReference.precedes)
                .map { AssetMediaPreviewItem(identifier: $0.localIdentifier, kind: $0.kind) }
            + pickedAssets.map { AssetMediaPreviewItem(identifier: $0.id, kind: $0.kind) }, order: mediaOrder)
    }

    private func applyRecognizedDraft(_ draft: ItineraryScreenshotDraft) {
        if !draft.title.isEmpty, draft.title != "待补充的安排" { title = draft.title }
        category = draft.category
        transport = draft.transport
        attractionType = AttractionType(rawValue: draft.attractionTypeRaw) ?? .automatic
        startTime = draft.startTime
        endTime = draft.endTime
        if mode == .favorite, !draft.favoriteCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { favoriteCity = draft.favoriteCity.trimmingCharacters(in: .whitespacesAndNewlines) }
        locationMode = draft.locationMode
        if !draft.placeName.isEmpty { placeName = draft.placeName }
        if !draft.placeAddress.isEmpty { placeAddress = draft.placeAddress }
        if !draft.originName.isEmpty { originName = draft.originName }
        if !draft.originAddress.isEmpty { originAddress = draft.originAddress }
        if !draft.destinationName.isEmpty { destinationName = draft.destinationName }
        if !draft.destinationAddress.isEmpty { destinationAddress = draft.destinationAddress }
        if locationMode == .single, placeName.isEmpty, !draft.address.isEmpty {
            placeAddress = draft.address
        }
        if draft.cost > 0 { costText = String(draft.cost) }
        for detail in [draft.note] where !detail.isEmpty && !note.contains(detail) {
            note = [note, detail].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        let existingIDs = Set(pickedAssets.map(\.id))
        pickedAssets.append(contentsOf: draft.sourceAssetIdentifiers
            .filter { !existingIDs.contains($0) }
            .map { PickedAsset(id: $0, kind: .image) })
        if let recognitionNotice = draft.recognitionNotice {
            smartImportUsedFallback = true
            smartImportFeedback = recognitionNotice
        } else {
            smartImportUsedFallback = false
            smartImportFeedback = "已预填，可继续修改。"
        }
    }

    @ViewBuilder
    private func mediaGrid(existing: [MediaReference], picked: [PickedAsset]) -> some View {
        ReorderableMediaGrid(assets: existing.map { AssetMediaPreviewItem(identifier: $0.localIdentifier, kind: $0.kind) }
            + picked.map { AssetMediaPreviewItem(identifier: $0.id, kind: $0.kind) }, order: $mediaOrder) { asset in
            removableThumbnail(identifier: asset.identifier, kind: asset.kind) {
                if let reference = existing.first(where: { $0.localIdentifier == asset.identifier }) { removedMediaIDs.insert(reference.id) }
                pickedAssets.removeAll { $0.id == asset.identifier }
            }
        } addTile: {
            let remaining = max(0, 20 - existing.count - picked.count)
            if remaining > 0 {
                PermissionAwarePhotosPicker(selection: $pickerItems, maxSelectionCount: remaining, matching: .any(of: [.images, .videos])) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.tripLake.opacity(0.045))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.tripLake.opacity(0.52), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        }
                        .overlay { Image(systemName: "plus").font(.title2.weight(.medium)).foregroundStyle(Color.tripLake) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加照片或视频")
            }
        }
    }

    private func removableThumbnail(
        identifier: String,
        kind: MediaKind,
        onRemove: @escaping () -> Void
    ) -> some View {
        let thumbnail = Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AssetThumbnail(identifier: identifier, showsVideoBadge: kind == .video)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        return ZStack(alignment: .topTrailing) {
            Button {
                mediaPreview = AssetMediaPreviewRequest(
                    items: previewMediaItems,
                    initialIdentifier: identifier
                )
            } label: {
                thumbnail
            }
            .buttonStyle(.plain)
            .accessibilityLabel(kind == .video ? "预览视频" : "预览图片")

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .font(.title3)
                    .frame(width: 44, height: 44, alignment: .topTrailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .zIndex(1)
            .accessibilityLabel("移除这项素材")
        }
    }

    private func consumePickerItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let converted = PhotoLibraryService.pickedAssets(from: items)
        if converted.count != items.count {
            mediaWarning = "有 \(items.count - converted.count) 项无法读取相簿标识，请从系统“照片”中重选。当前权限：\(PhotoLibraryService.readableStatusText)。"
        }

        let activeExistingIDs = Set((item?.media ?? [])
            .filter { !removedMediaIDs.contains($0.id) }
            .map(\.localIdentifier))
        let alreadyPickedIDs = Set(pickedAssets.map(\.id))
        pickedAssets.append(contentsOf: converted.filter {
            !activeExistingIDs.contains($0.id) && !alreadyPickedIDs.contains($0.id)
        })
        pickerItems = []
    }

    private func save() {
        let target: ItineraryItem
        if let item {
            target = item
        } else if mode == .favorite {
            target = ItineraryItem(
                title: title,
                category: category,
                startTime: startTime,
                endTime: endTime,
                sortOrder: 0
            )
            target.isFavorite = true
            target.favoriteCreatedAt = Date()
            modelContext.insert(target)
        } else {
            guard let day else { return }
            target = ItineraryItem(title: title, category: category, startTime: startTime, endTime: endTime, sortOrder: day.items.count)
            target.day = day
            day.items.append(target)
        }

        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.locationMode = locationMode
        target.placeName = JourneyLocationText.entityName(
            from: placeName,
            arrangementTitle: target.title
        )
        target.placeAddress = placeAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        target.originName = JourneyLocationText.entityName(
            from: originName,
            arrangementTitle: target.title,
            role: .origin
        )
        target.originAddress = originAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        target.destinationName = JourneyLocationText.entityName(
            from: destinationName,
            arrangementTitle: target.title,
            role: .destination
        )
        target.destinationAddress = destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        target.retainSelectedLocation()
        target.address = locationMode == .single ? target.placeAddress : target.destinationAddress
        target.category = category
        target.transport = transport
        if mode == .favorite || item == nil { target.attractionTypeRaw = attractionType.rawValue }
        if isTimePending && !target.isTimePending { target.executionStatus = .notStarted }
        target.isTimePending = isTimePending
        if mode == .itinerary {
            if let source = target.day,
               let destination = source.trip?.days.first(where: { $0.id == targetDayID }), destination.id != source.id {
                source.items.removeAll { $0.id == target.id }
                target.day = destination
                target.sortOrder = destination.items.count
                destination.items.append(target)
                JourneyHierarchyService.normalizeItems(source.items)
            }
            let scheduleDay = target.day?.date ?? day?.date ?? startTime
            target.startTime = DateRangeDateService.applyingDay(
                scheduleDay,
                to: startTime,
                preservingTime: true
            )
            target.endTime = DateRangeDateService.applyingDay(
                scheduleDay,
                to: endTime,
                preservingTime: true
            )
            target.completeIfElapsed()
            target.isFixedTime = isFixedTime && !isTimePending
            if target.endTime <= target.startTime {
                target.endTime = target.startTime.addingTimeInterval(60)
            }
        }
        target.journalNote = journalNote.trimmingCharacters(in: .whitespacesAndNewlines)
        target.note = note
        target.playDurationMinutes = max(0, Int(target.endTime.timeIntervalSince(target.startTime) / 60))
        if let targetDay = target.day { JourneyHierarchyService.normalizeItems(targetDay.items) }
        target.cost = Double(costText.replacingOccurrences(of: ",", with: ".")) ?? 0
        target.isFavorite = mode == .favorite
        if mode == .favorite { target.favoriteCity = favoriteCity.trimmingCharacters(in: .whitespacesAndNewlines) }

        UnifiedJourneyService.removeMedia(ids: removedMediaIDs, from: target, context: modelContext)
        let activeMedia = target.media.filter { !removedMediaIDs.contains($0.id) }
        let existingIDs = Set(activeMedia.map(\.localIdentifier))
        let nextSortOrder = (activeMedia.map(\.sortOrder).max() ?? -1) + 1
        for (index, picked) in pickedAssets.filter({ !existingIDs.contains($0.id) }).enumerated() {
            let reference = MediaReference(localIdentifier: picked.id, kind: picked.kind, sortOrder: nextSortOrder + index)
            reference.itineraryItem = target
            target.media.append(reference)
        }
        let orderedMedia = target.media.filter { !removedMediaIDs.contains($0.id) }.sorted {
            let left = mediaOrder.firstIndex(of: $0.localIdentifier) ?? (mediaOrder.count + $0.sortOrder)
            let right = mediaOrder.firstIndex(of: $1.localIdentifier) ?? (mediaOrder.count + $1.sortOrder)
            return left == right ? MediaReference.precedes($0, $1) : left < right
        }
        for (index, reference) in orderedMedia.enumerated() { reference.sortOrder = index }
        do { try modelContext.save() } catch {
            mediaWarning = "保存失败：\(error.localizedDescription)"
            return
        }
        onSaved?()
        let key = mode == .favorite ? "favorite:\(target.id.uuidString.lowercased())" : (target.day?.trip).map { "trip:\($0.id.uuidString.lowercased())" }
        if let key { Task { await CloudSyncService.shared.uploadPending(context: modelContext, key: key, entityID: mode == .favorite ? nil : target.id) } }
        dismiss()
    }
}

enum SingleSmartImportMode: String, CaseIterable, Identifiable {
    case text = "文字"
    case image = "截图"

    var id: String { rawValue }
}

private struct SingleItinerarySmartImportView: View {
    let referenceDate: Date
    let purpose: SmartArrangementRecognitionPurpose
    let onCancel: () -> Void
    let onRecognized: (ItineraryScreenshotDraft) -> Void

    @State private var mode: SingleSmartImportMode
    @State private var inputText = ""
    @State private var imageItems: [PhotosPickerItem] = []
    @State private var showsImagePicker = false
    @State private var isRecognizing = false
    @State private var errorMessage: String?
    @State private var offersPhotoSettings = false
    @State private var pendingFallbackDraft: ItineraryScreenshotDraft?
    @FocusState private var isInputFocused: Bool

    init(
        initialMode: SingleSmartImportMode,
        referenceDate: Date,
        purpose: SmartArrangementRecognitionPurpose,
        onCancel: @escaping () -> Void,
        onRecognized: @escaping (ItineraryScreenshotDraft) -> Void
    ) {
        self.referenceDate = referenceDate
        self.purpose = purpose
        self.onCancel = onCancel
        self.onRecognized = onRecognized
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        TripNavigationStack {
            Form {
                Section {
                    Picker("录入方式", selection: $mode) {
                        ForEach(SingleSmartImportMode.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .text {
                    Section("安排内容") {
                        ZStack(alignment: .topLeading) {
                            if inputText.isEmpty {
                                Text("粘贴 1 个安排或地点的描述")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $inputText).clearableText($inputText, alignment: .topTrailing)
                                .focused($isInputFocused)
                                .frame(height: 220)
                                .scrollContentBackground(.hidden)
                                .clipped()
                        }
                        .frame(height: 220)
                        .clipped()
                    }
                } else {
                    Section("安排截图") {
                        Text("上传 1 个安排或地点的截图")
                            .font(.subheadline).foregroundStyle(.secondary)
                        imageSelectionGrid
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .photosPicker(
                isPresented: $showsImagePicker,
                selection: $imageItems,
                maxSelectionCount: 1,
                selectionBehavior: .ordered,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: mode) { _, newMode in
                guard newMode == .image else { return }
                requestImageSelection()
            }
            .onAppear {
                if mode == .image {
                    requestImageSelection()
                }
            }
            .navigationTitle("智能录入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { isInputFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    recognize()
                } label: {
                    HStack {
                        if isRecognizing { ProgressView().controlSize(.small) }
                        Label(isRecognizing ? "识别中…" : "开始识别", systemImage: "wand.and.stars")
                    }
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                    .foregroundStyle(hasInput && !isRecognizing ? Color.white : Color.tripInk.opacity(0.58))
                    .padding(.vertical, 13)
                    .background(
                        hasInput && !isRecognizing ? Color.tripLake : Color.tripMist.opacity(0.52),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRecognizing || !hasInput)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .alert("智能录入", isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                        offersPhotoSettings = false
                        pendingFallbackDraft = nil
                    }
                }
            )) {
                if let pendingFallbackDraft {
                    Button("使用本地结果") {
                        clearRecognitionAlert()
                        onRecognized(pendingFallbackDraft)
                    }
                    Button("重试大模型") {
                        clearRecognitionAlert()
                        recognize()
                    }
                } else if !offersPhotoSettings, hasInput {
                    Button("重试") {
                        clearRecognitionAlert()
                        recognize()
                    }
                }
                Button("知道了", role: .cancel) {
                    clearRecognitionAlert()
                }
                if offersPhotoSettings {
                    Button("去设置") {
                        clearRecognitionAlert()
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var selectedImageAssets: [PickedAsset] {
        PhotoLibraryService.pickedAssets(from: imageItems)
    }

    private var imageSelectionGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(selectedImageAssets) { asset in
                AssetThumbnail(identifier: asset.id)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button { imageItems.removeAll { $0.itemIdentifier == asset.id } } label: {
                            Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55)).frame(width: 36, height: 36)
                        }.buttonStyle(.plain).accessibilityLabel("移除截图")
                    }
            }

            if selectedImageAssets.isEmpty {
            Button {
                requestImageSelection()
            } label: {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.tripLake.opacity(0.08))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                Color.tripLake.opacity(0.38),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    }
                    .overlay {
                        Image(systemName: selectedImageAssets.isEmpty ? "photo.stack" : "plus")
                            .font(.title3.bold())
                            .foregroundStyle(Color.tripLake)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selectedImageAssets.isEmpty ? "选择截图" : "重新选择截图")
            }
        }
    }

    private func requestImageSelection() {
        Task { @MainActor in
            let authorization = await PhotoLibraryService.requestReadWriteAccessIfNeeded()
            if authorization == .authorized || authorization == .limited {
                showsImagePicker = true
            } else {
                offersPhotoSettings = authorization == .denied || authorization == .restricted
                errorMessage = PhotoLibraryService.permissionGuidance
            }
        }
    }

    private var hasInput: Bool {
        switch mode {
        case .text: !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image: !imageItems.isEmpty
        }
    }

    private func clearRecognitionAlert() {
        errorMessage = nil
        offersPhotoSettings = false
        pendingFallbackDraft = nil
    }

    private func recognize() {
        isInputFocused = false
        isRecognizing = true
        Task { @MainActor in
            defer { isRecognizing = false }
            do {
                offersPhotoSettings = false
                let draft: ItineraryScreenshotDraft
                switch mode {
                case .text:
                    draft = try await SmartItineraryRecognitionService.recognizeSingleItemText(
                        inputText,
                        referenceDate: referenceDate,
                        purpose: purpose
                    )
                case .image:
                    var imageDatas: [Data] = []
                    var identifiers: [String] = []
                    for item in imageItems {
                        if let data = try await item.loadTransferable(type: Data.self) {
                            imageDatas.append(data)
                            if let identifier = item.itemIdentifier { identifiers.append(identifier) }
                        }
                    }
                    draft = try await SmartItineraryRecognitionService.recognizeSingleItem(
                        imageDatas: imageDatas,
                        referenceDate: referenceDate,
                        sourceAssetIdentifiers: identifiers,
                        purpose: purpose
                    )
                }
                if let recognitionNotice = draft.recognitionNotice {
                    pendingFallbackDraft = draft
                    errorMessage = recognitionNotice
                } else {
                    onRecognized(draft)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// Local gestures avoid Form promoting a transferable drag to the entire list row.
private struct MediaCellFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
struct ReorderableMediaGrid<Tile: View, AddTile: View>: View {
    let assets: [AssetMediaPreviewItem]
    @Binding var order: [String]
    @ViewBuilder let tile: (AssetMediaPreviewItem) -> Tile
    @ViewBuilder let addTile: () -> AddTile
    @State private var spaceID = UUID()
    @State private var frames: [String: CGRect] = [:]
    @State private var draggedID: String?
    @State private var origin: CGPoint?
    @GestureState private var dragging = false

    static func ordered(_ assets: [AssetMediaPreviewItem], order: [String]) -> [AssetMediaPreviewItem] {
        let ids = order.filter { id in assets.contains { $0.identifier == id } }
            + assets.map(\.identifier).filter { !order.contains($0) }
        return ids.compactMap { id in assets.first { $0.identifier == id } }
    }
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Self.ordered(assets, order: order)) { asset in
                tile(asset)
                    .contentShape(Rectangle())
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: MediaCellFrames.self, value: [asset.identifier: proxy.frame(in: .named(spaceID))])
                    })
                    .overlay { if draggedID == asset.identifier { RoundedRectangle(cornerRadius: 12).stroke(Color.tripLake, lineWidth: 3).allowsHitTesting(false) } }
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.3).sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(spaceID)))
                        .updating($dragging) { value, state, _ in if case .second(true, _) = value { state = true } }
                        .onChanged { value in
                            guard case .second(true, let drag?) = value else { return }
                            if draggedID == nil {
                                draggedID = asset.identifier
                                origin = drag.startLocation
                            }
                            guard draggedID == asset.identifier, origin != nil else { return }
                            let point = drag.location
                            guard let target = frames.first(where: { $0.key != asset.identifier && $0.value.contains(point) })?.key else { return }
                            var ids = Self.ordered(assets, order: order).map(\.identifier)
                            guard let from = ids.firstIndex(of: asset.identifier), let to = ids.firstIndex(of: target) else { return }
                            ids.remove(at: from); ids.insert(asset.identifier, at: to)
                            withAnimation(.easeInOut(duration: 0.15)) { order = ids }
                        }
                        .onEnded { _ in draggedID = nil; origin = nil })
            }
            addTile()
        }
        .coordinateSpace(name: spaceID)
        .onPreferenceChange(MediaCellFrames.self) { frames = $0 }
        .onChange(of: dragging) { _, active in if !active { draggedID = nil; origin = nil } }
    }
}
