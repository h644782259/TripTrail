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

    init(trip: Trip, day selectedDay: TripDay? = nil) {
        let days = selectedDay.map { [$0] } ?? trip.sortedDays
        id = trip.id
        scopeID = selectedDay?.id ?? trip.id
        scopeLabel = selectedDay == nil ? "整段行程" : "单日行程"
        eyebrow = "TRIP PLAN · 行程计划"
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
                        detail: [$0.category.rawValue, $0.address, $0.distanceText]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "),
                        completed: $0.isCompleted
                    )
                }
            )
        }
        coverAssetIdentifier = days
            .flatMap(\.sortedItems)
            .flatMap { $0.media.sorted { $0.sortOrder < $1.sortOrder } }
            .first?
            .localIdentifier
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
                        detail: [$0.category.rawValue, $0.address, $0.note]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "),
                        completed: true
                    )
                }
            )
        }
        coverAssetIdentifier = days
            .flatMap(\.sortedEntries)
            .flatMap(\.sortedMedia)
            .first?
            .localIdentifier
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
            return [ShareScopeOption(id: trip.id, title: "整段行程", subtitle: "\(trip.sortedDays.count) 天 · \(trip.totalCount) 段安排")] +
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
            return days.flatMap(\.sortedEntries).flatMap(\.media).count
        }
    }
}

struct ShareExportView: View {
    @Environment(\.dismiss) private var dismiss
    private let source: ShareExportSource
    @State private var selectedScopeID: UUID
    @State private var coverImage: UIImage?
    @State private var renderedImage: UIImage?
    @State private var fileURL: URL?
    @State private var portableFileURL: URL?
    @State private var includeMedia = false
    @State private var isPreparingPortableFile = false
    @State private var portableMediaCount = 0
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    scopePicker

                    ShareCard(data: data, coverImage: coverImage)
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
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $includeMedia) {
                            Text("照片与视频（\(source.mediaCount(for: selectedScopeID))）")
                                .font(.headline)
                        }
                        if includeMedia {
                            Text("将读取相簿原件，文件可能较大。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .cardSurface()

                    if isPreparingPortableFile {
                        ProgressView(includeMedia ? "正在读取并打包媒体原件…" : "正在生成可收藏文件…")
                            .frame(maxWidth: .infinity)
                    } else if let portableFileURL {
                        ShareLink(
                            item: portableFileURL,
                            subject: Text("来自旅迹的\(data.scopeLabel)"),
                            message: Text("点击文件并选择用“旅迹”打开，即可预览并收藏。")
                        ) {
                            Label("发送可导入的\(data.scopeLabel)", systemImage: "square.and.arrow.up.on.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Text(includeMedia
                             ? "已包含 \(portableMediaCount) 个媒体原件。"
                             : "对方可在旅迹中预览并收藏。")
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
            .task(id: "\(selectedScopeID.uuidString)-\(includeMedia)") { await render() }
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

    @MainActor
    private func render() async {
        renderedImage = nil
        fileURL = nil
        portableFileURL = nil
        portableMediaCount = 0
        isPreparingPortableFile = true
        let currentData = data
        do {
            let safeName = currentData.title.replacingOccurrences(of: "/", with: "-")
            let generatedURL: URL
            if includeMedia {
                let result = try await source.portablePackage(for: currentData.scopeID)
                let namedURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("旅迹收藏-\(safeName)-\(currentData.scopeLabel)-含媒体-\(UUID().uuidString.prefix(6)).triptrail")
                try FileManager.default.copyItem(at: result.url, to: namedURL)
                generatedURL = namedURL
                portableMediaCount = result.mediaCount
            } else {
                let portableData = try source.portableData(for: currentData.scopeID)
                let portableURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("旅迹收藏-\(safeName)-\(currentData.scopeLabel)-\(currentData.scopeID.uuidString.prefix(6)).triptrail")
                try portableData.write(to: portableURL, options: .atomic)
                generatedURL = portableURL
            }
            guard !Task.isCancelled, currentData.scopeID == selectedScopeID else { return }
            portableFileURL = generatedURL
        } catch {
            message = "可收藏文件生成失败：\(error.localizedDescription)"
        }
        isPreparingPortableFile = false
        let loadedCover: UIImage?
        if let identifier = currentData.coverAssetIdentifier {
            loadedCover = await PhotoLibraryService.shareImage(identifier: identifier)
        } else {
            loadedCover = nil
        }
        guard !Task.isCancelled, currentData.scopeID == selectedScopeID else { return }
        coverImage = loadedCover

        guard
            let image = ShareCardImageRenderer.render(data: currentData, coverImage: loadedCover),
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
    static func render(data: ShareCardData, coverImage: UIImage?, scale: CGFloat = 2) -> UIImage? {
        let content = ShareCard(data: data, coverImage: coverImage)
            .frame(width: 360)
            .fixedSize(horizontal: false, vertical: true)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        return renderer.uiImage
    }
}

private struct ShareCard: View {
    let data: ShareCardData
    let coverImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                LinearGradient(
                    colors: [.tripInk.opacity(coverImage == nil ? 1 : 0.48), Color.tripLake.opacity(coverImage == nil ? 1 : 0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(data.eyebrow).font(.caption.bold()).tracking(1.4).foregroundStyle(Color.tripSand)
                        Spacer()
                        Text(data.scopeLabel)
                            .font(.caption2.bold())
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                    Spacer()
                    Text(data.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Label(data.destination.isEmpty ? "目的地待定" : data.destination, systemImage: "mappin.and.ellipse")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.88))
                    Text(data.dateRange).font(.caption).foregroundStyle(.white.opacity(0.72))
                }
                .padding(24)
            }
            .frame(height: coverImage == nil ? 190 : 230)

            VStack(alignment: .leading, spacing: 20) {
                if !data.summary.isEmpty {
                    Text(data.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(data.sections.enumerated()), id: \.element.id) { sectionIndex, section in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 10) {
                            Text("D\(sectionIndex + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.tripLake, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title).font(.headline)
                                Text(section.dateText).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if !section.narrative.isEmpty {
                            Text(section.narrative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if section.items.isEmpty {
                            Text("这一天还没有具体安排")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { itemIndex, item in
                                HStack(alignment: .top, spacing: 11) {
                                    ZStack {
                                        Circle().fill(item.completed ? Color.tripSage : Color.tripLake.opacity(0.15))
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
                                    .frame(width: 26, height: 26)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(item.title).font(.subheadline.bold())
                                            Spacer(minLength: 8)
                                            Text(item.time).font(.caption2).foregroundStyle(.secondary)
                                        }
                                        if !item.detail.isEmpty {
                                            Text(item.detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if sectionIndex < data.sections.count - 1 {
                        Divider()
                    }
                }

                HStack {
                    Text("旅迹 · 把走过的路留下来").font(.caption2.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(Color.tripLake)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(Color(uiColor: .systemBackground))
        }
        .environment(\.colorScheme, .light)
    }
}
