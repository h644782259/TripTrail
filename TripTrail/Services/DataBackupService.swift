import Foundation
import SwiftData

struct TripTrailBackupSummary: Equatable {
    let exportedAt: Date
    let tripCount: Int
    let storyCount: Int
    let dayCount: Int
    let placeCount: Int
    let mediaReferenceCount: Int

    var restoreDescription: String {
        "\(tripCount) 段旅程、\(storyCount) 篇足迹、\(dayCount) 天记录、\(placeCount) 个地点、\(mediaReferenceCount) 个媒体文件"
    }
}

enum TripTrailBackupError: LocalizedError {
    case unreadableFile
    case unsupportedVersion(Int)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "这不是有效的旅迹备份文件。"
        case .unsupportedVersion(let version):
            "该备份版本为 \(version)，当前 App 暂不支持恢复。"
        case .restoreFailed(let reason):
            "恢复失败，本机原有数据已保留。\(reason)"
        }
    }
}

@MainActor
enum DataBackupService {
    private static let currentFormatVersion = 1

    static func makeBackupData(from modelContext: ModelContext, exportedAt: Date = Date()) throws -> Data {
        let trips = try modelContext.fetch(FetchDescriptor<Trip>())
            .sorted { $0.createdAt < $1.createdAt }
        let stories = try modelContext.fetch(FetchDescriptor<TravelStory>())
            .sorted { $0.createdAt < $1.createdAt }
        let backup = BackupFile(
            formatVersion: currentFormatVersion,
            exportedAt: exportedAt,
            trips: trips.map { TripRecord($0) },
            stories: stories.map { StoryRecord($0) }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(backup)
    }

    static func makeBackupPackage(from modelContext: ModelContext, exportedAt: Date = Date()) async throws -> PortablePackageExportResult {
        let trips = try modelContext.fetch(FetchDescriptor<Trip>())
            .sorted { $0.createdAt < $1.createdAt }
        let stories = try modelContext.fetch(FetchDescriptor<TravelStory>())
            .sorted { $0.createdAt < $1.createdAt }
        let data = try makeBackupData(from: modelContext, exportedAt: exportedAt)
        let media = trips
            .flatMap(\.sortedDays)
            .flatMap(\.sortedItems)
            .flatMap(\.media)
            + stories.flatMap(\.sortedEntries).flatMap(\.sortedMedia)
        return try await PortablePackageService.makePackage(
            kind: .backup,
            contentData: data,
            mediaReferences: media,
            fileExtension: "triptrailbackup"
        )
    }

    static func inspectBackup(_ data: Data) throws -> TripTrailBackupSummary {
        try decode(data).summary
    }

    static func inspectBackup(at url: URL) throws -> TripTrailBackupSummary {
        if let package = try PortablePackageService.open(url) {
            guard package.kind == .backup else { throw PortablePackageError.wrongPackageKind }
            return try inspectBackup(package.contentData)
        }
        return try inspectBackup(Data(contentsOf: url))
    }

    @discardableResult
    static func restoreBackup(_ data: Data, into modelContext: ModelContext) throws -> TripTrailBackupSummary {
        let backup = try decode(data)

        // 先在内存中完整重建对象图，确保备份内容有效后才更改当前数据库。
        let restoredTrips = backup.trips.map { $0.makeModel() }
        let restoredStories = backup.stories.map { $0.makeModel() }

        do {
            let existingTrips = try modelContext.fetch(FetchDescriptor<Trip>())
            let existingStories = try modelContext.fetch(FetchDescriptor<TravelStory>())
            existingTrips.forEach(modelContext.delete)
            existingStories.forEach(modelContext.delete)
            restoredTrips.forEach(modelContext.insert)
            restoredStories.forEach(modelContext.insert)
            try modelContext.save()
            return backup.summary
        } catch {
            modelContext.rollback()
            throw TripTrailBackupError.restoreFailed(error.localizedDescription)
        }
    }

    @discardableResult
    static func restoreBackup(from url: URL, into modelContext: ModelContext) async throws -> TripTrailBackupSummary {
        guard let package = try PortablePackageService.open(url) else {
            return try restoreBackup(Data(contentsOf: url), into: modelContext)
        }
        guard package.kind == .backup else { throw PortablePackageError.wrongPackageKind }
        let backup = try decode(package.contentData)
        let restoredTrips = backup.trips.map { $0.makeModel() }
        let restoredStories = backup.stories.map { $0.makeModel() }
        let identifiers = try await PortablePackageService.restoreMedia(from: package)
        guard identifiers.count == backup.summary.mediaReferenceCount else {
            throw TripTrailBackupError.restoreFailed("媒体清单与数据引用不一致。")
        }
        applyMediaIdentifiers(identifiers, trips: restoredTrips, stories: restoredStories)

        do {
            let existingTrips = try modelContext.fetch(FetchDescriptor<Trip>())
            let existingStories = try modelContext.fetch(FetchDescriptor<TravelStory>())
            existingTrips.forEach(modelContext.delete)
            existingStories.forEach(modelContext.delete)
            restoredTrips.forEach(modelContext.insert)
            restoredStories.forEach(modelContext.insert)
            try modelContext.save()
            return backup.summary
        } catch {
            modelContext.rollback()
            throw TripTrailBackupError.restoreFailed(error.localizedDescription)
        }
    }

    private static func applyMediaIdentifiers(
        _ identifiers: [UUID: String],
        trips: [Trip],
        stories: [TravelStory]
    ) {
        let media = trips.flatMap(\.sortedDays).flatMap(\.sortedItems).flatMap(\.media)
            + stories.flatMap(\.sortedEntries).flatMap(\.media)
        for reference in media {
            if let identifier = identifiers[reference.id] {
                reference.localIdentifier = identifier
            }
        }
    }

    private static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let backup: BackupFile
        do {
            backup = try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw TripTrailBackupError.unreadableFile
        }
        guard backup.formatVersion == currentFormatVersion else {
            throw TripTrailBackupError.unsupportedVersion(backup.formatVersion)
        }
        return backup
    }
}

