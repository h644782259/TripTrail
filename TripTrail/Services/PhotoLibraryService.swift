import AVKit
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

private enum PhotoLibraryImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    static func key(identifier: String, targetSize: CGSize, contentMode: PHImageContentMode) -> NSString {
        "\(identifier)-\(Int(targetSize.width))x\(Int(targetSize.height))-\(contentMode.rawValue)" as NSString
    }

    static func store(_ image: UIImage, forKey key: NSString) {
        let pixelCost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        shared.setObject(image, forKey: key, cost: pixelCost)
    }
}

struct PickedAsset: Identifiable, Hashable {
    let id: String
    let kind: MediaKind
}

enum FootprintMediaPolicy {
    static let maximumCount = 6

    static func remainingSlots(existingCount: Int, pendingCount: Int = 0) -> Int {
        max(0, maximumCount - existingCount - pendingCount)
    }
}

enum MediaPagingPolicy {
    static func targetIndex(
        currentIndex: Int,
        itemCount: Int,
        translation: CGFloat,
        predictedTranslation: CGFloat,
        pageWidth: CGFloat
    ) -> Int {
        guard itemCount > 1 else { return 0 }
        let threshold = min(max(pageWidth * 0.18, 56), 88)
        let projected = abs(predictedTranslation) > abs(translation)
            ? predictedTranslation
            : translation
        if projected < -threshold {
            return min(currentIndex + 1, itemCount - 1)
        }
        if projected > threshold {
            return max(currentIndex - 1, 0)
        }
        return min(max(currentIndex, 0), itemCount - 1)
    }
}

struct AssetMediaPreviewItem: Identifiable, Hashable {
    var id: String { identifier }
    let identifier: String
    let kind: MediaKind
}

struct AssetMediaPreviewRequest: Identifiable {
    let id = UUID()
    let items: [AssetMediaPreviewItem]
    let initialIdentifier: String

    init(items: [AssetMediaPreviewItem], initialIdentifier: String) {
        var seen = Set<String>()
        self.items = items.filter { seen.insert($0.identifier).inserted }
        self.initialIdentifier = initialIdentifier
    }
}

struct ExportedPhotoResource {
    let fileURL: URL
    let originalFilename: String
    let uniformTypeIdentifier: String
}

