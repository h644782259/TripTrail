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

    @State private var title: String
    @State private var locationMode: ArrangementLocationMode
    @State private var placeName: String
    @State private var placeAddress: String
    @State private var originName: String
    @State private var originAddress: String
    @State private var destinationName: String
    @State private var destinationAddress: String
    @State private var category: PlaceCategory
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var isFixedTime: Bool
    @State private var note: String
    @State private var transport: TransportMode
    @State private var distanceText: String
    @State private var costText: String
    @State private var showsSmartImport = false
    @State private var smartImportMode: SingleSmartImportMode
    @State private var smartImportFeedback: String?
    @State private var smartImportUsedFallback = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickedAssets: [PickedAsset] = []
    @State private var removedMediaIDs: Set<UUID> = []
    @State private var mediaWarning: String?
    @State private var mediaPreview: AssetMediaPreviewRequest?

    init(
        day: TripDay?,
        item: ItineraryItem? = nil,
        mode: ItemEditorMode = .itinerary,
        startsWithSmartImport: Bool = false,
        initialSmartImportMode: SingleSmartImportMode = .text
    ) {
        self.day = day
        self.item = item
        self.mode = mode
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
        let isLegacyItem = item?.locationModeRaw.isEmpty != false
        _locationMode = State(initialValue: item?.locationMode ?? .single)
        _placeName = State(initialValue: item.map {
            $0.placeName.isEmpty && isLegacyItem ? $0.title : $0.placeName
        } ?? "")
        _placeAddress = State(initialValue: item.map {
            $0.placeAddress.isEmpty && isLegacyItem ? $0.address : $0.placeAddress
        } ?? "")
        _originName = State(initialValue: item?.originName ?? "")
        _originAddress = State(initialValue: item?.originAddress ?? "")
        _destinationName = State(initialValue: item?.destinationName ?? "")
        _destinationAddress = State(initialValue: item?.destinationAddress ?? "")
        _category = State(initialValue: item?.category ?? .attraction)
        _startTime = State(initialValue: initialStartTime)
        _endTime = State(initialValue: initialEndTime)
        _isFixedTime = State(initialValue: item?.isFixedTime ?? false)
        _note = State(initialValue: item?.note ?? "")
        _transport = State(initialValue: item?.transport ?? .car)
        _distanceText = State(initialValue: item?.distanceText ?? "")
        _costText = State(initialValue: item.map { $0.cost == 0 ? "" : String($0.cost) } ?? "")
        _showsSmartImport = State(initialValue: startsWithSmartImport && item == nil)
        _smartImportMode = State(initialValue: initialSmartImportMode)
    }

    var body: some View {
        TripNavigationStack {
            Form {
                if item == nil {
                    Section {
                        Button { showsSmartImport = true } label: {
                            Label("智能录入", systemImage: "wand.and.stars")
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

                Section("安排") {
                    VStack(alignment: .leading, spacing: 6) {
                        editorFieldLabel("安排名称/说明")
                        TextField("例如：广州 → 上海、游览世纪公园", text: $title)
                            .accessibilityLabel("安排名称或说明")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        editorFieldLabel("补充说明")
                        TextField("例如：先寄存行李，下午两点后办理入住", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .accessibilityLabel("补充说明")
                    }
                    Picker("类型", selection: $category) {
                        ForEach(PlaceCategory.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                    if mode == .itinerary {
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

                Section("地点") {
                    Picker("地点类型", selection: $locationMode) {
                        ForEach(ArrangementLocationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if locationMode == .single {
                        VStack(alignment: .leading, spacing: 6) {
                            editorFieldLabel("地点名称")
                            TextField("例如：上海世纪公园", text: $placeName)
                                .accessibilityLabel("地点名称")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            editorFieldLabel("详细地址（选填）")
                            TextField("用于提高地图匹配准确度", text: $placeAddress, axis: .vertical)
                                .lineLimit(1...3)
                                .accessibilityLabel("地点详细地址")
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
                        TextField("输入金额", text: $costText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("花费")
                    }
                }

                Section {
                    Picker("前往方式", selection: $transport) {
                        ForEach(TransportMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        editorFieldLabel("路程说明")
                        TextField("例如：6.8 km · 25 分钟", text: $distanceText)
                            .accessibilityLabel("路程说明")
                    }
                } header: {
                    Text("路程")
                }

                Section("照片与视频") {
                    let visibleMedia = (item?.media ?? [])
                        .filter { !removedMediaIDs.contains($0.id) }
                        .sorted { $0.sortOrder < $1.sortOrder }
                    if !visibleMedia.isEmpty || !pickedAssets.isEmpty {
                        mediaGrid(existing: visibleMedia, picked: pickedAssets)
                    }
                    PermissionAwarePhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 20,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label("从系统相簿选择", systemImage: "photo.on.rectangle.angled")
                    }
                    Text("删除相簿原素材后，这里将无法显示。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(
                        title.trimmingCharacters(in: .whitespaces).isEmpty
                            || (mode == .itinerary && endTime <= startTime)
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
            .sheet(isPresented: $showsSmartImport) {
                SingleItinerarySmartImportView(
                    initialMode: smartImportMode,
                    referenceDate: startTime,
                    purpose: mode == .favorite ? .favorite : .itinerary,
                    onCancel: { showsSmartImport = false },
                    onRecognized: { draft in
                        applyRecognizedDraft(draft)
                        showsSmartImport = false
                    }
                )
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

    private func locationFields(
        title: String,
        name: Binding<String>,
        address: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            editorFieldLabel(title)
            TextField("\(title)名称", text: name)
                .accessibilityLabel("\(title)名称")
            TextField("\(title)详细地址（选填）", text: address, axis: .vertical)
                .lineLimit(1...3)
                .accessibilityLabel("\(title)详细地址")
        }
    }

    private var previewMediaItems: [AssetMediaPreviewItem] {
        (item?.media ?? [])
            .filter { !removedMediaIDs.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { AssetMediaPreviewItem(identifier: $0.localIdentifier, kind: $0.kind) }
        + pickedAssets
            .map { AssetMediaPreviewItem(identifier: $0.id, kind: $0.kind) }
    }

    private func applyRecognizedDraft(_ draft: ItineraryScreenshotDraft) {
        if !draft.title.isEmpty, draft.title != "待补充的安排" { title = draft.title }
        category = draft.category
        startTime = draft.startTime
        endTime = draft.endTime
        locationMode = draft.locationMode
        if !draft.placeName.isEmpty { placeName = draft.placeName }
        if !draft.placeAddress.isEmpty { placeAddress = draft.placeAddress }
        if !draft.originName.isEmpty { originName = draft.originName }
        if !draft.originAddress.isEmpty { originAddress = draft.originAddress }
        if !draft.destinationName.isEmpty { destinationName = draft.destinationName }
        if !draft.destinationAddress.isEmpty { destinationAddress = draft.destinationAddress }
        if locationMode == .single, placeName.isEmpty, !draft.address.isEmpty {
            placeName = draft.title
            placeAddress = draft.address
        }
        transport = draft.transport
        if !draft.distanceText.isEmpty { distanceText = draft.distanceText }
        if draft.cost > 0 { costText = String(draft.cost) }
        for detail in [draft.reservationInfo, draft.note] where !detail.isEmpty && !note.contains(detail) {
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
            ForEach(existing) { reference in
                removableThumbnail(identifier: reference.localIdentifier, kind: reference.kind) {
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
        let thumbnail = AssetThumbnail(identifier: identifier, showsVideoBadge: kind == .video)
            .frame(height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

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
        target.address = locationMode == .single ? target.placeAddress : target.destinationAddress
        target.category = category
        if mode == .itinerary {
            let scheduleDay = day?.date ?? target.day?.date ?? startTime
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
            target.isFixedTime = isFixedTime
            if target.endTime <= target.startTime {
                target.endTime = target.startTime.addingTimeInterval(60)
            }
        }
        target.note = note
        target.transport = transport
        target.distanceText = distanceText
        target.playDurationMinutes = max(0, Int(target.endTime.timeIntervalSince(target.startTime) / 60))
        if let targetDay = target.day { JourneyHierarchyService.normalizeItems(targetDay.items) }
        target.cost = Double(costText.replacingOccurrences(of: ",", with: ".")) ?? 0
        target.isFavorite = mode == .favorite

        for reference in target.media where removedMediaIDs.contains(reference.id) {
            modelContext.delete(reference)
        }
        let activeMedia = target.media.filter { !removedMediaIDs.contains($0.id) }
        let existingIDs = Set(activeMedia.map(\.localIdentifier))
        let nextSortOrder = (activeMedia.map(\.sortOrder).max() ?? -1) + 1
        for (index, picked) in pickedAssets.filter({ !existingIDs.contains($0.id) }).enumerated() {
            let reference = MediaReference(localIdentifier: picked.id, kind: picked.kind, sortOrder: nextSortOrder + index)
            reference.itineraryItem = target
            target.media.append(reference)
        }
        dismiss()
    }
}

enum SingleSmartImportMode: String, CaseIterable, Identifiable {
    case text = "文字"
    case image = "图片"

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
                                Text("粘贴这一段安排的订单、导航或描述")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $inputText)
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
                        imageSelectionGrid
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .photosPicker(
                isPresented: $showsImagePicker,
                selection: $imageItems,
                maxSelectionCount: 10,
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
            .navigationTitle("智能录入安排")
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
                        Label(isRecognizing ? "识别中…" : "识别并预填", systemImage: "wand.and.stars")
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
            ForEach(selectedImageAssets) { asset in
                AssetThumbnail(identifier: asset.id)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

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