enum SharedJourneyKind: String, Codable {
    case trip
    case footprint

    var displayName: String {
        switch self {
        case .trip: "旅程"
        case .footprint: "足迹"
        }
    }
}

struct SharedJourneySummary: Equatable {
    let kind: SharedJourneyKind
    let title: String
    let destination: String
    let dayCount: Int
    let placeCount: Int
    let mediaCount: Int

    var importDescription: String {
        let mediaText = mediaCount > 0 ? "、\(mediaCount) 个媒体文件" : ""
        return "\(kind.displayName)“\(title)”（\(dayCount) 天、\(placeCount) 个地点\(mediaText)）"
    }
}

struct SharedJourneyImportResult: Equatable {
    let summary: SharedJourneySummary
    let wasAlreadyPresent: Bool
}

struct SharedJourneyPreview {
    struct Day: Identifiable {
        let id: UUID
        let title: String
        let date: Date
        let narrative: String
        let places: [Place]
    }

    struct Place: Identifiable {
        let id: UUID
        let title: String
        let category: String
        let time: String
        let address: String
        let note: String
    }

    let summary: SharedJourneySummary
    let startDate: Date
    let endDate: Date
    let overview: String
    let days: [Day]
}

enum SharedJourneyError: LocalizedError {
    case unreadableFile
    case unsupportedVersion(Int)
    case invalidContent
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "这不是有效的旅迹分享文件。"
        case .unsupportedVersion(let version):
            "该分享文件版本为 \(version)，当前 App 暂不支持导入。"
        case .invalidContent:
            "分享文件没有包含可导入的旅程或足迹。"
        case .importFailed(let reason):
            "导入失败，本机原有数据未受影响。\(reason)"
        }
    }
}