@MainActor
enum PhotoLibraryService {
    static func localFile(_ identifier: String) -> URL? {
        guard let url = URL(string: identifier), url.isFileURL else { return nil }
        // Application container paths can change after reinstalling/updating the app.
        if url.deletingLastPathComponent().lastPathComponent == "CloudMedia",
           let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return support.appendingPathComponent("CloudMedia").appendingPathComponent(url.lastPathComponent)
        }
        return url
    }

    static func isLocallyAvailable(_ identifier: String) -> Bool {
        if let file = localFile(identifier) {
            return FileManager.default.isReadableFile(atPath: file.path)
        }
        return PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject != nil
    }

    static func localImage(_ url: URL, maxPixelSize: Int = 2400) -> UIImage? {
        #if targetEnvironment(simulator)
        // Host-generated previews support HEIC variants unavailable in Simulator codecs.
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let preview = caches.appendingPathComponent("CompatibleMedia").appendingPathComponent(url.lastPathComponent + ".jpg")
            if FileManager.default.fileExists(atPath: preview.path), let image = UIImage(contentsOfFile: preview.path) { return image }
        }
        #endif
        let cacheKey = "local:\(url.path):\(maxPixelSize)" as NSString
        if let cached = PhotoLibraryImageCache.shared.object(forKey: cacheKey) { return cached }
        let type = UTType(filenameExtension: url.pathExtension)
        let isVideo = type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true
        if !isVideo {
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                if let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    let image = UIImage(cgImage: decoded)
                    PhotoLibraryImageCache.shared.setObject(image, forKey: cacheKey, cost: decoded.bytesPerRow * decoded.height)
                    return image
                }
                return nil
            }
            // A failed still-image decode must not be retried through the video decoder.
            if type?.conforms(to: .image) == true { return nil }
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        return (try? generator.copyCGImage(at: .zero, actualTime: nil)).map { UIImage(cgImage: $0) }
    }

    static var status: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static func requestReadWriteAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    static var hasReadWriteAccess: Bool {
        status == .authorized || status == .limited
    }

    static func requestReadWriteAccessIfNeeded() async -> PHAuthorizationStatus {
        status == .notDetermined ? await requestReadWriteAccess() : status
    }

    static var permissionGuidance: String {
        switch status {
        case .denied:
            "相簿权限已关闭。请到系统设置中允许“旅迹”访问照片，然后再试。"
        case .restricted:
            "当前设备限制了相簿访问，暂时无法使用这项功能。"
        default:
            "需要允许访问系统相簿才能继续。"
        }
    }

    static func pickedAssets(from items: [PhotosPickerItem]) -> [PickedAsset] {
        items.compactMap { item in
            guard let identifier = item.itemIdentifier else { return nil }
            let kind: MediaKind = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) ? .video : .image
            return PickedAsset(id: identifier, kind: kind)
        }
    }

    static var readableStatusText: String {
        switch status {
        case .authorized: "已允许全部相簿"
        case .limited: "已允许部分相簿"
        case .denied: "相簿权限已拒绝"
        case .restricted: "相簿访问受系统限制"
        case .notDetermined: "尚未请求相簿权限"
        @unknown default: "相簿权限状态未知"
        }
    }

    static func shareImage(identifier: String, targetSize: CGSize = CGSize(width: 1_200, height: 800)) async -> UIImage? {
        if let url = localFile(identifier) { return localImage(url) }
        let authorization = await requestReadWriteAccessIfNeeded()
        guard authorization == .authorized || authorization == .limited else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            var didResume = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded, !didResume else { return }
                didResume = true
                continuation.resume(returning: image)
            }
        }
    }

    static func displayImage(identifier: String, targetSize: CGSize = CGSize(width: 2_000, height: 2_000)) async -> UIImage? {
        if let url = localFile(identifier) { return localImage(url) }
        let authorization = await requestReadWriteAccessIfNeeded()
        guard authorization == .authorized || authorization == .limited else { return nil }
        let cacheKey = PhotoLibraryImageCache.key(
            identifier: identifier,
            targetSize: targetSize,
            contentMode: .aspectFit
        )
        if let cached = PhotoLibraryImageCache.shared.object(forKey: cacheKey) {
            return cached
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            var didResume = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded, !didResume else { return }
                didResume = true
                if let image {
                    PhotoLibraryImageCache.store(image, forKey: cacheKey)
                }
                continuation.resume(returning: image)
            }
        }
    }

    static func exportOriginal(
        identifier: String,
        kind: MediaKind,
        referenceID: UUID,
        to directory: URL
    ) async throws -> ExportedPhotoResource {
        if let source = localFile(identifier) {
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: destination)
            return ExportedPhotoResource(fileURL: destination, originalFilename: source.lastPathComponent,
                uniformTypeIdentifier: UTType(filenameExtension: source.pathExtension)?.identifier ?? UTType.data.identifier)
        }
        let authorization = status == .notDetermined ? await requestReadWriteAccess() : status
        guard authorization == .authorized || authorization == .limited else {
            throw PhotoLibraryError.permissionDenied
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { throw PhotoLibraryError.assetUnavailable }
        let resources = PHAssetResource.assetResources(for: asset)
        let resource: PHAssetResource?
        switch kind {
        case .image:
            resource = resources.first { $0.type == .photo }
                ?? resources.first { $0.type == .fullSizePhoto }
        case .video:
            resource = resources.first { $0.type == .video }
                ?? resources.first { $0.type == .fullSizeVideo }
        }
        guard let resource else { throw PhotoLibraryError.assetUnavailable }
        let fileExtension = URL(fileURLWithPath: resource.originalFilename).pathExtension
        let destination = directory
            .appendingPathComponent(referenceID.uuidString)
            .appendingPathExtension(fileExtension.isEmpty ? (kind == .video ? "mov" : "jpg") : fileExtension)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
        return ExportedPhotoResource(
            fileURL: destination,
            originalFilename: resource.originalFilename,
            uniformTypeIdentifier: resource.uniformTypeIdentifier
        )
    }

    static func importAssetFile(at url: URL, kind: MediaKind) async throws -> String {
        let authorization = await requestReadWriteAccessIfNeeded()
        guard authorization == .authorized || authorization == .limited else {
            throw PhotoLibraryError.permissionDenied
        }
        var createdIdentifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request: PHAssetChangeRequest?
            switch kind {
            case .image:
                request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            case .video:
                request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            createdIdentifier = request?.placeholderForCreatedAsset?.localIdentifier
        }
        guard let createdIdentifier else { throw PhotoLibraryError.importFailed }
        return createdIdentifier
    }
}

