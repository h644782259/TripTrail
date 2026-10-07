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

enum ShareField: String, CaseIterable, Identifiable {
    case title = "安排标题", time = "时间", location = "地点", category = "类型"
    case memory = "回忆", supplement = "补充说明", cost = "花费", media = "照片与视频"
    var id: String { rawValue }
    static let required: Set<ShareField> = [.title, .location, .category]
    static var selectable: [ShareField] { allCases.filter { !required.contains($0) } }
}

struct ShareCardItem: Identifiable {
    let id: UUID
    let time: String
    let title: String
    let detail: String
    let completed: Bool
    var category: PlaceCategory = .other
    var symbol: String = "camera.fill"
    let statusText: String
    var photoAssetIdentifiers: [String]
}

struct ShareCardSection: Identifiable {
    let id: UUID
    let title: String
    let dateText: String
    let narrative: String
    var items: [ShareCardItem]
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
    var sections: [ShareCardSection]
    var coverAssetIdentifier: String?
    let coverZoom: Double
    let coverOffsetX: Double
    let coverOffsetY: Double

    init(trip: Trip, day selectedDay: TripDay? = nil, selectedItemIDs: Set<UUID>? = nil, fields: Set<ShareField> = Set(ShareField.allCases)) {
        let days = (selectedDay.map { [$0] } ?? trip.sortedDays).filter { day in selectedItemIDs == nil || day.sortedItems.contains { selectedItemIDs!.contains($0.id) } }
        id = trip.id
        scopeID = selectedDay?.id ?? trip.id
        scopeLabel = selectedItemIDs.map { $0.count == trip.totalCount ? "整段旅程" : "所选旅程安排" } ?? (selectedDay == nil ? "整段旅程" : "单日旅程")
        eyebrow = "TRIP PLAN · 旅程计划"
        title = trip.title
        destination = trip.destination
        dateRange = selectedDay?.date.chineseDateText
            ?? "\(trip.startDate.chineseDateText) — \(trip.endDate.chineseDateText)"
        if let selectedDay {
            summary = fields.contains(.supplement) ? trip.note : ""
        } else {
            summary = fields.contains(.supplement) ? trip.note : ""
        }
        sections = days.enumerated().map { index, day in
            ShareCardSection(
                id: day.id,
                title: day.title.isEmpty ? "第 \(index + 1) 天" : day.title,
                dateText: day.date.formatted(.dateTime.month().day().weekday(.wide)),
                narrative: fields.contains(.supplement) ? day.note : "",
                items: day.sortedItems.filter { selectedItemIDs == nil || selectedItemIDs!.contains($0.id) }.map {
                    ShareCardItem(
                        id: $0.id,
                        time: fields.contains(.time) && !$0.timeRangeText.isEmpty ? "🕒 \($0.timeRangeText)" : "",
                        title: fields.contains(.title) ? $0.title : "",
                        detail: [
                            [fields.contains(.location) && !$0.locationSummary.isEmpty ? "📍 \($0.locationSummary)" : "", fields.contains(.cost) && $0.cost != 0 ? "💰 ¥\($0.cost)" : ""].filter { !$0.isEmpty }.joined(separator: " · "),
                            fields.contains(.memory) && !$0.journalNote.isEmpty ? "💭 \($0.journalNote)" : "",
                            fields.contains(.supplement) && !$0.note.isEmpty ? "📝 \($0.note)" : ""
                        ].filter { !$0.isEmpty }.joined(separator: "\n"),
                        completed: $0.executionStatus == .completed,
                        category: fields.contains(.category) ? $0.category : .other,
                        symbol: fields.contains(.category) ? $0.arrangementSymbol : "circle.fill",
                        statusText: $0.executionStatus.rawValue,
                        photoAssetIdentifiers: fields.contains(.media) ? $0.media
                            .sorted { $0.sortOrder < $1.sortOrder }
                            .filter { $0.kind == .image }
                            .map(\.localIdentifier) : []
                    )
                }
            )
        }
        coverAssetIdentifier = fields.contains(.media) ? days
            .flatMap(\.sortedItems)
            .filter { selectedItemIDs == nil || selectedItemIDs!.contains($0.id) }
            .flatMap { $0.media.sorted(by: MediaReference.precedes) }
            .first { $0.kind == .image }?
            .localIdentifier : nil
        coverZoom = 1
        coverOffsetX = 0
        coverOffsetY = 0
    }