/// 跨平台交换格式：轻量分享为 JSON；包含媒体时使用版本化容器封装 JSON 与原始媒体字节。
@MainActor
enum SharedJourneyService {
    private static let formatName = "triptrail.shared-journey"
    private static let currentFormatVersion = 1

    static func makeShareData(
        trip: Trip,
        selectedDay: TripDay? = nil,
        sharedAt: Date = Date(),
        includeMedia: Bool = false
    ) throws -> Data {
        try encode(
            SharedJourneyFile(
                format: formatName,
                formatVersion: currentFormatVersion,
                sharedAt: sharedAt,
                kind: .trip,
                trip: TripRecord(
                    trip,
                    selectedDay: selectedDay,
                    includeMedia: includeMedia,
                    includeLocalMediaIdentifiers: false
                ),
                story: nil
            )
        )
    }

    static func makeShareData(
        story: TravelStory,
        selectedDay: StoryDay? = nil,
        sharedAt: Date = Date(),
        includeMedia: Bool = false
    ) throws -> Data {
        try encode(
            SharedJourneyFile(
                format: formatName,
                formatVersion: currentFormatVersion,
                sharedAt: sharedAt,
                kind: .footprint,
                trip: nil,
                story: StoryRecord(
                    story,
                    selectedDay: selectedDay,
                    includeMedia: includeMedia,
                    includeSourceLinks: false,
                    includeLocalMediaIdentifiers: false
                )
            )
        )
    }

    static func makeSharePackage(trip: Trip, selectedDay: TripDay? = nil) async throws -> PortablePackageExportResult {
        let days = selectedDay.map { [$0] } ?? trip.sortedDays
        let media = days.flatMap(\.sortedItems).flatMap(\.media)
        return try await PortablePackageService.makePackage(
            kind: .sharedJourney,
            contentData: try makeShareData(trip: trip, selectedDay: selectedDay, includeMedia: true),
            mediaReferences: media,
            fileExtension: "triptrail"
        )
    }

    static func makeSharePackage(story: TravelStory, selectedDay: StoryDay? = nil) async throws -> PortablePackageExportResult {
        let days = selectedDay.map { [$0] } ?? story.sortedDays
        let media = days.flatMap(\.sortedEntries).flatMap(\.sortedMedia)
        return try await PortablePackageService.makePackage(
            kind: .sharedJourney,
            contentData: try makeShareData(story: story, selectedDay: selectedDay, includeMedia: true),
            mediaReferences: media,
            fileExtension: "triptrail"
        )
    }

    static func inspect(_ data: Data) throws -> SharedJourneySummary {
        try decode(data).summary
    }

    static func inspect(at url: URL) throws -> SharedJourneySummary {
        if let package = try PortablePackageService.open(url) {
            guard package.kind == .sharedJourney else { throw PortablePackageError.wrongPackageKind }
            return try inspect(package.contentData)
        }
        return try inspect(Data(contentsOf: url))
    }

