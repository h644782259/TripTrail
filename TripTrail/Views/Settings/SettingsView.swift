import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(EnhancedRecognitionSettings.enabledDefaultsKey)
    private var enhancedRecognitionEnabled = ZhipuAPIKeyStore.hasAPIKey
    @State private var message: String?
    @State private var backupExportRequest: BackupExportRequest?
    @State private var backupExportResult: BackupExportResult?
    @State private var isPreparingBackup = false
    @State private var preparedBackupMediaCount = 0
    @State private var importRequest: DocumentImportRequest?
    @State private var pendingRestoreURL: URL?
    @State private var pendingRestoreSummary: TripTrailBackupSummary?
    @State private var isConfirmingRestore = false
    @State private var pendingSharedJourneyURL: URL?
    @State private var pendingSharedJourneySummary: SharedJourneySummary?
    @State private var isConfirmingSharedJourney = false
    @State private var showsCreatorReward = false
    @State private var zhipuAPIKeyInput = ZhipuAPIKeyStore.load() ?? ""
    @State private var deepSeekAPIKeyInput = DeepSeekAPIKeyStore.load() ?? ""
    @AppStorage(EnhancedRecognitionSettings.providerDefaultsKey) private var recognitionProvider = EnhancedRecognitionSettings.Provider.zhipu.rawValue
    @State private var isZhipuAPIKeyVisible = false
    @State private var hasZhipuAPIKey = ZhipuAPIKeyStore.hasAPIKey
    @State private var isZhipuAPIKeyDirty = false
    @State private var apiKeySaveTask: Task<Void, Never>?
    @State private var isAddingSampleTrip = false
    @FocusState private var isZhipuAPIKeyFocused: Bool

    var body: some View {
        List {
            Section("开始体验") {
                Button { addSampleTrip() } label: {
                    Label(isAddingSampleTrip ? "正在准备示例旅程…" : "添加示例旅程", systemImage: "wand.and.stars")
                }
                .disabled(isAddingSampleTrip)
            }

            Section("旅行概览") {
                NavigationLink {
                    TripStatisticsView()
                } label: {
                    Label("旅行统计", systemImage: "chart.bar.fill")
                }
            }

            Section {
                Toggle(
                    "使用大模型智能识别",
                    isOn: $enhancedRecognitionEnabled
                )

                if enhancedRecognitionEnabled {
                    Picker("模型", selection: $recognitionProvider) {
                        ForEach(EnhancedRecognitionSettings.Provider.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .onChange(of: recognitionProvider) { _, _ in
                        finishEditingAPIKeys()
                        hasZhipuAPIKey = !activeAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    HStack(spacing: 10) {
                        Group {
                            if isZhipuAPIKeyVisible {
                                TextField(activeProvider.apiKeyLabel, text: activeAPIKeyBinding)
                            } else {
                                SecureField(activeProvider.apiKeyLabel, text: activeAPIKeyBinding)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                        .privacySensitive()
                        .focused($isZhipuAPIKeyFocused)

                        Button {
                            isZhipuAPIKeyVisible.toggle()
                        } label: {
                            Image(systemName: isZhipuAPIKeyVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isZhipuAPIKeyVisible ? "隐藏 API Key" : "显示 API Key")
                    }
                    .onChange(of: zhipuAPIKeyInput) { _, newValue in
                        handleAPIKeyInputChange(newValue)
                    }
                }
            } header: {
                Text("智能识别")
            }

            Section {
                Button(action: exportBackup) {
                    if isPreparingBackup {
                        Label("正在读取并打包媒体…", systemImage: "hourglass")
                    } else {
                        Label("导出备份", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isPreparingBackup)
                Button { importRequest = DocumentImportRequest(kind: .backup) } label: {
                    Label("恢复备份", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("备份与恢复")
            } footer: {
                Text("含照片和视频；恢复将替换本机数据。")
            }

            Section {
                Button { importRequest = DocumentImportRequest(kind: .sharedJourney) } label: {
                    Label("导入旅程或足迹", systemImage: "square.and.arrow.down.on.square")
                }
            } header: {
                Text("接收分享")
            }

            Section("数据与隐私") {
                Label("数据存在本机", systemImage: "lock.shield")
                Label("删除相簿原图后，图片将无法显示", systemImage: "exclamationmark.triangle")
            }

            Section("关于") {
                Button {
                    showsCreatorReward = true
                } label: {
                    HStack {
                        Text("创作者")
                        Spacer()
                        Text("黄逸轩")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                LabeledContent("版本", value: "0.1.0")
                LabeledContent("系统要求", value: "iOS 17+")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hasZhipuAPIKey = !activeAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !hasZhipuAPIKey {
                enhancedRecognitionEnabled = false
            }
        }
        .onChange(of: enhancedRecognitionEnabled) { _, isEnabled in
            if isEnabled, !hasZhipuAPIKey {
                Task { @MainActor in
                    await Task.yield()
                    isZhipuAPIKeyFocused = true
                }
            } else if !isEnabled {
                isZhipuAPIKeyFocused = false
                flushPendingZhipuAPIKeyChange()
            }
        }
        .onChange(of: isZhipuAPIKeyFocused) { wasFocused, isFocused in
            guard wasFocused, !isFocused else { return }
            finishEditingZhipuAPIKey()
        }
        .onDisappear {
            finishEditingZhipuAPIKey()
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 72)
        }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
        .alert("恢复这份备份？", isPresented: $isConfirmingRestore) {
            Button("取消", role: .cancel) {
                pendingRestoreURL = nil
                pendingRestoreSummary = nil
            }
            Button("替换本机数据", role: .destructive, action: restorePendingBackup)
        } message: {
            Text(restoreConfirmationText)
        }
        .alert("收藏这份内容？", isPresented: $isConfirmingSharedJourney) {
            Button("取消", role: .cancel) {
                pendingSharedJourneyURL = nil
                pendingSharedJourneySummary = nil
            }
            Button("添加到我的旅迹", action: importPendingSharedJourney)
        } message: {
            Text(sharedJourneyConfirmationText)
        }
        .sheet(item: $backupExportRequest, onDismiss: finishBackupExport) { request in
            DocumentExportPicker(url: request.url) { result in
                backupExportResult = result
                backupExportRequest = nil
            }
        }
        .sheet(item: $importRequest) { request in
            DocumentImportPicker(contentTypes: request.kind.allowedContentTypes) { result in
                importRequest = nil
                Task { @MainActor in
                    await Task.yield()
                    if case .failure(let error) = result, error is CancellationError {
                        return
                    }
                    switch request.kind {
                    case .backup:
                        handleImportedBackup(result)
                    case .sharedJourney:
                        handleImportedSharedJourney(result)
                    }
                }
            }
        }
        .sheet(isPresented: $showsCreatorReward) {
            CreatorRewardView()
        }
    }

    private func handleAPIKeyInputChange(_ value: String) {
        apiKeySaveTask?.cancel()
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        hasZhipuAPIKey = !candidate.isEmpty
        isZhipuAPIKeyDirty = true

        apiKeySaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            guard candidate == activeAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            if persistAPIKey(candidate) {
                isZhipuAPIKeyDirty = false
                apiKeySaveTask = nil
            }
        }
    }

    @discardableResult
    private func persistZhipuAPIKey(_ key: String) -> Bool {
        do {
            if key.isEmpty {
                try ZhipuAPIKeyStore.delete()
            } else {
                try ZhipuAPIKeyStore.save(key)
            }
            return true
        } catch {
            hasZhipuAPIKey = ZhipuAPIKeyStore.hasAPIKey
            message = error.localizedDescription
            return false
        }
    }

    private var activeProvider: EnhancedRecognitionSettings.Provider { EnhancedRecognitionSettings.Provider(rawValue: recognitionProvider) ?? .zhipu }
    private var activeAPIKeyInput: String { activeProvider == .zhipu ? zhipuAPIKeyInput : deepSeekAPIKeyInput }
    private var activeAPIKeyBinding: Binding<String> {
        Binding(get: { activeAPIKeyInput }, set: { value in
            if activeProvider == .zhipu { zhipuAPIKeyInput = value } else { deepSeekAPIKeyInput = value }
            handleAPIKeyInputChange(value)
        })
    }
    private func persistAPIKey(_ key: String) -> Bool {
        do {
            if activeProvider == .zhipu { try key.isEmpty ? ZhipuAPIKeyStore.delete() : ZhipuAPIKeyStore.save(key) }
            else { try key.isEmpty ? DeepSeekAPIKeyStore.delete() : DeepSeekAPIKeyStore.save(key) }
            return true
        } catch { message = error.localizedDescription; return false }
    }
    private func finishEditingAPIKeys() { flushPendingZhipuAPIKeyChange() }

    private func finishEditingZhipuAPIKey() {
        let candidate = flushPendingZhipuAPIKeyChange()
        if candidate.isEmpty {
            enhancedRecognitionEnabled = false
        }
    }

    @discardableResult
    private func flushPendingZhipuAPIKeyChange() -> String {
        apiKeySaveTask?.cancel()
        apiKeySaveTask = nil
        let candidate = activeAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        hasZhipuAPIKey = !candidate.isEmpty
        if isZhipuAPIKeyDirty, persistAPIKey(candidate) {
            isZhipuAPIKeyDirty = false
        }
        return candidate
    }

    private func exportBackup() {
        isPreparingBackup = true
        Task {
            do {
                let result = try await DataBackupService.makeBackupPackage(from: modelContext)
                preparedBackupMediaCount = result.mediaCount
                let filename = "TripTrail-Backup-\(Self.backupDateFormatter.string(from: Date())).triptrailbackup"
                let namedURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try FileManager.default.moveItem(at: result.url, to: namedURL)
                backupExportRequest = BackupExportRequest(url: namedURL)
            } catch {
                message = "生成备份失败：\(error.localizedDescription)"
            }
            isPreparingBackup = false
        }
    }

    private func finishBackupExport() {
        guard let result = backupExportResult else { return }
        backupExportResult = nil
        switch result {
        case .exported:
            message = "完整备份已导出，包含 \(preparedBackupMediaCount) 个照片或视频原件。请保存到安全位置。"
        case .cancelled:
            break
        }
    }

    private func handleImportedBackup(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            message = "无法读取备份：\(error.localizedDescription)"
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let copy = try PortablePackageService.temporaryCopy(of: url)
                pendingRestoreSummary = try DataBackupService.inspectBackup(at: copy)
                pendingRestoreURL = copy
                isConfirmingRestore = true
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private var restoreConfirmationText: String {
        guard let summary = pendingRestoreSummary else { return "将替换本机当前数据。" }
        return "备份包含\(summary.restoreDescription)。恢复后将替换本机当前的所有旅程、足迹和收藏，此操作不可撤销。"
    }

    private func restorePendingBackup() {
        guard let url = pendingRestoreURL else { return }
        Task {
            do {
                let summary = try await DataBackupService.restoreBackup(from: url, into: modelContext)
                message = "恢复完成：\(summary.restoreDescription)。"
            } catch {
                message = error.localizedDescription
            }
            pendingRestoreURL = nil
            pendingRestoreSummary = nil
        }
    }

    private func handleImportedSharedJourney(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            message = "无法读取分享文件：\(error.localizedDescription)"
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let copy = try PortablePackageService.temporaryCopy(of: url)
                pendingSharedJourneySummary = try SharedJourneyService.inspect(at: copy)
                pendingSharedJourneyURL = copy
                isConfirmingSharedJourney = true
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private var sharedJourneyConfirmationText: String {
        guard let summary = pendingSharedJourneySummary else { return "内容会追加到你的旅迹。" }
        return "将\(summary.importDescription)添加为你的独立副本，不会覆盖本机已有内容。"
    }

    private func importPendingSharedJourney() {
        guard let url = pendingSharedJourneyURL else { return }
        Task {
            do {
                let result = try await SharedJourneyService.importJourney(from: url, into: modelContext)
                message = result.wasAlreadyPresent
                    ? "这份\(result.summary.kind.displayName)已经收藏过了。"
                    : "已收藏\(result.summary.importDescription)。"
            } catch {
                message = error.localizedDescription
            }
            pendingSharedJourneyURL = nil
            pendingSharedJourneySummary = nil
        }
    }

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    private func addSampleTrip() {
        guard !isAddingSampleTrip else { return }
        isAddingSampleTrip = true
        Task { @MainActor in
            let media = await importSampleMedia()
            let trip = makeFeatureRichSampleTrip(media: media)
            modelContext.insert(trip)
            do {
                try modelContext.save()
                message = media.hasAnyMedia
                    ? "示例旅程已添加，可从“旅程”页体验完整功能。"
                    : "示例旅程已添加。未获取到相簿权限，因此未加入示例图片和视频。"
            } catch {
                message = "示例旅程添加失败：\(error.localizedDescription)"
            }
            isAddingSampleTrip = false
        }
    }

    private func importSampleMedia() async -> SampleJourneyMedia {
        let authorization = await PhotoLibraryService.requestReadWriteAccessIfNeeded()
        guard authorization == .authorized || authorization == .limited else { return .empty }

        func importResource(_ name: String, extension fileExtension: String, kind: MediaKind) async -> String? {
            guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else { return nil }
            return try? await PhotoLibraryService.importAssetFile(at: url, kind: kind)
        }

        return SampleJourneyMedia(
            lake: await importResource("triptrail-demo-lake", extension: "png", kind: .image),
            city: await importResource("triptrail-demo-city", extension: "png", kind: .image),
            motion: await importResource("triptrail-demo-motion", extension: "mov", kind: .video)
        )
    }

    private func makeFeatureRichSampleTrip(media: SampleJourneyMedia) -> Trip {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let firstDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let lastDate = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        func at(_ hour: Int, _ minute: Int = 0, on date: Date) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }
        let endOfToday = at(23, 50, on: today)
        let currentWalkStart = min(now.addingTimeInterval(-30 * 60), endOfToday.addingTimeInterval(-90 * 60))
        let currentWalkEnd = min(now.addingTimeInterval(60 * 60), endOfToday.addingTimeInterval(-45 * 60))
        let lakesideStart = currentWalkEnd.addingTimeInterval(15 * 60)

        let trip = Trip(
            title: "杭州山水三日",
            destination: "杭州",
            startDate: firstDate,
            endDate: lastDate,
            note: "从西湖晨光到龙井茶山，一段有路线、预约、花费和影像记录的完整示例旅程。"
        )

        let arrivalDay = TripDay(date: firstDate, title: "抵达与安顿", sortOrder: 0, trip: trip)
        arrivalDay.note = "先放好行李，再用一段轻松的湖边散步开始旅程。"
        let lakeDay = TripDay(date: today, title: "西湖一日", sortOrder: 1, trip: trip)
        lakeDay.note = "不赶景点，把时间留给湖面、风和一顿杭帮菜。"
        let teaDay = TripDay(date: lastDate, title: "茶山与返程", sortOrder: 2, trip: trip)
        teaDay.note = "上午慢走茶园，下午买好伴手礼后前往车站。"
        trip.days = [arrivalDay, lakeDay, teaDay]

        let train = sampleItem(
            title: "高铁前往杭州", category: .transport,
            start: at(8, 0, on: firstDate), end: at(9, 5, on: firstDate), order: 0, day: arrivalDay,
            transport: .train, distance: "高铁 1 小时 5 分", duration: 65,
            reservation: "G7311 · 08车12A", cost: 73,
            note: "提前 30 分钟到站，抵达后从东广场出站。"
        )
        train.locationMode = .route
        train.originName = "上海虹桥站"
        train.originAddress = "上海市闵行区申贵路1500号"
        train.destinationName = "杭州东站"
        train.destinationAddress = "杭州市上城区全福桥路2号"

        let hotel = sampleItem(
            title: "办理酒店入住", category: .hotel,
            start: at(10, 0, on: firstDate), end: at(10, 30, on: firstDate), order: 1, day: arrivalDay,
            place: "杭州西湖湖滨酒店", address: "杭州市上城区湖滨路",
            transport: .bus, distance: "地铁 1 号线·龙翔桥站", duration: 30,
            reservation: "大床房 · 含早", cost: 688,
            note: "先寄存行李，14:00 后取房卡。"
        )

        let packing = sampleItem(
            title: "整理随身物品", category: .other,
            start: at(10, 40, on: firstDate), end: at(11, 0, on: firstDate), order: 2, day: arrivalDay,
            place: "杭州西湖湖滨酒店", transport: .walk, distance: "酒店内", duration: 20,
            reservation: "", cost: 0,
            note: "只带相机、雨伞和充电宝，大件行李留在酒店。"
        )
        arrivalDay.items = [train, hotel, packing]

        let bridge = sampleItem(
            title: "沿白堤看西湖晨光", category: .attraction,
            start: at(7, 30, on: today), end: at(9, 0, on: today), order: 0, day: lakeDay,
            place: "断桥残雪", address: "杭州市西湖区白堤东端",
            transport: .walk, distance: "步行 1.8 公里", duration: 90,
            reservation: "无需预约", cost: 0,
            note: "从断桥慢慢走到平湖秋月，清晨人少，适合拍湖面反光。"
        )
        attachSampleMedia(media.lake, kind: .image, caption: "西湖晨光", order: 0, to: bridge)
        attachSampleMedia(media.motion, kind: .video, caption: "湖边的风", order: 1, to: bridge)

        let lunch = sampleItem(
            title: "品尝杭帮菜", category: .restaurant,
            start: at(11, 30, on: today), end: at(13, 0, on: today), order: 1, day: lakeDay,
            place: "楼外楼（孤山店）", address: "杭州市西湖区孤山路30号",
            transport: .walk, distance: "步行 900 米", duration: 90,
            reservation: "12:00 · 2人 · 临窗位", cost: 328,
            note: "尝试西湖醋鱼和龙井虾仁，用餐后可在孤山稍作休息。"
        )
        lunch.isFavorite = true
        lunch.favoriteCreatedAt = now

        let currentWalk = sampleItem(
            title: "湖畔自由漫步", category: .attraction,
            start: currentWalkStart, end: currentWalkEnd, order: 2, day: lakeDay,
            place: "曲院风荷", address: "杭州市西湖区北山街89号",
            transport: .walk, distance: "环湖步行约 2.4 公里", duration: 90,
            reservation: "", cost: 0,
            note: "这段安排示范“进行中”状态，状态会随当前时间自动更新。"
        )

        let sunset = sampleItem(
            title: "湖滨散步与拍照", category: .special,
            start: lakesideStart, end: endOfToday, order: 3, day: lakeDay,
            place: "集贤亭", address: "杭州市上城区湖滨路",
            transport: .ride, distance: "骑行约 3.2 公里", duration: 60,
            reservation: "日落前 30 分钟到达", cost: 15,
            note: "沿湖滨慢慢走，记录城市灯光与湖面；如果下雨就改成室内散步。"
        )
        attachSampleMedia(media.city, kind: .image, caption: "湖滨夜色", order: 0, to: sunset)
        lakeDay.items = [bridge, lunch, currentWalk, sunset]

        let teaGarden = sampleItem(
            title: "漫步龙井村茶园", category: .special,
            start: at(9, 0, on: lastDate), end: at(11, 30, on: lastDate), order: 0, day: teaDay,
            place: "龙井村", address: "杭州市西湖区龙井村",
            transport: .car, distance: "驾车约 11 公里", duration: 150,
            reservation: "茶室 09:30", cost: 120,
            note: "沿十里琅珰走一小段，穿防滑的鞋，留意山间天气。"
        )
        let shopping = sampleItem(
            title: "挑选杭州伴手礼", category: .other,
            start: at(14, 0, on: lastDate), end: at(15, 0, on: lastDate), order: 1, day: teaDay,
            place: "河坊街", address: "杭州市上城区河坊街",
            transport: .bus, distance: "公交约 35 分钟", duration: 60,
            reservation: "", cost: 180,
            note: "茶叶和桂花糕控制在一个手提袋内。"
        )
        let station = sampleItem(
            title: "前往杭州东站", category: .transport,
            start: at(16, 0, on: lastDate), end: at(16, 45, on: lastDate), order: 2, day: teaDay,
            transport: .bus, distance: "地铁约 35 分钟", duration: 45,
            reservation: "G7590 · 17:30 开车", cost: 6,
            note: "提前 40 分钟到站，进站前确认检票口。"
        )
        station.locationMode = .route
        station.originName = "河坊街"
        station.originAddress = "杭州市上城区河坊街"
        station.destinationName = "杭州东站"
        station.destinationAddress = "杭州市上城区全福桥路2号"
        teaDay.items = [teaGarden, shopping, station]

        for item in trip.allItems {
            item.completeIfElapsed(relativeTo: now)
        }

        return trip
    }

    private func sampleItem(
        title: String,
        category: PlaceCategory,
        start: Date,
        end: Date,
        order: Int,
        day: TripDay,
        place: String = "",
        address: String = "",
        transport: TransportMode,
        distance: String,
        duration: Int,
        reservation: String,
        cost: Double,
        note: String
    ) -> ItineraryItem {
        let item = ItineraryItem(title: title, category: category, startTime: start, endTime: end, sortOrder: order)
        item.locationMode = .single
        item.placeName = place
        item.placeAddress = address
        item.address = address
        item.transport = transport
        item.distanceText = distance
        item.playDurationMinutes = duration
        item.reservationInfo = reservation
        item.cost = cost
        item.note = note
        item.day = day
        return item
    }

    private func attachSampleMedia(
        _ identifier: String?,
        kind: MediaKind,
        caption: String,
        order: Int,
        to item: ItineraryItem
    ) {
        guard let identifier else { return }
        let media = MediaReference(localIdentifier: identifier, kind: kind, sortOrder: order)
        media.caption = caption
        media.itineraryItem = item
        item.media.append(media)
    }
}

private struct SampleJourneyMedia {
    let lake: String?
    let city: String?
    let motion: String?

    static let empty = SampleJourneyMedia(lake: nil, city: nil, motion: nil)
    var hasAnyMedia: Bool { lake != nil || city != nil || motion != nil }
}

private struct CreatorRewardView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TripNavigationStack {
            VStack {
                Spacer(minLength: 20)
                Image("CreatorReward")
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 7)
                Spacer(minLength: 20)
            }
            .padding()
            .background(Color.tripCanvas.ignoresSafeArea())
            .navigationTitle("创作者")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct BackupExportRequest: Identifiable {
    let id = UUID()
    let url: URL
}

private enum BackupExportResult {
    case exported
    case cancelled
}

private struct DocumentExportPicker: UIViewControllerRepresentable {
    let url: URL
    let onFinish: (BackupExportResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (BackupExportResult) -> Void

        init(onFinish: @escaping (BackupExportResult) -> Void) {
            self.onFinish = onFinish
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFinish(.exported)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish(.cancelled)
        }
    }
}

private enum DocumentImportKind {
    case backup
    case sharedJourney

    var allowedContentTypes: [UTType] {
        switch self {
        case .backup:
            [.tripTrailBackup, .json]
        case .sharedJourney:
            [.tripTrailJourney, .json]
        }
    }
}

private struct DocumentImportRequest: Identifiable {
    let id = UUID()
    let kind: DocumentImportKind
}

private struct DocumentImportPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onFinish: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (Result<URL, Error>) -> Void

        init(onFinish: @escaping (Result<URL, Error>) -> Void) {
            self.onFinish = onFinish
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onFinish(.failure(CocoaError(.fileReadNoSuchFile)))
                return
            }
            onFinish(.success(url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish(.failure(CancellationError()))
        }
    }
}