    init(story: TravelStory, day selectedDay: StoryDay? = nil, selectedItemIDs: Set<UUID>? = nil, fields: Set<ShareField> = Set(ShareField.allCases)) {
        let days = (selectedDay.map { [$0] } ?? story.sortedDays).filter { day in selectedItemIDs == nil || day.sortedEntries.contains { selectedItemIDs!.contains($0.id) } }
        id = story.id
        scopeID = selectedDay?.id ?? story.id
        scopeLabel = selectedItemIDs.map { $0.count == story.sortedEntries.count ? "整段足迹" : "所选足迹安排" } ?? (selectedDay == nil ? "整段足迹" : "单日足迹")
        eyebrow = "TRAVEL MEMORY · 旅行足迹"
        title = story.title
        destination = story.destination
        dateRange = selectedDay?.date.chineseDateText
            ?? "\(story.startDate.chineseDateText) — \(story.endDate.chineseDateText)"
        if let selectedDay {
            summary = fields.contains(.memory) ? story.summary : ""
        } else {
            summary = fields.contains(.memory) ? story.summary : ""
        }
        sections = days.enumerated().map { index, day in
            ShareCardSection(
                id: day.id,
                title: day.title.isEmpty ? "第 \(index + 1) 天" : day.title,
                dateText: day.date.formatted(.dateTime.month().day().weekday(.wide)),
                narrative: [fields.contains(.memory) ? day.note : "", fields.contains(.supplement) ? day.details : ""].filter { !$0.isEmpty }.joined(separator: "\n"),
                items: day.sortedEntries.filter { selectedItemIDs == nil || selectedItemIDs!.contains($0.id) }.map {
                    ShareCardItem(
                        id: $0.id,
                        time: fields.contains(.time) && !$0.timeLabel.isEmpty ? "🕒 \($0.timeLabel)" : "",
                        title: fields.contains(.title) ? $0.title : "",
                        detail: [
                            [fields.contains(.location) && !$0.locationTargets.isEmpty ? "📍 " + $0.locationTargets.map(\.displayName).joined(separator: " → ") : "", fields.contains(.cost) && $0.cost != 0 ? "💰 ¥\($0.cost)" : ""].filter { !$0.isEmpty }.joined(separator: " · "),
                            fields.contains(.memory) && !$0.note.isEmpty ? "💭 \($0.note)" : "",
                            fields.contains(.supplement) && !$0.arrangementNote.isEmpty ? "📝 \($0.arrangementNote)" : ""
                        ].filter { !$0.isEmpty }.joined(separator: "\n"),
                        completed: true,
                        category: fields.contains(.category) ? $0.category : .other,
                        symbol: fields.contains(.category) ? $0.arrangementSymbol : "circle.fill",
                        statusText: "",
                        photoAssetIdentifiers: fields.contains(.media) ? $0.sortedMedia
                            .filter { $0.kind == .image }
                            .map(\.localIdentifier) : []
                    )
                }
            )
        }
        let fallbackCoverIdentifier = days
            .flatMap(\.sortedEntries)
            .filter { selectedItemIDs == nil || selectedItemIDs!.contains($0.id) }
            .flatMap(\.sortedMedia)
            .first { $0.kind == .image }?
            .localIdentifier
        coverAssetIdentifier = fields.contains(.media) ? (story.coverMedia?.localIdentifier ?? fallbackCoverIdentifier) : nil
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

private enum ShareExportSource {
    var fileTypeLabel: String {
        switch self {
        case .trip: return "旅程"
        case .story: return "足迹"
        }
    }

    case trip(Trip)
    case story(TravelStory)

    var allData: ShareCardData {
        switch self {
        case .trip(let trip): return ShareCardData(trip: trip)
        case .story(let story): return ShareCardData(story: story)
        }
    }

    func initialSelection(scopeID: UUID?) -> Set<UUID> {
        let sections = allData.sections
        let chosen = sections.first { $0.id == scopeID }.map { [$0] } ?? sections
        return Set(chosen.flatMap(\.items).map(\.id))
    }

    func data(for ids: Set<UUID>, fields: Set<ShareField>) -> ShareCardData {
        switch self {
        case .trip(let trip): return ShareCardData(trip: trip, selectedItemIDs: ids, fields: fields)
        case .story(let story): return ShareCardData(story: story, selectedItemIDs: ids, fields: fields)
        }
    }

    @MainActor
    func portableData(for ids: Set<UUID>, excludedMedia: Set<UUID>, fields: Set<ShareField>, includeMedia: Bool = false) throws -> Data {
        let data: Data
        switch self {
        case .trip(let trip): data = try SharedJourneyService.makeShareData(trip: trip, selectedItemIDs: ids, includeMedia: includeMedia)
        case .story(let story): data = try SharedJourneyService.makeShareData(story: story, selectedItemIDs: ids, includeMedia: includeMedia)
        }
        return try SharedJourneyService.filterShareFields(fields, from: SharedJourneyService.excludingMedia(excludedMedia, from: data))
    }

    @MainActor
    func media(for ids: Set<UUID>) -> [MediaReference] {
        switch self {
        case .trip(let trip): return trip.allItems.filter { ids.contains($0.id) }.flatMap(\.media) + [trip.coverMedia].compactMap { $0 }
        case .story(let story): return story.sortedEntries.filter { ids.contains($0.id) }.flatMap(\.media) + [story.coverMedia].compactMap { $0 }
        }
    }

    @MainActor
    func portablePackage(for ids: Set<UUID>, excludedMedia: Set<UUID>, fields: Set<ShareField>) async throws -> PortablePackageExportResult {
        try await PortablePackageService.makePackage(kind: .sharedJourney, contentData: portableData(for: ids, excludedMedia: excludedMedia, fields: fields, includeMedia: fields.contains(.media)), mediaReferences: fields.contains(.media) ? media(for: ids).filter { !excludedMedia.contains($0.id) } : [], fileExtension: "triptrail")
    }
}

struct ShareExportView: View {
    @Environment(\.dismiss) private var dismiss
    private let source: ShareExportSource
    private let initialScopeID: UUID?
    @State private var selectedItemIDs: Set<UUID>
    @State private var selectedFields = Set(ShareField.allCases).subtracting([.cost, .time])
    @State private var excludedMediaIDs: Set<UUID> = []
    @State private var coverImage: UIImage?
    @State private var photoImages: [String: UIImage] = [:]
    @State private var imageCache = NSCache<NSString, UIImage>()
    @State private var isPreparingImage = false
    @State private var renderedImage: UIImage?
    @State private var showsImageShare = false
    @State private var isPreparingPortableFile = false
    @State private var showsPortableOptions = false
    @State private var portableShareItem: PortableShareItem?
    @State private var temporaryFiles = TemporaryFileOwner()
    @State private var isClosed = false
    @State private var message: String?

    init(trip: Trip, initialScopeID: UUID? = nil) {
        source = .trip(trip)
        self.initialScopeID = initialScopeID
        _selectedItemIDs = State(initialValue: ShareExportSource.trip(trip).initialSelection(scopeID: initialScopeID))
    }

    init(story: TravelStory, initialScopeID: UUID? = nil) {
        source = .story(story)
        self.initialScopeID = initialScopeID
        _selectedItemIDs = State(initialValue: ShareExportSource.story(story).initialSelection(scopeID: initialScopeID))
    }

    private var selectionSections: [ShareCardSection] {
        let sections = source.allData.sections
        if let initialScopeID, sections.contains(where: { $0.id == initialScopeID }) {
            return sections.filter { $0.id == initialScopeID }
        }
        return sections
    }
    private var selectableItemIDs: Set<UUID> { Set(selectionSections.flatMap(\.items).map(\.id)) }
    private var availableMedia: [MediaReference] {
        var seen = Set<UUID>()
        return source.media(for: selectedItemIDs).filter { seen.insert($0.id).inserted }
    }
    private var selectionKey: String {
        selectedItemIDs.map(\.uuidString).sorted().joined() + ":" + excludedMediaIDs.map(\.uuidString).sorted().joined() + selectedFields.map(\.rawValue).sorted().joined()
    }
    private var data: ShareCardData {
        var result = source.data(for: selectedItemIDs, fields: selectedFields)
        let excludedAssets = Set(availableMedia.filter { excludedMediaIDs.contains($0.id) }.map(\.localIdentifier))
        result.sections = result.sections.map { section in
            var value = section
            value.items = section.items.map { item in
                var value = item
                value.photoAssetIdentifiers.removeAll { excludedAssets.contains($0) }
                return value
            }
            return value
        }
        if let cover = result.coverAssetIdentifier, excludedAssets.contains(cover) {
            result.coverAssetIdentifier = result.photoAssetIdentifiers.first
        }
        return result
    }

    var body: some View {
        TripNavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    scopePicker
                    fieldPicker
                    if selectedFields.contains(.media) && !availableMedia.isEmpty { mediaPicker }

                    ShareCard(data: data, coverImage: coverImage, photoImages: photoImages)
                        .frame(width: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.16), radius: 20, y: 10)

                    if selectedItemIDs.isEmpty {
                        Text("请至少选择一个安排").foregroundStyle(.secondary)
                    } else {
                        Button { prepareLongImage() } label: {
                            if isPreparingImage { ProgressView("正在生成分享长图…").frame(maxWidth: .infinity) }
                            else { Label("分享精美长图", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        }.buttonStyle(.borderedProminent).disabled(isPreparingImage)
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
                        .disabled(selectedItemIDs.isEmpty)
                    }
                }
                .padding()
            }
            .background(Color.tripCanvas)
            .navigationTitle("分享预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("返回") { dismiss() } } }
            .task(id: selectionKey) {
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                await updatePreviewImages()
            }
            .onAppear {
                isClosed = false
                imageCache.countLimit = 40
                imageCache.totalCostLimit = 48 * 1024 * 1024
            }
            .onDisappear {
                isClosed = true
                imageCache.removeAllObjects()
                photoImages = [:]; coverImage = nil
                if !showsImageShare { renderedImage = nil }
                if portableShareItem == nil { temporaryFiles.clear() }
            }
            .sheet(isPresented: $showsImageShare, onDismiss: { renderedImage = nil }) {
                if let renderedImage {
                    // Share the image itself so receiving apps do not treat it as a document URL.
                    SystemShareSheet(items: [renderedImage])
                }
            }
            .confirmationDialog("是否包含照片与视频？", isPresented: $showsPortableOptions, titleVisibility: .visible) {
                let mediaCount = availableMedia.filter { !excludedMediaIDs.contains($0.id) }.count
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
                SystemShareSheet(items: [item.url], onPresent: { temporaryFiles.handOff(item.url) })
            }
            .alert("分享提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private func selectionMark(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(selected ? Color.tripLake : Color.secondary.opacity(0.35))
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择分享安排").font(.headline)
                    Text("已选择 \(selectedItemIDs.count) 个安排").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(selectedItemIDs == selectableItemIDs ? "取消全选" : "全选") {
                    selectedItemIDs = selectedItemIDs == selectableItemIDs ? [] : selectableItemIDs
                }.font(.caption.weight(.semibold)).foregroundStyle(Color.tripLakeText)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.tripLake.opacity(0.09), in: Capsule())
            }
            ForEach(selectionSections) { section in
                let ids = Set(section.items.map(\.id))
                VStack(spacing: 0) {
                    Button {
                        selectedItemIDs = ids.isSubset(of: selectedItemIDs) ? selectedItemIDs.subtracting(ids) : selectedItemIDs.union(ids)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.tripLakeText)
                                .frame(width: 34, height: 34)
                                .background(Color.tripLake.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(section.title).font(.headline.weight(.semibold)).foregroundStyle(Color.tripInk)
                                Text(section.dateText).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(spacing: 4) {
                                selectionMark(!ids.isEmpty && ids.isSubset(of: selectedItemIDs))
                                Text("\(selectedItemIDs.intersection(ids).count)/\(ids.count)").font(.caption2).foregroundStyle(Color.tripLakeText)
                            }
                        }.padding(12).frame(maxWidth: .infinity)
                            .background(Color.tripLake.opacity(0.11))
                    }
                    ForEach(section.items) { item in
                        Button {
                            if selectedItemIDs.contains(item.id) { selectedItemIDs.remove(item.id) }
                            else { selectedItemIDs.insert(item.id) }
                        } label: {
                            HStack(spacing: 10) {
                                selectionMark(selectedItemIDs.contains(item.id))
                                Text(item.title).font(.subheadline).foregroundStyle(Color.tripInk)
                                Spacer(minLength: 8)
                            }.padding(.leading, 28).padding(.trailing, 12)
                                .frame(minHeight: 48).contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    if item.id != section.items.last?.id {
                                        Rectangle().fill(Color.tripMist.opacity(0.45)).frame(height: 0.5).padding(.leading, 59)
                                    }
                                }
                        }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.tripLake.opacity(0.10)))
            }
        }.buttonStyle(.plain).cardSurface()
    }

    private var fieldPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分享字段").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ShareField.selectable) { field in
                    let selected = selectedFields.contains(field)
                    Button {
                        if selected { selectedFields.remove(field) }
                        else { selectedFields.insert(field) }
                    } label: {
                        HStack(spacing: 8) {
                            selectionMark(selected)
                            Text(field.rawValue).font(.subheadline).foregroundStyle(Color.tripInk)
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 12).frame(minHeight: 46)
                            .background(selected ? Color.tripLake.opacity(0.07) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }
        }.cardSurface()
    }

    private var mediaPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("照片与视频").font(.headline)
            Text("已选择 \(availableMedia.filter { !excludedMediaIDs.contains($0.id) }.count) / \(availableMedia.count)，取消勾选可排除媒体")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(availableMedia) { media in
                    Button {
                        if excludedMediaIDs.contains(media.id) { excludedMediaIDs.remove(media.id) }
                        else { excludedMediaIDs.insert(media.id) }
                    } label: {
                        GeometryReader { geometry in
                            AssetThumbnail(identifier: media.localIdentifier, showsVideoBadge: media.kind == .video)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        }
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: excludedMediaIDs.contains(media.id) ? "circle" : "checkmark.circle.fill")
                                    .foregroundStyle(.white, Color.accentColor).padding(6)
                            }
                    }.buttonStyle(.plain)
                }
            }
        }.cardSurface()
    }

    private func preparePortableFile(includeMedia: Bool) {
        let currentData = data
        let currentSelection = selectedItemIDs
        let currentExcludedMedia = excludedMediaIDs
        let currentFields = selectedFields
        isPreparingPortableFile = true
        Task { @MainActor in
            defer { isPreparingPortableFile = false }
            do {
                let safeName = currentData.title.replacingOccurrences(of: "/", with: "-")
                let generatedURL: URL
                if includeMedia {
                    let result = try await source.portablePackage(for: currentSelection, excludedMedia: currentExcludedMedia, fields: currentFields)
                    defer { try? FileManager.default.removeItem(at: result.url) }
                    let namedURL = try TemporaryFileOwner.shareURL(filename: "旅迹-\(source.fileTypeLabel)-\(safeName)-\(currentData.scopeLabel)-含媒体-\(UUID().uuidString.prefix(6)).triptrail")
                    try FileManager.default.moveItem(at: result.url, to: namedURL)
                    generatedURL = namedURL
                } else {
                    let portableData = try source.portableData(for: currentSelection, excludedMedia: currentExcludedMedia, fields: currentFields)
                    let portableURL = try TemporaryFileOwner.shareURL(filename: "旅迹-\(source.fileTypeLabel)-\(safeName)-\(currentData.scopeLabel)-\(UUID().uuidString.prefix(6)).triptrail")
                    do { try portableData.write(to: portableURL, options: .atomic) }
                    catch { try? FileManager.default.removeItem(at: portableURL); throw error }
                    generatedURL = portableURL
                }
                temporaryFiles.keep(generatedURL)
                guard !isClosed, currentSelection == selectedItemIDs, currentExcludedMedia == excludedMediaIDs, currentFields == selectedFields else {
                    temporaryFiles.remove(generatedURL)
                    return
                }
                portableShareItem = PortableShareItem(url: generatedURL)
            } catch {
                message = "可导入文件生成失败：\(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func cachedImage(_ identifier: String, cover: Bool = false) async -> UIImage? {
        let key = "\(cover ? "cover" : "preview"):\(identifier)" as NSString
        if let image = imageCache.object(forKey: key) { return image }
        let image = await PhotoLibraryService.shareImage(identifier: identifier,
            targetSize: cover ? CGSize(width: 1200, height: 1200) : CGSize(width: 600, height: 600))
        guard !isClosed, !Task.isCancelled else { return nil }
        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            imageCache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    @MainActor
    private func images(for snapshot: ShareCardData) async -> (UIImage?, [String: UIImage]) {
        var photos: [String: UIImage] = [:]
        for identifier in snapshot.photoAssetIdentifiers {
            guard !Task.isCancelled, !isClosed else { return (nil, [:]) }
            if let image = await cachedImage(identifier) { photos[identifier] = image }
        }
        let cover = if let identifier = snapshot.coverAssetIdentifier { await cachedImage(identifier, cover: true) } else { nil as UIImage? }
        return (cover, photos)
    }

    @MainActor
    private func updatePreviewImages() async {
        let key = selectionKey
        let snapshot = data
        let (cover, photos) = await images(for: snapshot)
        guard !Task.isCancelled, !isClosed, key == selectionKey else { return }
        coverImage = cover; photoImages = photos
    }

    private func prepareLongImage() {
        guard !isPreparingImage, !selectedItemIDs.isEmpty else { return }
        let key = selectionKey
        let snapshot = data
        isPreparingImage = true
        Task { @MainActor in
            defer { isPreparingImage = false }
            let (cover, photos) = await images(for: snapshot)
            guard !isClosed, key == selectionKey else { return }
            guard let image = ShareCardImageRenderer.render(data: snapshot, coverImage: cover, photoImages: photos) else {
                message = "分享图生成失败，请稍后重试。"
                return
            }
            renderedImage = image
            showsImageShare = true
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
    var onPresent: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        onPresent?()
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ShareCard: View {
    let data: ShareCardData
    let coverImage: UIImage?
    let photoImages: [String: UIImage]

    private var singleDayDetails: String { "" }

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
                    if !singleDayDetails.isEmpty {
                        Text(singleDayDetails)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.92))
                            .lineSpacing(3)
                            .lineLimit(5)
                    }
                }
                .padding(22)
            }
            .frame(height: singleDayDetails.isEmpty ? 252 : 340)
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
                            if data.sections.count > 1 {
                                Text("D\(sectionIndex + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.tripLake, in: Circle())
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                    .font(.headline.bold())
                                    .foregroundStyle(Color.tripInk)
                                Text(section.dateText)
                                    .font(.caption)
                                    .foregroundStyle(Color.tripInk.opacity(0.62))
                            }
                            Spacer()

                        }
                        if !section.narrative.isEmpty {
                            Text(section.narrative)
                                .font(.caption)
                                .foregroundStyle(Color.tripInk.opacity(0.68))
                                .lineSpacing(2)
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
                                            Image(systemName: item.symbol)
                                                .font(.caption2.bold())
                                                .foregroundStyle(item.completed ? .white : Color.tripLake)

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
                                .shadow(color: Color.black.opacity(0.075), radius: 8, y: 4)
                            }
                        }
                    }
                    .padding(data.sections.count > 1 ? 14 : 0)
                    .background(data.sections.count > 1 ? Color.shareDayPanel : Color.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.tripLake.opacity(data.sections.count > 1 ? 0.20 : 0), lineWidth: 1)
                    }
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.tripLake.opacity(data.sections.count > 1 ? 0.58 : 0))
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
        let count = 3
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: count)
    }

    var body: some View {
        if !availableIdentifiers.isEmpty {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(displayedIdentifiers.enumerated()), id: \.element) { index, identifier in
                    if let image = images[identifier] {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                GeometryReader { proxy in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                        .clipped()
                                }
                            }
                            .overlay {
                                if index == 3, availableIdentifiers.count > displayedIdentifiers.count {
                                    ZStack {
                                        Color.black.opacity(0.42)
                                        Text("+\(availableIdentifiers.count - displayedIdentifiers.count)")
                                            .font(.title2.bold())
                                            .foregroundStyle(.white)
                                    }
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