    static func preview(_ data: Data) throws -> SharedJourneyPreview {
        let package = try decode(data)
        let summary = try package.summary
        switch package.kind {
        case .trip:
            guard let trip = package.trip else { throw SharedJourneyError.invalidContent }
            return SharedJourneyPreview(
                summary: summary,
                startDate: trip.startDate,
                endDate: trip.endDate,
                overview: trip.note,
                days: trip.days.map { day in
                    SharedJourneyPreview.Day(
                        id: day.id,
                        title: day.title,
                        date: day.date,
                        narrative: day.note,
                        places: day.items.map { item in
                            SharedJourneyPreview.Place(
                                id: item.id,
                                title: item.title,
                                category: item.categoryRaw,
                                time: "\(item.startTime.formatted(date: .omitted, time: .shortened))–\(item.endTime.formatted(date: .omitted, time: .shortened))",
                                address: item.address,
                                note: item.note
                            )
                        }
                    )
                }
            )
        case .footprint:
            guard let story = package.story else { throw SharedJourneyError.invalidContent }
            let entriesByDay = Dictionary(grouping: story.entries, by: \.storyDayID)
            return SharedJourneyPreview(
                summary: summary,
                startDate: story.startDate,
                endDate: story.endDate,
                overview: story.summary,
                days: story.days.map { day in
                    SharedJourneyPreview.Day(
                        id: day.id,
                        title: day.title,
                        date: day.date,
                        narrative: [day.note, day.details].filter { !$0.isEmpty }.joined(separator: "\n"),
                        places: (entriesByDay[day.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }.map { entry in
                            SharedJourneyPreview.Place(
                                id: entry.id,
                                title: entry.title,
                                category: entry.categoryRaw,
                                time: entry.timeLabel,
                                address: entry.address,
                                note: [entry.note, entry.routeInfo].filter { !$0.isEmpty }.joined(separator: " · ")
                            )
                        }
                    )
                }
            )
        }
    }

    static func preview(at url: URL) throws -> SharedJourneyPreview {
        if let package = try PortablePackageService.open(url) {
            guard package.kind == .sharedJourney else { throw PortablePackageError.wrongPackageKind }
            return try preview(package.contentData)
        }
        return try preview(Data(contentsOf: url))
    }

    @discardableResult
    static func importJourney(_ data: Data, into modelContext: ModelContext) throws -> SharedJourneyImportResult {
        let package = try decode(data)
        let summary = try package.summary

        do {
            switch package.kind {
            case .trip:
                guard let record = package.trip else { throw SharedJourneyError.invalidContent }
                let alreadyExists = try modelContext.fetch(FetchDescriptor<Trip>()).contains { $0.id == record.id }
                guard !alreadyExists else {
                    return SharedJourneyImportResult(summary: summary, wasAlreadyPresent: true)
                }
                modelContext.insert(record.makeModel())
            case .footprint:
                guard let record = package.story else { throw SharedJourneyError.invalidContent }
                let alreadyExists = try modelContext.fetch(FetchDescriptor<TravelStory>()).contains { $0.id == record.id }
                guard !alreadyExists else {
                    return SharedJourneyImportResult(summary: summary, wasAlreadyPresent: true)
                }
                // 别人分享的足迹是独立副本，不保留对分享者源行程的同步关系。
                modelContext.insert(record.makeModel(preserveSourceLinks: false))
            }
            try modelContext.save()
            return SharedJourneyImportResult(summary: summary, wasAlreadyPresent: false)
        } catch let error as SharedJourneyError {
            throw error
        } catch {
            modelContext.rollback()
            throw SharedJourneyError.importFailed(error.localizedDescription)
        }
    }

    @discardableResult
    static func importJourney(from url: URL, into modelContext: ModelContext) async throws -> SharedJourneyImportResult {
        guard let portablePackage = try PortablePackageService.open(url) else {
            return try importJourney(Data(contentsOf: url), into: modelContext)
        }
        guard portablePackage.kind == .sharedJourney else { throw PortablePackageError.wrongPackageKind }
        let package = try decode(portablePackage.contentData)
        let summary = try package.summary

        switch package.kind {
        case .trip:
            guard let record = package.trip else { throw SharedJourneyError.invalidContent }
            if try modelContext.fetch(FetchDescriptor<Trip>()).contains(where: { $0.id == record.id }) {
                return SharedJourneyImportResult(summary: summary, wasAlreadyPresent: true)
            }
        case .footprint:
            guard let record = package.story else { throw SharedJourneyError.invalidContent }
            if try modelContext.fetch(FetchDescriptor<TravelStory>()).contains(where: { $0.id == record.id }) {
                return SharedJourneyImportResult(summary: summary, wasAlreadyPresent: true)
            }
        }

        let identifiers = try await PortablePackageService.restoreMedia(from: portablePackage)
        guard identifiers.count == summary.mediaCount else { throw SharedJourneyError.invalidContent }
        do {
            switch package.kind {
            case .trip:
                guard let record = package.trip else { throw SharedJourneyError.invalidContent }
                let trip = record.makeModel()
                applyMediaIdentifiers(identifiers, to: trip.sortedDays.flatMap(\.sortedItems).flatMap(\.media))
                modelContext.insert(trip)
            case .footprint:
                guard let record = package.story else { throw SharedJourneyError.invalidContent }
                let story = record.makeModel(preserveSourceLinks: false)
                applyMediaIdentifiers(identifiers, to: story.sortedEntries.flatMap(\.media))
                modelContext.insert(story)
            }
            try modelContext.save()
            return SharedJourneyImportResult(summary: summary, wasAlreadyPresent: false)
        } catch let error as SharedJourneyError {
            throw error
        } catch {
            modelContext.rollback()
            throw SharedJourneyError.importFailed(error.localizedDescription)
        }
    }

    private static func applyMediaIdentifiers(_ identifiers: [UUID: String], to media: [MediaReference]) {
        for reference in media {
            guard let identifier = identifiers[reference.id] else { continue }
            reference.localIdentifier = identifier
        }
    }

    private static func encode(_ package: SharedJourneyFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(package)
    }

    private static func decode(_ data: Data) throws -> SharedJourneyFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package: SharedJourneyFile
        do {
            package = try decoder.decode(SharedJourneyFile.self, from: data)
        } catch {
            throw SharedJourneyError.unreadableFile
        }
        guard package.format == formatName else { throw SharedJourneyError.unreadableFile }
        guard package.formatVersion == currentFormatVersion else {
            throw SharedJourneyError.unsupportedVersion(package.formatVersion)
        }
        _ = try package.summary
        return package
    }
}

