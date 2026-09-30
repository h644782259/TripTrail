import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(EnhancedRecognitionSettings.enabledDefaultsKey)
    private var enhancedRecognitionEnabled = ZhipuAPIKeyStore.hasAPIKey
    @State private var storageUsage = CloudSyncService.shared.cachedStorageUsage()
    @State private var storageUsageUnavailable = false
    @State private var message: String?
    @State private var pendingBackupAction: Int?
    @State private var choosingBackupDestination = false
    @State private var choosingRestoreSource = false
    @State private var uploadingBackup = false
    @State private var showsBackupManager = false
    @State private var downloadedBackup: (url: URL, restoring: Bool)?
    @State private var backupExportRequest: BackupExportRequest?
    @State private var temporaryFiles = TemporaryFileOwner()
    @State private var backupTemporaryURL: URL?
    @State private var backupExportResult: BackupExportResult?
    @State private var isPreparingBackup = false
    @State private var preparedBackupMediaCount = 0
    @State private var skippedBackupMedia: [String] = []
    @State private var confirmsPartialBackup = false
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
    @FocusState private var isZhipuAPIKeyFocused: Bool

    var body: some View {
        List {
            Section { NavigationLink("☁️ 云端数据") { CloudDataView() } }
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
                                TextField(activeProvider.apiKeyLabel, text: activeAPIKeyBinding).clearableText(activeAPIKeyBinding, minimumHeight: 0)
                            } else {
                                SecureField(activeProvider.apiKeyLabel, text: activeAPIKeyBinding).clearableText(activeAPIKeyBinding, minimumHeight: 0)
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
                NavigationLink { RecycleBinView() } label: { Label("回收站", systemImage: "trash") }
                Button { showsBackupManager = true } label: { Label("备份管理", systemImage: "clock.arrow.circlepath") }.disabled(isPreparingBackup)
                Button { importRequest = DocumentImportRequest(kind: .sharedJourney) } label: {
                    Label("导入分享文件", systemImage: "square.and.arrow.down.on.square")
                }
            } header: {
                Text("数据管理")
            }

            Section("数据与隐私") {
                Label("本地始终保留数据副本", systemImage: "internaldrive")
                Label("云端内容和备份为公开共享", systemImage: "cloud")
                Text("仅引用相簿的照片或视频，删除原件后可能无法读取。换机或卸载前，请确认完整备份已保存成功。").font(.footnote).foregroundStyle(.secondary)
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
                LabeledContent("云端数据库", value: storageUsage.map { CloudStorageUsage.formatted($0.database_bytes) } ?? (storageUsageUnavailable ? "暂不可用" : "加载中"))
                LabeledContent("云端对象存储", value: storageUsage.map { CloudStorageUsage.formatted($0.object_bytes) } ?? (storageUsageUnavailable ? "暂不可用" : "加载中"))
                if let usage = storageUsage {
                    Text("统计于 \(usage.measuredAt.formatted(date: .abbreviated, time: .shortened)) · 每日更新")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task {
            do { storageUsage = try await CloudSyncService.shared.storageUsage(); storageUsageUnavailable = false }
            catch { storageUsageUnavailable = true }
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
        .sheet(isPresented: $showsBackupManager, onDismiss: {
            if let action = pendingBackupAction {
                pendingBackupAction = nil
                if action == 2 { importRequest = DocumentImportRequest(kind: .backup) }
                else { uploadingBackup = action == 1; exportBackup() }
            } else { consumeDownloadedBackup() }
        }) {
            CloudBackupManagerView(onExport: { cloud in
                pendingBackupAction = cloud ? 1 : 0; showsBackupManager = false
            }, onImport: { pendingBackupAction = 2; showsBackupManager = false }) { url, restoring in
                downloadedBackup = (url, restoring)
                showsBackupManager = false
            }
        }
        .alert("部分资源无法读取", isPresented: $confirmsPartialBackup) {
            Button("取消", role: .cancel) {
                temporaryFiles.remove(backupTemporaryURL)
                backupTemporaryURL = nil
            }
            Button("跳过并继续导出") {
                if let url = backupTemporaryURL { completePreparedBackup(url) }
            }
        } message: {
            Text("有 \(skippedBackupMedia.count) 个图片或视频可能已删除或无法访问。继续将跳过这些资源，其余内容正常备份。本机记录不会修改。")
        }
        .alert("恢复这份备份？", isPresented: $isConfirmingRestore) {
            Button("取消", role: .cancel) {
                temporaryFiles.remove(pendingRestoreURL)
                pendingRestoreURL = nil
                pendingRestoreSummary = nil
            }
            Button("替换本机数据", role: .destructive, action: restorePendingBackup)
        } message: {
            Text(restoreConfirmationText)
        }
        .alert("收藏这份内容？", isPresented: $isConfirmingSharedJourney) {
            Button("取消", role: .cancel) {
                temporaryFiles.remove(pendingSharedJourneyURL)
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
                defer { try? FileManager.default.removeItem(at: result.url) }
                let filename = "旅迹-完整备份.triptrailbackup"
                let namedURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: namedURL)
                try FileManager.default.moveItem(at: result.url, to: namedURL)
                temporaryFiles.keep(namedURL)
                backupTemporaryURL = namedURL
                skippedBackupMedia = result.skippedMedia
                if result.skippedMedia.isEmpty { completePreparedBackup(namedURL) }
                else { confirmsPartialBackup = true }
            } catch {
                message = "生成备份失败：\(error.localizedDescription)"
            }
            if !uploadingBackup || backupTemporaryURL == nil || confirmsPartialBackup { isPreparingBackup = false }
        }
    }

    private func consumeDownloadedBackup() {
        guard let download = downloadedBackup else { return }
        downloadedBackup = nil
        if download.restoring {
            handleImportedBackup(.success(download.url))
            try? FileManager.default.removeItem(at: download.url)
        } else {
            temporaryFiles.keep(download.url)
            backupTemporaryURL = download.url
            skippedBackupMedia = []
            backupExportRequest = BackupExportRequest(url: download.url)
        }
    }

    private func completePreparedBackup(_ url: URL) {
        guard uploadingBackup else { backupExportRequest = BackupExportRequest(url: url); return }
        isPreparingBackup = true
        Task {
            defer { isPreparingBackup = false; temporaryFiles.remove(url); backupTemporaryURL = nil }
            do {
                try await CloudBackupService.upload(url)
                message = "云端备份已保存为新版本，可在备份管理中导出或恢复。" + (skippedBackupMedia.isEmpty ? "" : "已跳过 \(skippedBackupMedia.count) 个无法读取的资源。")
            } catch { message = "上传失败：\(error.localizedDescription)" }
        }
    }

    private func finishBackupExport() {
        temporaryFiles.remove(backupTemporaryURL)
        backupTemporaryURL = nil
        guard let result = backupExportResult else { return }
        backupExportResult = nil
        switch result {
        case .exported:
            message = "备份文件已导出。" + (skippedBackupMedia.isEmpty ? "" : "已跳过 \(skippedBackupMedia.count) 个无法读取的资源。")
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
                temporaryFiles.keep(copy)
                do { pendingRestoreSummary = try DataBackupService.inspectBackup(at: copy) }
                catch { temporaryFiles.remove(copy); throw error }
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
        guard let url = pendingRestoreURL, !isPreparingBackup else { return }
        isPreparingBackup = true
        Task {
            defer { temporaryFiles.remove(url); isPreparingBackup = false }
            do {
                let summary = try await CloudSyncService.shared.restoreBackup(from: url, into: modelContext)
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
                temporaryFiles.keep(copy)
                do { pendingSharedJourneySummary = try SharedJourneyService.inspect(at: copy) }
                catch { temporaryFiles.remove(copy); throw error }
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
            defer { temporaryFiles.remove(url) }
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

private struct CloudBackupManagerView: View {
    let onExport: (Bool) -> Void
    let onImport: () -> Void
    let onDownload: (URL, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [CloudBackupVersion] = []
    @State private var busy = false
    @State private var message: String?
    @State private var deleting: CloudBackupVersion?
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                Section {
                    Menu {
                        Button("导出本地") { onExport(false) }
                        Button("上传云端") { onExport(true) }.disabled(!CloudSyncService.shared.configured)
                    } label: { Label("导出备份", systemImage: "square.and.arrow.up") }
                    Menu {
                        Button("从本地文件导入", action: onImport)
                        Button("从云端恢复") { withAnimation { proxy.scrollTo("backupVersions", anchor: .top) } }
                            .disabled(!CloudSyncService.shared.configured)
                    } label: { Label("恢复备份", systemImage: "square.and.arrow.down") }
                }.disabled(busy)
                Section("备份版本") {
                    Color.clear.frame(height: 0).id("backupVersions")
                    ForEach(versions) { version in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(version.title).font(.headline)
                            Text(ByteCountFormatter.string(fromByteCount: version.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                            if version.deleting { Text("删除未完成，可再次删除重试").font(.caption) }
                            else if !version.ready { Text("上传未完成，可删除后重新上传").font(.caption) }
                            HStack {
                                Button("导出") { download(version, restoring: false) }.disabled(version.deleting || !version.ready)
                                Button("恢复") { download(version, restoring: true) }.disabled(version.deleting || !version.ready)
                                Spacer()
                                Button("删除", role: .destructive) { deleting = version }
                            }.buttonStyle(.borderless).disabled(busy)
                        }
                    }
                    if versions.isEmpty { Text(busy ? "正在加载…" : "暂无云端备份").foregroundStyle(.secondary) }
                }
            }
            .overlay { if busy { ProgressView().allowsHitTesting(false) } }
            .navigationTitle("备份管理")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .task { await refresh() }
            .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("确定") { message = nil }
            } message: { Text(message ?? "") }
            .confirmationDialog("删除这个云端备份版本？删除后无法恢复，不影响本机数据。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                if let version = deleting {
                    Button("删除备份", role: .destructive) {
                        deleting = nil; busy = true
                        Task {
                            do { try await CloudBackupService.delete(version) }
                            catch { message = error.localizedDescription }
                            await refresh()
                        }
                    }
                }
            }
        }
        }
    }
    private func refresh() async {
        busy = true
        defer { busy = false }
        do { versions = try await CloudBackupService.list() }
        catch { message = "读取备份失败：\(error.localizedDescription)" }
    }
    private func download(_ version: CloudBackupVersion, restoring: Bool) {
        busy = true
        Task {
            defer { busy = false }
            do { onDownload(try await CloudBackupService.download(version), restoring) }
            catch { message = error.localizedDescription }
        }
    }
}
