import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let tripTrailJourney = UTType(
        exportedAs: "com.personal.triptrail.shared-journey",
        conformingTo: .data
    )
    static let tripTrailBackup = UTType(
        exportedAs: "com.personal.triptrail.backup",
        conformingTo: .data
    )
}

struct ShareCardItem: Identifiable {
    let id: UUID
    let time: String
    let title: String
    let detail: String
    let completed: Bool
    let statusText: String
    let photoAssetIdentifiers: [String]
}

struct ShareCardSection: Identifiable {
    let id: UUID
    let title: String
    let dateText: String
    let narrative: String
    let items: [ShareCardItem]
}

struct ShareCardData {
    let id: UUID
    let scopeID: UUID
    let scopeLabel: String
    let eyebrow: String
    let title: String
    let destination: String
    let dateRange: String
    let summary: String
    let sections: [ShareCardSection]
    let coverAssetIdentifier: String?
    let coverZoom: Double
    let coverOffsetX: Double
    let coverOffsetY: Double

    init(trip: Trip, day selectedDay: TripDay? = nil) {
        let days = selectedDay.map { [$0] } ?? trip.sortedDays
        id = trip.id
        scopeID = selectedDay?.id ?? trip.id
        scopeLabel = selectedDay == nil ? "整段旅程" : "单日旅程"
        eyebrow = "TRIP PLAN · 旅程计划"
        title = trip.title
        destination = trip.destination
        dateRange = selectedDay?.date.chineseDateText
            ?? "\(trip.startDate.chineseDateText) — \(trip.endDate.chineseDateText)"
        if let selectedDay {
            summary = selectedDay.note.isEmpty ? "\(selectedDay.items.count) 段当天安排" : selectedDay.note
        } else {
            summary = trip.note.isEmpty ? "\(trip.sortedDays.count) 天 · \(trip.totalCount) 段安排 · \(trip.completedCount) 段已完成" : trip.note
        }
        sections = days.enumerated().map { index, day in
            ShareCardSection(
                id: day.id,
                title: day.title.isEmpty ? "第 \(index + 1) 天" : day.title,
                dateText: day.date.formatted(.dateTime.month().day().weekday(.wide)),
                narrative: selectedDay == nil ? day.note : "",
                items: day.sortedItems.map {
                    ShareCardItem(
                        id: $0.id,
                        time: "\($0.startTime.timeText)–\($0.endTime.timeText)",
                        title: $0.title,
                        detail: [$0.locationSummary, $0.category.rawValue, $0.distanceText, $0.note]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "),
                        completed: $0.executionStatus == .completed,
                        statusText: $0.executionStatus.rawValue,
                        photoAssetIdentifiers: $0.media
                            .sorted { $0.sortOrder < $1.sortOrder }
                            .filter { $0.kind == .image }
                            .map(\.localIdentifier)
                    )
                }
            )
        }
        coverAssetIdentifier = days
            .flatMap(\.sortedItems)
            .flatMap { $0.media.sorted { $0.sortOrder < $1.sortOrder } }
            .first { $0.kind == .image }?
            .localIdentifier
        coverZoom = 1
        coverOffsetX = 0
        coverOffsetY = 0
    }

    init(story: TravelStory, day selectedDay: StoryDay? = nil) {
        let days = selectedDay.map { [$0] } ?? story.sortedDays
        id = story.id
        scopeID = selectedDay?.id ?? story.id
        scopeLabel = selectedDay == nil ? "整段足迹" : "单日足迹"
        eyebrow = "TRAVEL MEMORY · 旅行足迹"
        title = story.title
        destination = story.destination
        dateRange = selectedDay?.date.chineseDateText
            ?? "\(story.startDate.chineseDateText) — \(story.endDate.chineseDateText)"
        if let selectedDay {
            summary = selectedDay.note.isEmpty ? "\(selectedDay.entries.count) 个当天片段" : selectedDay.note
        } else {
            summary = story.summary.isEmpty ? "\(story.sortedDays.count) 天 · \(story.sortedEntries.count) 个旅行片段" : story.summary
        }
        sections = days.enumerated().map { index, day in
            ShareCardSection(
                id: day.id,
                title: day.title.isEmpty ? "第 \(index + 1) 天" : day.title,
                dateText: day.date.formatted(.dateTime.month().day().weekday(.wide)),
                narrative: selectedDay == nil
                    ? [day.note, day.details].filter { !$0.isEmpty }.joined(separator: "\n")
                    : day.details,
                items: day.sortedEntries.map {
                    ShareCardItem(
                        id: $0.id,
                        time: $0.timeLabel,
                        title: $0.title,
                        detail: $0.note,
                        completed: true,
                        statusText: "",
                        photoAssetIdentifiers: $0.sortedMedia
                            .filter { $0.kind == .image }
                            .map(\.localIdentifier)
                    )
                }
            )
        }
        let fallbackCoverIdentifier = days
            .flatMap(\.sortedEntries)
            .flatMap(\.sortedMedia)
            .first { $0.kind == .image }?
            .localIdentifier
        coverAssetIdentifier = story.coverMedia?.localIdentifier ?? fallbackCoverIdentifier
        coverZoom = story.coverMedia == nil ? 1 : story.coverZoom
        coverOffsetX = story.coverMedia == nil ? 0 : story.coverOffsetX
        coverOffsetY = story.coverMedia == nil ? 0 : story.coverOffsetY
    }