private struct SharedJourneyFile: Codable {
    let format: String
    let formatVersion: Int
    let sharedAt: Date
    let kind: SharedJourneyKind
    let trip: TripRecord?
    let story: StoryRecord?

    var summary: SharedJourneySummary {
        get throws {
            switch kind {
            case .trip:
                guard let trip, story == nil else { throw SharedJourneyError.invalidContent }
                return SharedJourneySummary(
                    kind: .trip,
                    title: trip.title,
                    destination: trip.destination,
                    dayCount: trip.days.count,
                    placeCount: trip.days.flatMap(\.items).count,
                    mediaCount: trip.days.flatMap(\.items).flatMap(\.media).count
                )
            case .footprint:
                guard let story, trip == nil else { throw SharedJourneyError.invalidContent }
                return SharedJourneySummary(
                    kind: .footprint,
                    title: story.title,
                    destination: story.destination,
                    dayCount: story.days.count,
                    placeCount: story.entries.count,
                    mediaCount: story.entries.flatMap(\.media).count
                )
            }
        }
    }
}

private struct BackupFile: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let trips: [TripRecord]
    let stories: [StoryRecord]

    var summary: TripTrailBackupSummary {
        let tripDays = trips.flatMap(\.days)
        let storyDays = stories.flatMap(\.days)
        let tripItems = tripDays.flatMap(\.items)
        let storyEntries = stories.flatMap(\.entries)
        let mediaCount = tripItems.flatMap(\.media).count + storyEntries.flatMap(\.media).count
        return TripTrailBackupSummary(
            exportedAt: exportedAt,
            tripCount: trips.count,
            storyCount: stories.count,
            dayCount: tripDays.count + storyDays.count,
            placeCount: tripItems.count + storyEntries.count,
            mediaReferenceCount: mediaCount
        )
    }
}

private struct TripRecord: Codable {
    let id: UUID
    let title: String
    let destination: String
    let startDate: Date
    let endDate: Date
    let note: String
    let createdAt: Date
    let days: [TripDayRecord]

    init(
        _ trip: Trip,
        selectedDay: TripDay? = nil,
        includeMedia: Bool = true,
        includeLocalMediaIdentifiers: Bool = true
    ) {
        id = trip.id
        title = selectedDay.map { day in
            day.title.isEmpty ? trip.title : "\(trip.title) · \(day.title)"
        } ?? trip.title
        destination = trip.destination
        startDate = selectedDay?.date ?? trip.startDate
        endDate = selectedDay?.date ?? trip.endDate
        note = selectedDay?.note ?? trip.note
        createdAt = trip.createdAt
        days = (selectedDay.map { [$0] } ?? trip.sortedDays).map {
            TripDayRecord(
                $0,
                includeMedia: includeMedia,
                includeLocalMediaIdentifiers: includeLocalMediaIdentifiers
            )
        }
    }

