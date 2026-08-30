import PhotosUI
import SwiftData
import SwiftUI

struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let day: TripDay?
    let item: ItineraryItem?

    @State private var title: String
    @State private var address: String
    @State private var category: PlaceCategory
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var note: String
    @State private var transport: TransportMode
    @State private var distanceText: String
    @State private var costText: String
    @State private var showsSmartImport = false
    @State private var smartImportFeedback: String?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickedAssets: [PickedAsset] = []
    @State private var removedMediaIDs: Set<UUID> = []
    @State private var mediaWarning: String?
    @State private var mediaPreview: AssetMediaPreviewRequest?

    init(day: TripDay?, item: ItineraryItem? = nil) {
        self.day = day
        self.item = item
        let base = day?.date ?? Date()
        let calendar = Calendar.current
        let defaultStart = day?.suggestedStartTime(calendar: calendar)
            ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base)
            ?? base
        _title = State(initialValue: item?.title ?? "")
        _address = State(initialValue: item?.address ?? "")
        _category = State(initialValue: item?.category ?? .attraction)
        _startTime = State(initialValue: item?.startTime ?? defaultStart)
        _endTime = State(initialValue: item?.endTime ?? calendar.date(byAdding: .hour, value: 1, to: defaultStart)!)
        _note = State(initialValue: item?.note ?? "")
        _transport = State(initialValue: item?.transport ?? .car)
        _distanceText = State(initialValue: item?.distanceText ?? "")
        _costText = State(initialValue: item.map { $0.cost == 0 ? "" : String($0.cost) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if item == nil {
                    Section {
                        Button { showsSmartImport = true } label: {
                            Label("智能录入", systemImage: "wand.and.stars")
                        }
                        if let smartImportFeedback {
                            Label(smartImportFeedback, systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("安排") {
                    VStack(alignment: .leading, spacing: 6) {
                        editorFieldLabel("地点")
                        TextField("例如：湖滨酒店", text: $title)
                            .accessibilityLabel("地点")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        editorFieldLabel("说明")
                        TextField("例如：先寄存行李，下午两点后办理入住", text: $address, axis: .vertical)
                            .lineLimit(2...5)
                            .accessibilityLabel("说明")
                    }
                    Picker("类型", selection: $category) {
                        ForEach(PlaceCategory.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                    TwoTapDateRangePicker(
                        title: "时间",
                        startTitle: "开始",
                        endTitle: "结束",
                        startDate: $startTime,
                        endDate: $endTime,
                        preservesTimeComponents: true,
                        showsTimeSelection: true,
                        showsEndpointTitles: false
                    )
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

                Section("补充信息") {
                    TextField("记录提醒或补充说明", text: $note, axis: .vertical)
                        .lineLimit(4...10)
                        .accessibilityLabel("补充信息")
                }

                Section("照片与视频") {
                    let visibleMedia = (item?.media ?? [])
                        .filter { !removedMediaIDs.contains($0.id) }
                        .sorted { $0.sortOrder < $1.sortOrder }
                    if !visibleMedia.isEmpty || !pickedAssets.isEmpty {
                        mediaGrid(existing: visibleMedia, picked: pickedAssets)
                    }
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 20,
                        matching: .any(of: [.images, .videos]),
                        photoLibrary: .shared()
                    ) {
                        Label("从系统相簿选择", systemImage: "photo.on.rectangle.angled")
                    }
                    Text("删除相簿原素材后，这里将无法显示。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(item == nil ? "添加安排" : "编辑安排")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: pickerItems) { _, newValue in
                consumePickerItems(newValue)
            }
            .sheet(isPresented: $showsSmartImport) {
                SingleItinerarySmartImportView(
                    referenceDate: startTime,
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

    private func editorFieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
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
        if !draft.address.isEmpty { address = draft.address }
        if title.isEmpty, !draft.address.isEmpty { title = draft.address }
        transport = draft.transport
        if !draft.distanceText.isEmpty { distanceText = draft.distanceText }
        if !draft.reservationInfo.isEmpty, !note.contains(draft.reservationInfo) {
            note = [note, draft.reservationInfo].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        if draft.cost > 0 { costText = String(draft.cost) }
        if !draft.note.isEmpty { note = draft.note }
        let existingIDs = Set(pickedAssets.map(\.id))
        pickedAssets.append(contentsOf: draft.sourceAssetIdentifiers
            .filter { !existingIDs.contains($0) }
            .map { PickedAsset(id: $0, kind: .image) })
        smartImportFeedback = "已预填，可继续修改。"
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
        } else {
            guard let day else { return }
            target = ItineraryItem(title: title, category: category, startTime: startTime, endTime: endTime, sortOrder: day.items.count)
            target.day = day
            day.items.append(target)
        }

        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        target.category = category
        target.startTime = startTime
        target.endTime = endTime
        target.note = note
        target.transport = transport
        target.distanceText = distanceText
        target.playDurationMinutes = max(0, Int(endTime.timeIntervalSince(startTime) / 60))
        target.cost = Double(costText.replacingOccurrences(of: ",", with: ".")) ?? 0

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

private enum SingleSmartImportMode: String, CaseIterable, Identifiable {
    case text = "文字"
    case image = "图片"

    var id: String { rawValue }
}

private struct SingleItinerarySmartImportView: View {
    let referenceDate: Date
    let onCancel: () -> Void
    let onRecognized: (ItineraryScreenshotDraft) -> Void

    @State private var mode: SingleSmartImportMode = .text
    @State private var inputText = ""
    @State private var imageItems: [PhotosPickerItem] = []
    @State private var isRecognizing = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
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
                                .frame(minHeight: 190)
                                .scrollContentBackground(.hidden)
                        }
                    }
                } else {
                    Section("安排截图") {
                        PhotosPicker(
                            selection: $imageItems,
                            maxSelectionCount: 10,
                            selectionBehavior: .ordered,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label(
                                imageItems.isEmpty ? "选择截图" : "已选择 \(imageItems.count) 张，重新选择",
                                systemImage: "photo.stack"
                            )
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
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
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRecognizing || !hasInput)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .alert("智能录入", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var hasInput: Bool {
        switch mode {
        case .text: !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image: !imageItems.isEmpty
        }
    }

    private func recognize() {
        isInputFocused = false
        isRecognizing = true
        Task { @MainActor in
            defer { isRecognizing = false }
            do {
                let draft: ItineraryScreenshotDraft
                switch mode {
                case .text:
                    draft = try ScreenshotItineraryImportService.parseInputText(
                        inputText,
                        referenceDate: referenceDate
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
                    draft = try await ScreenshotItineraryImportService.recognize(
                        imageDatas: imageDatas,
                        referenceDate: referenceDate,
                        sourceAssetIdentifiers: identifiers
                    )
                }
                onRecognized(draft)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