    var photoAssetIdentifiers: [String] {
        var seen = Set<String>()
        return sections
            .flatMap(\.items)
            .flatMap(\.photoAssetIdentifiers)
            .filter { seen.insert($0).inserted }
    }
}

private struct ShareScopeOption: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
}

private enum ShareExportSource {
    case trip(Trip)
    case story(TravelStory)

    var options: [ShareScopeOption] {
        switch self {
        case .trip(let trip):
            return [ShareScopeOption(id: trip.id, title: "整段旅程", subtitle: "\(trip.sortedDays.count) 天 · \(trip.totalCount) 段安排")] +
                trip.sortedDays.enumerated().map { index, day in
                    ShareScopeOption(
                        id: day.id,
                        title: day.title.isEmpty ? "第 \(index + 1) 天" : day.title,
                        subtitle: "\(day.date.compactDayText) · \(day.items.count) 段安排"
                    )
                }
        case .story(let story):
            return [ShareScopeOption(id: story.id, title: "整段足迹", subtitle: "\(story.sortedDays.count) 天 · \(story.sortedEntries.count) 个片段")] +
                story.sortedDays.enumerated().map { index, day in
                    ShareScopeOption(
                        id: day.id,
                        title: day.title.isEmpty ? "第 \(index + 1) 天" : day.title,
                        subtitle: "\(day.date.compactDayText) · \(day.entries.count) 个片段"
                    )
                }
        }
    }

    func data(for scopeID: UUID) -> ShareCardData {
        switch self {
        case .trip(let trip):
            ShareCardData(trip: trip, day: trip.sortedDays.first { $0.id == scopeID })
        case .story(let story):
            ShareCardData(story: story, day: story.sortedDays.first { $0.id == scopeID })
        }
    }

    @MainActor
    func portableData(for scopeID: UUID) throws -> Data {
        switch self {
        case .trip(let trip):
            return try SharedJourneyService.makeShareData(
                trip: trip,
                selectedDay: trip.sortedDays.first { $0.id == scopeID }
            )
        case .story(let story):
            return try SharedJourneyService.makeShareData(
                story: story,
                selectedDay: story.sortedDays.first { $0.id == scopeID }
            )
        }
    }

    @MainActor
    func portablePackage(for scopeID: UUID) async throws -> PortablePackageExportResult {
        switch self {
        case .trip(let trip):
            return try await SharedJourneyService.makeSharePackage(
                trip: trip,
                selectedDay: trip.sortedDays.first { $0.id == scopeID }
            )
        case .story(let story):
            return try await SharedJourneyService.makeSharePackage(
                story: story,
                selectedDay: story.sortedDays.first { $0.id == scopeID }
            )
        }
    }

    func mediaCount(for scopeID: UUID) -> Int {
        switch self {
        case .trip(let trip):
            let days = trip.sortedDays.first { $0.id == scopeID }.map { [$0] } ?? trip.sortedDays
            return days.flatMap(\.sortedItems).flatMap(\.media).count
        case .story(let story):
            let days = story.sortedDays.first { $0.id == scopeID }.map { [$0] } ?? story.sortedDays
            return days.flatMap(\.sortedEntries).flatMap(\.media).count + (story.coverMedia == nil ? 0 : 1)
        }
    }
}