    func makeModel() -> Trip {
        let trip = Trip(title: title, destination: destination, startDate: startDate, endDate: endDate, note: note)
        trip.id = id
        trip.createdAt = createdAt
        for dayRecord in days {
            let day = dayRecord.makeModel(trip: trip)
            trip.days.append(day)
        }
        return trip
    }
}

private struct TripDayRecord: Codable {
    let id: UUID
    let date: Date
    let title: String
    let note: String
    let sortOrder: Int
    let items: [ItineraryItemRecord]

    init(_ day: TripDay, includeMedia: Bool = true, includeLocalMediaIdentifiers: Bool = true) {
        id = day.id
        date = day.date
        title = day.title
        note = day.note
        sortOrder = day.sortOrder
        items = day.sortedItems.map {
            ItineraryItemRecord(
                $0,
                includeMedia: includeMedia,
                includeLocalMediaIdentifiers: includeLocalMediaIdentifiers
            )
        }
    }

    func makeModel(trip: Trip) -> TripDay {
        let day = TripDay(date: date, title: title, sortOrder: sortOrder, trip: trip)
        day.id = id
        day.note = note
        for itemRecord in items {
            let item = itemRecord.makeModel(day: day)
            day.items.append(item)
        }
        return day
    }
}

private struct ItineraryItemRecord: Codable {
    let id: UUID
    let title: String
    let categoryRaw: String
    let startTime: Date
    let endTime: Date
    let address: String
    let note: String
    let transportRaw: String
    let distanceText: String
    let playDurationMinutes: Int
    let reservationInfo: String
    let cost: Double
    let isCompleted: Bool
    let isAutomaticCompletionOverridden: Bool?
    let sortOrder: Int
    let media: [MediaRecord]

    init(_ item: ItineraryItem, includeMedia: Bool = true, includeLocalMediaIdentifiers: Bool = true) {
        id = item.id
        title = item.title
        categoryRaw = item.categoryRaw
        startTime = item.startTime
        endTime = item.endTime
        address = item.address
        note = item.note
        transportRaw = item.transportRaw
        distanceText = item.distanceText
        playDurationMinutes = item.playDurationMinutes
        reservationInfo = item.reservationInfo
        cost = item.cost
        isCompleted = item.isCompleted
        isAutomaticCompletionOverridden = item.isAutomaticCompletionOverridden
        sortOrder = item.sortOrder
        media = includeMedia
            ? item.media.sorted { $0.sortOrder < $1.sortOrder }.map {
                MediaRecord($0, includeLocalIdentifier: includeLocalMediaIdentifiers)
            }
            : []
    }

    func makeModel(day: TripDay) -> ItineraryItem {
        let category = PlaceCategory.resolved(rawValue: categoryRaw)
        let item = ItineraryItem(title: title, category: category, startTime: startTime, endTime: endTime, sortOrder: sortOrder)
        item.id = id
        item.categoryRaw = category.rawValue
        item.address = address
        item.note = note
        item.transportRaw = transportRaw
        item.distanceText = distanceText
        item.playDurationMinutes = playDurationMinutes
        item.reservationInfo = reservationInfo
        item.cost = cost
        item.isCompleted = isCompleted
        item.isAutomaticCompletionOverridden = isAutomaticCompletionOverridden ?? false
        item.day = day
        for mediaRecord in media {
            let reference = mediaRecord.makeModel()
            reference.itineraryItem = item
            item.media.append(reference)
        }
        return item
    }
}

