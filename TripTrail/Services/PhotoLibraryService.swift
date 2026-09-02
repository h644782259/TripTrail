import AVKit
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

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
                                FullSizeAssetImage(identifier: item.identifier)
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
        guard abs(value.translation.width) > abs(value.translation.height) else { return false }
        if currentItem?.kind == .video, value.startLocation.y > size.height * 0.72 {
            return false
        }
        return true
    }
}

private struct FullSizeAssetImage: View {
    let identifier: String
    @State private var image: UIImage?
    @State private var isMissing = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
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

private struct FullSizeAssetVideo: View {
    let identifier: String
    let isActive: Bool

    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
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
        .task(id: identifier) { loadVideo() }
        .onChange(of: isActive) { _, active in
            if active { player?.play() }
            else { player?.pause() }
        }
        .onDisappear { player?.pause() }
    }

    private func loadVideo() {
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
                guard let asset else {
                    failed = true
                    return
                }
                let loadedPlayer = AVPlayer(playerItem: AVPlayerItem(asset: asset))
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

    var body: some View {
        TripNavigationStack {
            Group {
                if let player {
                    VideoPlayer(player: player)
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
        .task { loadVideo() }
    }

    private func loadVideo() {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else {
            failed = true
            return
        }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { asset, _, _ in
            Task { @MainActor in
                if let asset { player = AVPlayer(playerItem: AVPlayerItem(asset: asset)) }
                else { failed = true }
            }
        }
    }
}