struct ShareExportView: View {
    @Environment(\.dismiss) private var dismiss
    private let source: ShareExportSource
    @State private var selectedScopeID: UUID
    @State private var coverImage: UIImage?
    @State private var photoImages: [String: UIImage] = [:]
    @State private var renderedImage: UIImage?
    @State private var fileURL: URL?
    @State private var isPreparingPortableFile = false
    @State private var showsPortableOptions = false
    @State private var portableShareItem: PortableShareItem?
    @State private var message: String?

    init(trip: Trip, initialScopeID: UUID? = nil) {
        source = .trip(trip)
        _selectedScopeID = State(initialValue: initialScopeID ?? trip.id)
    }

    init(story: TravelStory, initialScopeID: UUID? = nil) {
        source = .story(story)
        _selectedScopeID = State(initialValue: initialScopeID ?? story.id)
    }

    private var data: ShareCardData { source.data(for: selectedScopeID) }

    var body: some View {
        TripNavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    scopePicker

                    ShareCard(data: data, coverImage: coverImage, photoImages: photoImages)
                        .frame(width: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.16), radius: 20, y: 10)

                    if let fileURL, let renderedImage {
                        ShareLink(item: fileURL, preview: SharePreview(data.title, image: Image(uiImage: renderedImage))) {
                            Label("分享精美长图", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        ProgressView("正在生成分享长图…")
                    }
                    if isPreparingPortableFile {
                        ProgressView("正在生成可导入文件…")
                            .frame(maxWidth: .infinity)
                    } else {
                        Button {
                            showsPortableOptions = true
                        } label: {
                            Label("发送可导入的\(data.scopeLabel)", systemImage: "square.and.arrow.up.on.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Text("点击后可选择是否包含照片与视频。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(Color.tripCanvas)
            .navigationTitle("分享预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task(id: selectedScopeID) { await renderLongImage() }
            .confirmationDialog("是否包含照片与视频？", isPresented: $showsPortableOptions, titleVisibility: .visible) {
                let mediaCount = source.mediaCount(for: selectedScopeID)
                Button("包含照片与视频（\(mediaCount)）") {
                    preparePortableFile(includeMedia: true)
                }
                .disabled(mediaCount == 0)
                Button("不包含，文件更小") {
                    preparePortableFile(includeMedia: false)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("包含媒体会保留完整内容，但文件更大，并需要读取相簿原件。")
            }
            .sheet(item: $portableShareItem) { item in
                SystemShareSheet(items: [item.url])
            }
            .alert("分享提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("选择分享范围", systemImage: "rectangle.stack")
                .font(.headline)
            Picker("分享范围", selection: $selectedScopeID) {
                ForEach(source.options) { option in
                    Text("\(option.title) · \(option.subtitle)").tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardSurface()
    }

    private func preparePortableFile(includeMedia: Bool) {
        let currentData = data
        isPreparingPortableFile = true
        Task { @MainActor in
            defer { isPreparingPortableFile = false }
            do {
                let safeName = currentData.title.replacingOccurrences(of: "/", with: "-")
                let generatedURL: URL
                if includeMedia {
                    let result = try await source.portablePackage(for: currentData.scopeID)
                    let namedURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("旅迹收藏-\(safeName)-\(currentData.scopeLabel)-含媒体-\(UUID().uuidString.prefix(6)).triptrail")
                    try FileManager.default.copyItem(at: result.url, to: namedURL)
                    generatedURL = namedURL
                } else {
                    let portableData = try source.portableData(for: currentData.scopeID)
                    let portableURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("旅迹收藏-\(safeName)-\(currentData.scopeLabel)-\(currentData.scopeID.uuidString.prefix(6)).triptrail")
                    try portableData.write(to: portableURL, options: .atomic)
                    generatedURL = portableURL
                }
                guard currentData.scopeID == selectedScopeID else { return }
                portableShareItem = PortableShareItem(url: generatedURL)
            } catch {
                message = "可导入文件生成失败：\(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func renderLongImage() async {
        renderedImage = nil
        fileURL = nil
        coverImage = nil
        photoImages = [:]
        let currentData = data

        var loadedPhotos: [String: UIImage] = [:]
        for identifier in currentData.photoAssetIdentifiers {
            guard !Task.isCancelled else { return }
            if let image = await PhotoLibraryService.shareImage(
                identifier: identifier,
                targetSize: CGSize(width: 600, height: 600)
            ) {
                loadedPhotos[identifier] = image
            }
        }

        let loadedCover: UIImage?
        if let identifier = currentData.coverAssetIdentifier {
            loadedCover = await PhotoLibraryService.shareImage(identifier: identifier)
        } else {
            loadedCover = nil
        }
        guard !Task.isCancelled, currentData.scopeID == selectedScopeID else { return }
        coverImage = loadedCover
        photoImages = loadedPhotos

        guard
            let image = ShareCardImageRenderer.render(
                data: currentData,
                coverImage: loadedCover,
                photoImages: loadedPhotos
            ),
            let png = image.pngData()
        else {
            message = "分享图生成失败，请稍后重试。"
            return
        }
        let safeName = currentData.title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("旅迹-\(safeName)-\(currentData.scopeLabel)-\(currentData.scopeID.uuidString.prefix(6)).png")
        do {
            try png.write(to: url, options: .atomic)
            renderedImage = image
            fileURL = url
        } catch {
            message = "分享文件保存失败：\(error.localizedDescription)"
        }
    }

}

@MainActor
enum ShareCardImageRenderer {
    static func render(
        data: ShareCardData,
        coverImage: UIImage?,
        photoImages: [String: UIImage] = [:],
        scale: CGFloat = 2
    ) -> UIImage? {
        let content = ShareCard(data: data, coverImage: coverImage, photoImages: photoImages)
            .frame(width: 360)
            .fixedSize(horizontal: false, vertical: true)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        return renderer.uiImage
    }
}

private struct PortableShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ShareCard: View {
    let data: ShareCardData
    let coverImage: UIImage?
    let photoImages: [String: UIImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [.tripInk, Color.tripLake],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if let coverImage {
                    ShareCoverImage(
                        image: coverImage,
                        zoom: data.coverZoom,
                        offsetX: data.coverOffsetX,
                        offsetY: data.coverOffsetY
                    )
                } else {
                    ShareCoverDecoration()
                }
                LinearGradient(
                    colors: [.black.opacity(0.08), .clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(data.eyebrow)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.35)
                        Spacer()
                        Text(data.scopeLabel)
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text(data.title)
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Label(data.destination.isEmpty ? "目的地待定" : data.destination, systemImage: "mappin.and.ellipse")
                        Text("·")
                        Text(data.dateRange)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.88))
                }
                .padding(22)
            }
            .frame(height: 252)
            .clipped()

            VStack(alignment: .leading, spacing: 18) {
                if !data.summary.isEmpty {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "quote.opening")
                            .font(.headline)
                            .foregroundStyle(Color.tripLake)
                        Text(data.summary)
                            .font(.subheadline)
                            .foregroundStyle(Color.tripInk.opacity(0.78))
                            .lineSpacing(3)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(15)
                    .background(Color.shareSummary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.tripLake.opacity(0.24), lineWidth: 1)
                    }
                }

                ForEach(Array(data.sections.enumerated()), id: \.element.id) { sectionIndex, section in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 11) {
                            Text("D\(sectionIndex + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.tripLake, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                    .font(.headline.bold())
                                    .foregroundStyle(Color.tripInk)
                                Text(section.dateText)
                                    .font(.caption)
                                    .foregroundStyle(Color.tripInk.opacity(0.62))
                            }
                            Spacer()
                            Text("\(section.items.count) 个片段")
                                .font(.caption2.bold())
                                .foregroundStyle(Color.tripLake)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.shareTimeBadge, in: Capsule())
                        }
                        if !section.narrative.isEmpty {
                            Text(section.narrative)
                                .font(.caption)
                                .foregroundStyle(Color.tripInk.opacity(0.68))
                                .lineSpacing(2)
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if section.items.isEmpty {
                            Text("这一天还没有具体内容")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color.shareItemTop, in: RoundedRectangle(cornerRadius: 14))
                        } else {
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { itemIndex, item in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .center, spacing: 9) {
                                        ZStack {
                                            Circle().fill(item.completed ? Color.tripSage : Color.tripLake.opacity(0.13))
                                            if item.completed {
                                                Image(systemName: "checkmark")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.white)
                                            } else {
                                                Text("\(itemIndex + 1)")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(Color.tripLake)
                                            }
                                        }
                                        .frame(width: 25, height: 25)
                                        Text(item.title)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(Color.tripInk)
                                            .lineLimit(2)
                                        Spacer(minLength: 6)
                                        if !item.time.isEmpty {
                                            Text(item.time)
                                                .font(.caption2.bold())
                                                .foregroundStyle(Color.tripLake)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 5)
                                                .background(Color.shareTimeBadge, in: Capsule())
                                        }
                                    }
                                    if !item.detail.isEmpty {
                                        Text(item.detail)
                                            .font(.caption)
                                            .foregroundStyle(Color.tripInk.opacity(0.66))
                                            .lineSpacing(2)
                                            .lineLimit(4)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    SharePhotoGrid(
                                        identifiers: item.photoAssetIdentifiers,
                                        images: photoImages
                                    )
                                }
                                .padding(13)
                                .background(
                                    LinearGradient(
                                        colors: [Color.shareItemTop, Color.shareItemBottom],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.tripLake.opacity(0.18), lineWidth: 1)
                                }
                                .shadow(color: Color.tripInk.opacity(0.075), radius: 8, y: 4)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.shareDayPanel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.tripLake.opacity(0.20), lineWidth: 1)
                    }
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.tripLake.opacity(0.58))
                            .frame(width: 3)
                            .padding(.vertical, 20)
                            .padding(.leading, 1)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("旅迹")
                            .font(.caption.bold())
                            .foregroundStyle(Color.tripInk)
                        Text("把走过的路留下来")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.title3)
                        .foregroundStyle(Color.tripLake)
                }
                .padding(.top, 6)
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [Color.sharePaperTop, Color.sharePaperBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .environment(\.colorScheme, .light)
    }
}

private struct ShareCoverImage: View {
    let image: UIImage
    let zoom: Double
    let offsetX: Double
    let offsetY: Double