private struct StoryRecord: Codable {
    let id: UUID
    let title: String
    let destination: String
    let startDate: Date
    let endDate: Date
    let summary: String
    let createdAt: Date
    let sourceTripID: UUID?
    let syncScopeRaw: String
    let sourceSelectionIDsRaw: String
    let days: [StoryDayRecord]
    let entries: [StoryEntryRecord]

    init(
        _ story: TravelStory,
        selectedDay: StoryDay? = nil,
        includeMedia: Bool = true,
        includeSourceLinks: Bool = true,
        includeLocalMediaIdentifiers: Bool = true
    ) {
        id = story.id
        title = selectedDay.map { day in
            day.title.isEmpty ? story.title : "\(story.title) · \(day.title)"
        } ?? story.title
        destination = story.destination
        startDate = selectedDay?.date ?? story.startDate
        endDate = selectedDay?.date ?? story.endDate
        summary = selectedDay?.note ?? story.summary
        createdAt = story.createdAt
        sourceTripID = includeSourceLinks ? story.sourceTripID : nil
        syncScopeRaw = includeSourceLinks ? story.syncScopeRaw : StorySyncScope.trip.rawValue
        sourceSelectionIDsRaw = includeSourceLinks ? story.sourceSelectionIDsRaw : ""
        let relevantDays = selectedDay.map { [$0] } ?? story.sortedDays
        days = relevantDays.map { StoryDayRecord($0, includeSourceLinks: includeSourceLinks) }

        var allEntries = story.entries.filter { entry in
            selectedDay == nil || entry.storyDay?.id == selectedDay?.id
        }
        let knownIDs = Set(allEntries.map(\.id))
        allEntries.append(contentsOf: relevantDays.flatMap(\.entries).filter { !knownIDs.contains($0.id) })
        entries = allEntries.sorted { lhs, rhs in
            if lhs.storyDay?.sortOrder == rhs.storyDay?.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return (lhs.storyDay?.sortOrder ?? .max) < (rhs.storyDay?.sortOrder ?? .max)
        }.map {
            StoryEntryRecord(
                $0,
                includeMedia: includeMedia,
                includeSourceLinks: includeSourceLinks,
                includeLocalMediaIdentifiers: includeLocalMediaIdentifiers
            )
        }
    }

    func makeModel(preserveSourceLinks: Bool = true) -> TravelStory {
        let story = TravelStory(
            title: title,
            destination: destination,
            startDate: startDate,
            endDate: endDate,
            summary: summary
        )
        story.id = id
        story.createdAt = createdAt
        story.sourceTripID = preserveSourceLinks ? sourceTripID : nil
        story.syncScopeRaw = preserveSourceLinks ? syncScopeRaw : StorySyncScope.trip.rawValue
        story.sourceSelectionIDsRaw = preserveSourceLinks ? sourceSelectionIDsRaw : ""

        var daysByID: [UUID: StoryDay] = [:]
        for dayRecord in days {
            let day = dayRecord.makeModel(story: story, preserveSourceLinks: preserveSourceLinks)
            daysByID[day.id] = day
            story.days.append(day)
        }
        for entryRecord in entries {
            let entry = entryRecord.makeModel(story: story, preserveSourceLinks: preserveSourceLinks)
            story.entries.append(entry)
            if let storyDayID = entryRecord.storyDayID, let day = daysByID[storyDayID] {
                entry.storyDay = day
                day.entries.append(entry)
            }
        }
        return story
    }
}

private struct StoryDayRecord: Codable {
    let id: UUID
    let date: Date
    let title: String
    let note: String
    let details: String
    let didMigrateInlineSummary: Bool
    let sortOrder: Int
    let sourceDayID: UUID?

    init(_ day: StoryDay, includeSourceLinks: Bool = true) {
        id = day.id
        date = day.date
        title = day.title
        note = day.note
        details = day.details
        didMigrateInlineSummary = day.didMigrateInlineSummary
        sortOrder = day.sortOrder
        sourceDayID = includeSourceLinks ? day.sourceDayID : nil
    }