enum PhotoLibraryError: LocalizedError {
    case permissionDenied
    case assetUnavailable
    case importFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "没有读取或添加相簿的权限，请在系统设置中允许。"
        case .assetUnavailable:
            "原照片或视频不可用，可能已删除或尚未从 iCloud 下载。"
        case .importFailed:
            "媒体写入系统相簿失败。"
        }
    }
}

struct PermissionAwarePhotosPicker<Label: View>: View {
    @Binding var selection: [PhotosPickerItem]
    let maxSelectionCount: Int
    var usesOrderedSelection = false
    let matching: PHPickerFilter
    @ViewBuilder let label: () -> Label

    @State private var isPresented = false
    @State private var permissionMessage: String?

    var body: some View {
        pickerTrigger
            .alert("需要相簿权限", isPresented: Binding(
                get: { permissionMessage != nil },
                set: { if !$0 { permissionMessage = nil } }
            )) {
                Button("取消", role: .cancel) { permissionMessage = nil }
                if PhotoLibraryService.status == .denied || PhotoLibraryService.status == .restricted {
                    Button("去设置") {
                        permissionMessage = nil
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text(permissionMessage ?? "")
            }
    }

    @ViewBuilder
    private var pickerTrigger: some View {
        if usesOrderedSelection {
            triggerButton
                .photosPicker(
                    isPresented: $isPresented,
                    selection: $selection,
                    maxSelectionCount: maxSelectionCount,
                    selectionBehavior: .ordered,
                    matching: matching,
                    photoLibrary: .shared()
                )
        } else {
            triggerButton
                .photosPicker(
                    isPresented: $isPresented,
                    selection: $selection,
                    maxSelectionCount: maxSelectionCount,
                    matching: matching,
                    photoLibrary: .shared()
                )
        }
    }

    private var triggerButton: some View {
        Button {
            Task { @MainActor in
                let authorization = await PhotoLibraryService.requestReadWriteAccessIfNeeded()
                if authorization == .authorized || authorization == .limited {
                    isPresented = true
                } else {
                    permissionMessage = PhotoLibraryService.permissionGuidance
                }
            }
        } label: {
            label()
        }
    }
}

struct AssetThumbnail: View {
    let identifier: String
    var showsVideoBadge = false
    @State private var image: UIImage?
    @State private var isMissing = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.12))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isMissing {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text("原素材不可用").font(.caption2)
                }
                .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            if showsVideoBadge {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.4))
            }
        }
        .clipped()
        .task(id: identifier) { load() }
    }

    private func load() {
        if let url = PhotoLibraryService.localFile(identifier) {
            image = PhotoLibraryService.localImage(url, maxPixelSize: 480); isMissing = image == nil; return
        }
        let targetSize = CGSize(width: 480, height: 480)
        let cacheKey = PhotoLibraryImageCache.key(
            identifier: identifier,
            targetSize: targetSize,
            contentMode: .aspectFill
        )
        if let cached = PhotoLibraryImageCache.shared.object(forKey: cacheKey) {
            image = cached
            isMissing = false
            return
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else {
            isMissing = true
            return
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { loadedImage, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            guard !degraded else { return }
            if let loadedImage {
                PhotoLibraryImageCache.store(loadedImage, forKey: cacheKey)
            }
            Task { @MainActor in
                image = loadedImage
                isMissing = loadedImage == nil
            }
        }
    }
}

struct AssetMediaViewer: View {
    @Environment(\.dismiss) private var dismiss
    let request: AssetMediaPreviewRequest

    @State private var imageIsZoomed = false
    @State private var currentIndex: Int
    @GestureState private var dragTranslation: CGFloat = 0

    init(request: AssetMediaPreviewRequest) {
        self.request = request
        _currentIndex = State(initialValue: request.items.firstIndex {
            $0.identifier == request.initialIdentifier
        } ?? 0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                let pageWidth = max(proxy.size.width, 1)
                HStack(spacing: 0) {
                    ForEach(Array(request.items.enumerated()), id: \.element.id) { index, item in
                        Group {
                            if item.kind == .video {
                                FullSizeAssetVideo(
                                    identifier: item.identifier,
                                    isActive: currentIndex == index
                                )
                            } else {
                                FullSizeAssetImage(identifier: item.identifier, onZoom: { if currentIndex == index { imageIsZoomed = $0 } })
                            }
                        }
                        .frame(width: pageWidth, height: proxy.size.height)
                    }
                }
                .offset(
                    x: -CGFloat(currentIndex) * pageWidth
                        + resistedTranslation(dragTranslation)
                )
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.88), value: currentIndex)
                .animation(
                    dragTranslation == 0
                        ? .interactiveSpring(response: 0.28, dampingFraction: 0.88)
                        : nil,
                    value: dragTranslation
                )
                .contentShape(Rectangle())
                .clipped()
                .simultaneousGesture(pagingGesture(in: proxy.size))
            }

            VStack {
                HStack {
                    if request.items.count > 1 {
                        Text(pageText)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.48), in: Capsule())
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.48), in: Circle())
                    }
                    .accessibilityLabel("关闭大图")
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                Spacer()
            }
        }
        .statusBarHidden()
    }

    private var pageText: String {
        "\(min(currentIndex + 1, request.items.count)) / \(request.items.count)"
    }

    private var currentItem: AssetMediaPreviewItem? {
        request.items.indices.contains(currentIndex) ? request.items[currentIndex] : nil
    }

    private func resistedTranslation(_ value: CGFloat) -> CGFloat {
        if (currentIndex == 0 && value > 0)
            || (currentIndex == request.items.count - 1 && value < 0) {
            return value * 0.22
        }
        return value
    }

    private func pagingGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, transaction in
                guard shouldHandlePaging(value, in: size) else {
                    state = 0
                    return
                }
                transaction.animation = nil
                state = value.translation.width
            }
            .onEnded { value in
                guard shouldHandlePaging(value, in: size), request.items.count > 1 else { return }
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
                    currentIndex = MediaPagingPolicy.targetIndex(
                        currentIndex: currentIndex,
                        itemCount: request.items.count,
                        translation: value.translation.width,
                        predictedTranslation: value.predictedEndTranslation.width,
                        pageWidth: size.width
                    )
                }
            }
    }

    private func shouldHandlePaging(_ value: DragGesture.Value, in size: CGSize) -> Bool {
        guard !imageIsZoomed, abs(value.translation.width) > abs(value.translation.height) else { return false }
        if currentItem?.kind == .video, value.startLocation.y > size.height * 0.72 {
            return false
        }
        return true
    }
}