    var body: some View {
        GeometryReader { proxy in
            let imageSize = image.size
            let cropSize = proxy.size
            let fillScale = max(cropSize.width / max(imageSize.width, 1), cropSize.height / max(imageSize.height, 1))
            let baseSize = CGSize(width: imageSize.width * fillScale, height: imageSize.height * fillScale)
            let safeZoom = CGFloat(max(1, min(4, zoom)))
            let maximumOffset = CGSize(
                width: max(0, (baseSize.width * safeZoom - cropSize.width) / 2),
                height: max(0, (baseSize.height * safeZoom - cropSize.height) / 2)
            )
            Image(uiImage: image)
                .resizable()
                .frame(width: baseSize.width, height: baseSize.height)
                .scaleEffect(safeZoom)
                .offset(
                    x: maximumOffset.width * CGFloat(max(-1, min(1, offsetX))),
                    y: maximumOffset.height * CGFloat(max(-1, min(1, offsetY)))
                )
                .frame(width: cropSize.width, height: cropSize.height)
                .clipped()
        }
    }
}

private struct ShareCoverDecoration: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 210, height: 210)
                    .offset(x: proxy.size.width * 0.33, y: -70)
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 26)
                    .frame(width: 170, height: 170)
                    .offset(x: -proxy.size.width * 0.38, y: 95)
                Image(systemName: "map.fill")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.white.opacity(0.08))
                    .offset(x: proxy.size.width * 0.28, y: 70)
            }
        }
    }
}

