import Photos
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var photoStatus = PhotoLibraryService.status
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

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "photo.stack.fill")
                        .font(.title2).foregroundStyle(Color.tripLake)
                        .frame(width: 42, height: 42)
                        .background(Color.tripLake.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("系统相簿").font(.headline)
                        Text(photoStatusText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(photoButtonTitle) { handlePhotoPermission() }.font(.subheadline.bold())
                }
            } header: { Text("权限") } footer: {
                Text("平时仅保存相簿索引；完整备份或带媒体分享时才读取原件。")
            }

            Section("开始体验") {
                Button { addSampleTrip() } label: { Label("添加杭州示例旅程", systemImage: "wand.and.stars") }
            }

            Section {
                Button(action: exportBackup) {
                    if isPreparingBackup {
                        Label("正在读取并打包媒体…", systemImage: "hourglass")
                    } else {
                        Label("导出完整备份", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isPreparingBackup)
                Button { importRequest = DocumentImportRequest(kind: .backup) } label: {
                    Label("从备份恢复", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("数据备份与换机")
            } footer: {
                Text("完整备份包含照片和视频；恢复会替换本机旅迹数据。")
            }

            Section {
                Button { importRequest = DocumentImportRequest(kind: .sharedJourney) } label: {
                    Label("收藏别人分享的旅程或足迹", systemImage: "square.and.arrow.down.on.square")
                }
            } header: {
                Text("接收分享")
            } footer: {
                Text("导入后保存为独立副本。")
            }

            Section("数据与隐私") {
                Label("旅行数据仅保存在本机", systemImage: "lock.shield")
                Label("删除相簿原图后，旅迹图片会失效", systemImage: "exclamationmark.triangle")
            }

            Section("关于") {
                LabeledContent("App", value: "旅迹")
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
                LabeledContent("版本", value: "0.1.0 MVP")
                LabeledContent("系统要求", value: "iOS 17 或更高")
            }
        }
        .navigationTitle("我的")
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

    private var photoStatusText: String {
        switch photoStatus {
        case .authorized: "已允许读取与添加"
        case .limited: "仅可访问已选择的照片"
        case .denied, .restricted: "未允许，请到系统设置修改"
        case .notDetermined: "尚未请求"
        @unknown default: "状态未知"
        }
    }

    private var photoButtonTitle: String {
        switch photoStatus {
        case .notDetermined: "允许"
        case .denied, .restricted: "去设置"
        default: "管理"
        }
    }

    private func handlePhotoPermission() {
        if photoStatus == .notDetermined {
            Task { photoStatus = await PhotoLibraryService.requestReadWriteAccess() }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
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
        return "备份包含\(summary.restoreDescription)。恢复后将替换本机当前的所有旅程和足迹，此操作不可撤销。"
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
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let trip = Trip(title: "西湖慢游三日", destination: "杭州", startDate: start, endDate: calendar.date(byAdding: .day, value: 2, to: start)!, note: "沿着湖边慢慢走，给好吃的和晚霞留出时间。")
        modelContext.insert(trip)
        let samples: [[(String, PlaceCategory, String)]] = [
            [("断桥残雪", .attraction, "从白堤东端开始散步，早晨光线更柔和。"), ("孤山公园", .attraction, "沿湖慢慢走，顺路看看荷花与林间小路。")],
            [("灵隐寺", .attraction, "建议早点到达，避开午后人流。"), ("龙井村", .restaurant, "找一家茶室休息，尝尝当地家常菜。")],
            [("九溪烟树", .attraction, "穿舒适的鞋，沿溪流慢慢走到林间。")]
        ]
        for dayIndex in samples.indices {
            let date = calendar.date(byAdding: .day, value: dayIndex, to: start)!
            let day = TripDay(date: date, title: ["湖畔初见", "山寺与茶", "九溪收尾"][dayIndex], sortOrder: dayIndex, trip: trip)
            trip.days.append(day)
            for (itemIndex, sample) in samples[dayIndex].enumerated() {
                let time = calendar.date(bySettingHour: 9 + itemIndex * 4, minute: 0, second: 0, of: date)!
                let item = ItineraryItem(title: sample.0, category: sample.1, startTime: time, endTime: calendar.date(byAdding: .hour, value: 2, to: time)!, sortOrder: itemIndex)
                item.address = sample.2
                item.distanceText = itemIndex == 0 ? "从当前位置出发" : "约 4.5 km · 20 分钟"
                item.note = "到达后可以补充照片、视频和当时的感受。"
                item.day = day
                day.items.append(item)
            }
        }
        message = "示例旅程已添加，可从“旅程”页开始体验。"
    }
}

private struct CreatorRewardView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