    func makeModel(story: TravelStory, preserveSourceLinks: Bool = true) -> StoryDay {
        let day = StoryDay(
            date: date,
            title: title,
            sortOrder: sortOrder,
            sourceDayID: preserveSourceLinks ? sourceDayID : nil,
            story: story
        )
        day.id = id
        day.note = note
        day.details = details
        day.didMigrateInlineSummary = didMigrateInlineSummary
        return day
    }
}

private struct StoryEntryRecord: Codable {
    let id: UUID
    let title: String
    let categoryRaw: String
    let startTime: Date?
    let endTime: Date?
    let timeLabel: String
    let address: String
    let supplementalInfo: String?
    let note: String
    let transportRaw: String?
    let routeInfo: String
    let cost: Double?
    let didPrefillSourceMemory: Bool?
    let sourceMemoryPrefill: String?
    let sortOrder: Int
    let sourceItemID: UUID?
    let storyDayID: UUID?
    let media: [MediaRecord]

    init(
        _ entry: StoryEntry,
        includeMedia: Bool = true,
        includeSourceLinks: Bool = true,
        includeLocalMediaIdentifiers: Bool = true
    ) {
        id = entry.id
        title = entry.title
        categoryRaw = entry.categoryRaw
        startTime = entry.startTime
        endTime = entry.endTime
        timeLabel = entry.timeLabel
        address = entry.address
        supplementalInfo = entry.supplementalInfo
        note = entry.note
        transportRaw = entry.transportRaw
        routeInfo = entry.routeInfo
        cost = entry.cost
        didPrefillSourceMemory = entry.didPrefillSourceMemory
        sourceMemoryPrefill = entry.sourceMemoryPrefill
        sortOrder = entry.sortOrder
        sourceItemID = includeSourceLinks ? entry.sourceItemID : nil
        storyDayID = entry.storyDay?.id
        media = includeMedia
            ? entry.sortedMedia.map { MediaRecord($0, includeLocalIdentifier: includeLocalMediaIdentifiers) }
            : []
    }

    func makeModel(story: TravelStory, preserveSourceLinks: Bool = true) -> StoryEntry {
        let category = PlaceCategory.resolved(rawValue: categoryRaw)
        let entry = StoryEntry(title: title, category: category, sortOrder: sortOrder)
        entry.id = id
        entry.categoryRaw = category.rawValue
        entry.startTime = startTime
        entry.endTime = endTime
        entry.timeLabel = timeLabel
        entry.address = address
        entry.supplementalInfo = supplementalInfo ?? ""
        entry.note = note
        entry.transportRaw = transportRaw ?? TransportMode.car.rawValue
        entry.routeInfo = routeInfo
        entry.cost = cost ?? 0
        entry.didPrefillSourceMemory = didPrefillSourceMemory ?? false
        entry.sourceMemoryPrefill = sourceMemoryPrefill
        entry.sourceItemID = preserveSourceLinks ? sourceItemID : nil
        entry.story = story
        for mediaRecord in media {
            let reference = mediaRecord.makeModel()
            reference.storyEntry = entry
            entry.media.append(reference)
        }
        return entry
    }
}

private struct MediaRecord: Codable {
    let id: UUID
    let localIdentifier: String
    let kindRaw: String
    let caption: String
    let createdAt: Date
    let sortOrder: Int

    init(_ reference: MediaReference, includeLocalIdentifier: Bool = true) {
        id = reference.id
        localIdentifier = includeLocalIdentifier ? reference.localIdentifier : ""
        kindRaw = reference.kindRaw
        caption = reference.caption
        createdAt = reference.createdAt
        sortOrder = reference.sortOrder
    }

    func makeModel() -> MediaReference {
        let kind = MediaKind(rawValue: kindRaw) ?? .image
        let reference = MediaReference(localIdentifier: localIdentifier, kind: kind, sortOrder: sortOrder)
        reference.id = id
        reference.kindRaw = kindRaw
        reference.caption = caption
        reference.createdAt = createdAt
        return reference
    }
}