private struct SharePhotoGrid: View {
    let identifiers: [String]
    let images: [String: UIImage]

    private var availableIdentifiers: [String] {
        identifiers.filter { images[$0] != nil }
    }

    private var displayedIdentifiers: [String] {
        Array(availableIdentifiers.prefix(4))
    }

    private var columns: [GridItem] {
        let count = displayedIdentifiers.count == 1 ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 5), count: count)
    }

    var body: some View {
        if !availableIdentifiers.isEmpty {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(displayedIdentifiers.enumerated()), id: \.element) { index, identifier in
                    if let image = images[identifier] {
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .aspectRatio(displayedIdentifiers.count == 1 ? 1.6 : 1.15, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .clipped()
                            if index == 3, availableIdentifiers.count > displayedIdentifiers.count {
                                Color.black.opacity(0.42)
                                Text("+\(availableIdentifiers.count - displayedIdentifiers.count)")
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color.tripSand.opacity(0.22), lineWidth: 1)
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
    }
}

private extension Color {
    static let sharePaperTop = Color(red: 0.975, green: 0.961, blue: 0.915)
    static let sharePaperBottom = Color(red: 0.950, green: 0.932, blue: 0.873)
    static let shareSummary = Color(red: 0.845, green: 0.902, blue: 0.858)
    static let shareDayPanel = Color(red: 0.900, green: 0.922, blue: 0.885)
    static let shareItemTop = Color(red: 0.986, green: 0.974, blue: 0.936)
    static let shareItemBottom = Color(red: 0.965, green: 0.952, blue: 0.910)
    static let shareTimeBadge = Color(red: 0.820, green: 0.895, blue: 0.880)
}