private struct FullSizeAssetImage: View {
    let identifier: String
    var onZoom: (Bool) -> Void
    @State private var image: UIImage?
    @State private var isMissing = false

    var body: some View {
        Group {
            if let image {
                ZoomablePreviewImage(image: image, onZoom: onZoom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isMissing {
                ContentUnavailableView(
                    "图片不可用",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("原图可能已从相簿删除，或尚未从 iCloud 下载。")
                )
                .foregroundStyle(.white)
            } else {
                ProgressView("正在读取原图…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .task(id: identifier) { loadImage() }
    }

    private func loadImage() {
        if let url = PhotoLibraryService.localFile(identifier) {
            image = PhotoLibraryService.localImage(url); isMissing = image == nil; return
        }
        image = nil
        isMissing = false
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else {
            isMissing = true
            return
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 2_400, height: 2_400),
            contentMode: .aspectFit,
            options: options
        ) { loadedImage, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            guard !degraded else { return }
            Task { @MainActor in
                image = loadedImage
                isMissing = loadedImage == nil
            }
        }
    }
}

@MainActor
private enum VideoPlaybackAudioSession {
    private static var owners: Set<UUID> = []

    static func activate(_ owner: UUID) {
        guard !owners.contains(owner) else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            owners.insert(owner)
        } catch {
            NSLog("Video audio session activation failed: %@", error.localizedDescription)
        }
    }

    static func deactivate(_ owner: UUID) {
        guard owners.remove(owner) != nil, owners.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private struct FullSizeAssetVideo: View {
    let identifier: String
    let isActive: Bool

    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var audioOwner = UUID()
    @State private var isVisible = false

    var body: some View {
        Group {
            if let player {
                MediaVideoPlayer(player: player)
            } else if failed {
                ContentUnavailableView(
                    "视频不可用",
                    systemImage: "video.slash",
                    description: Text("原视频可能已从相簿删除，或尚未从 iCloud 下载。")
                )
                .foregroundStyle(.white)
            } else {
                ProgressView("正在读取原视频…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .background(.black)
        .task(id: identifier) {
            isVisible = true
            if isActive { VideoPlaybackAudioSession.activate(audioOwner) }
            loadVideo()
        }
        .onChange(of: isActive) { _, active in
            if active && isVisible { VideoPlaybackAudioSession.activate(audioOwner); player?.play() }
            else { player?.pause(); VideoPlaybackAudioSession.deactivate(audioOwner) }
        }
        .onDisappear {
            isVisible = false
            player?.pause()
            VideoPlaybackAudioSession.deactivate(audioOwner)
        }
    }

    private func loadVideo() {
        if let url = PhotoLibraryService.localFile(identifier) {
            player = AVPlayer(url: url); player?.play(); return
        }
        player?.pause()
        player = nil
        failed = false
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else {
            failed = true
            return
        }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { asset, _, _ in
            Task { @MainActor in
                guard isVisible else { return }
                guard let asset else {
                    failed = true
                    return
                }
                let loadedPlayer = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                loadedPlayer.isMuted = false
                loadedPlayer.volume = 1
                player = loadedPlayer
                if isActive { loadedPlayer.play() }
            }
        }
    }
}

struct AssetVideoPlayer: View {
    let identifier: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var audioOwner = UUID()
    @State private var isVisible = false

    var body: some View {
        TripNavigationStack {
            Group {
                if let player {
                    MediaVideoPlayer(player: player)
                        .onAppear { player.play() }
                } else if failed {
                    ContentUnavailableView("视频不可用", systemImage: "video.slash", description: Text("原视频可能已从相簿删除，或尚未从 iCloud 下载。"))
                } else {
                    ProgressView("正在读取原视频…")
                }
            }
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task {
            isVisible = true
            VideoPlaybackAudioSession.activate(audioOwner)
            loadVideo()
        }
        .onDisappear {
            isVisible = false
            player?.pause()
            VideoPlaybackAudioSession.deactivate(audioOwner)
        }
    }

    private func loadVideo() {
        if let url = PhotoLibraryService.localFile(identifier) {
            player = AVPlayer(url: url); player?.play(); return
        }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else {
            failed = true
            return
        }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { asset, _, _ in
            Task { @MainActor in
                guard isVisible else { return }
                if let asset {
                    let loadedPlayer = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                    loadedPlayer.isMuted = false
                    loadedPlayer.volume = 1
                    player = loadedPlayer
                }
                else { failed = true }
            }
        }
    }
}

private struct ZoomablePreviewImage: UIViewRepresentable {
    let image: UIImage
    let onZoom: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onZoom: onZoom) }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = PreviewZoomScrollView()
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 5
        scroll.showsHorizontalScrollIndicator = false; scroll.showsVerticalScrollIndicator = false
        scroll.delegate = context.coordinator
        let imageView = context.coordinator.imageView
        imageView.contentMode = .scaleAspectFit; imageView.image = image
        scroll.addSubview(imageView)
        scroll.zoomImageView = imageView
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2; scroll.addGestureRecognizer(tap)
        return scroll
    }
    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.onZoom = onZoom
        if scroll.zoomScale == 1 {
            context.coordinator.imageView.frame = scroll.bounds
            scroll.contentSize = scroll.bounds.size
        }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        var onZoom: (Bool) -> Void
        init(onZoom: @escaping (Bool) -> Void) { self.onZoom = onZoom }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { onZoom(scrollView.zoomScale > 1.01) }
        @objc func doubleTap(_ tap: UITapGestureRecognizer) {
            guard let scroll = tap.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 { scroll.setZoomScale(1, animated: true) }
            else {
                let point = tap.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}

private final class PreviewZoomScrollView: UIScrollView {
    weak var zoomImageView: UIImageView?
    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1, let zoomImageView {
            zoomImageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }
}

private struct MediaVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer?
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsVideoFrameAnalysis = false
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}
