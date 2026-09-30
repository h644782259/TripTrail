import XCTest
import SwiftData
@testable import TripTrail

@MainActor
final class CloudSyncTests: XCTestCase {
    func testSharedMediaPathAllowsOriginalRecordAndRejectsUnsafePaths() {
        let path = UUID().uuidString.lowercased() + "/" + String(repeating: "a", count: 64) + ".jpg"
        XCTAssertTrue(CloudJSON.isValidMediaPath(path))
        XCTAssertFalse(CloudJSON.isValidMediaPath("../" + path))
        XCTAssertFalse(CloudJSON.isValidMediaPath(path + "?redirect=1"))
        XCTAssertFalse(CloudJSON.isValidMediaPath("invalid/hash.jpg"))
    }

    func testMissingCloudMediaIsDownloadedAgainWithoutRevisionChange() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let source = try ModelContainer(for: Trip.self, TripDay.self, ItineraryItem.self, MediaReference.self, TravelStory.self, StoryDay.self, StoryEntry.self, configurations: configuration)
        let favorite = ItineraryItem(title: "媒体恢复", category: .attraction, startTime: Date(), endTime: Date(), sortOrder: 0)
        favorite.isFavorite = true
        favorite.media = [MediaReference(localIdentifier: "missing-original", kind: .image)]
        source.mainContext.insert(favorite)
        try source.mainContext.save()
        let record = try XCTUnwrap(CloudRecordAdapter.records(source.mainContext).first)
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        // Reused media is stored under the original record, not the receiving favorite.
        let path = UUID().uuidString.lowercased() + "/" + CloudJSON.digest(bytes) + ".png"
        let payload = CloudJSON.transform(try JSONSerialization.jsonObject(with: record.data)) {
            var value = $0; value["cloudPath"] = path; value["localIdentifier"] = ""; return value
        }
        let response = try JSONSerialization.data(withJSONObject: [["id": record.id.uuidString, "kind": record.kind, "title": record.title, "payload": payload, "revision": 1]])
        var downloads = 0
        CloudStubURLProtocol.handler = { request in
            if request.url!.path.contains("triptrail_deleted_records") { return (200, Data("[]".utf8)) }
            if request.url!.path.contains("storage/v1/object") { downloads += 1; return (200, bytes) }
            return (200, response)
        }
        defer { CloudStubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CloudStubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let suite = "CloudMediaRepair-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = CloudSyncService(defaults: defaults, session: session, publicKeyOverride: "test-key")
        let target = try ModelContainer(for: Trip.self, TripDay.self, ItineraryItem.self, MediaReference.self, TravelStory.self, StoryDay.self, StoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        await cloud.sync(context: target.mainContext)
        let received = try XCTUnwrap(CloudRecordAdapter.records(target.mainContext).first)
        let file = try XCTUnwrap(PhotoLibraryService.localFile(try XCTUnwrap(received.media.first).localIdentifier))
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(downloads, 1)
        XCTAssertNotNil(PhotoLibraryService.localImage(file))
        try FileManager.default.removeItem(at: file)
        await cloud.sync(context: target.mainContext)
        XCTAssertEqual(downloads, 2)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(try CloudRecordAdapter.records(target.mainContext).count, 1)
    }

    func testOfflineAndConcurrentDecisionMatrix() {
        XCTAssertEqual(CloudSyncDecision.choose(localChanged: true, baseRevision: 0, remoteRevision: nil), .upload)
        XCTAssertEqual(CloudSyncDecision.choose(localChanged: true, baseRevision: 3, remoteRevision: 3), .upload)
        XCTAssertEqual(CloudSyncDecision.choose(localChanged: false, baseRevision: 3, remoteRevision: 4), .download)
        XCTAssertEqual(CloudSyncDecision.choose(localChanged: true, baseRevision: 3, remoteRevision: 4), .conflict)
        XCTAssertEqual(CloudSyncDecision.choose(localChanged: false, baseRevision: 3, remoteRevision: nil), .missing)
        XCTAssertEqual(CloudSyncDecision.choose(localChanged: false, baseRevision: 3, remoteRevision: 3), .unchanged)
    }
    func testLocalMediaPathDoesNotCreateFalseEdits() throws {
        let first = Data(#"{"media":[{"id":"a","localIdentifier":"photos:one","caption":"旅途"}]}"#.utf8)
        let second = Data(#"{"media":[{"caption":"旅途","id":"a","localIdentifier":"file:///cache/two.jpg","cloudPath":"abc/hash.jpg"}]}"#.utf8)
        XCTAssertEqual(try CloudJSON.fingerprint(first), try CloudJSON.fingerprint(second))
        let edited = Data(#"{"media":[{"id":"a","localIdentifier":"photos:one","caption":"新的说明"}]}"#.utf8)
        XCTAssertNotEqual(try CloudJSON.fingerprint(first), try CloudJSON.fingerprint(edited))
    }
    func testCloudRecordRejectsMismatchedIDAndUnknownKind() throws {
        let id = UUID().uuidString
        XCTAssertThrowsError(try CloudRemoteRecord(["id": id, "kind": "trip", "revision": 1, "payload": ["id": UUID().uuidString]]))
        XCTAssertThrowsError(try CloudRemoteRecord(["id": id, "kind": "unknown", "revision": 1, "payload": ["id": id]]))
    }
    func testApplyOneTripKeepsOtherTripsAndTopLevelIdentity() throws {
        let container = try ModelContainer(for: Trip.self, TripDay.self, ItineraryItem.self, MediaReference.self, TravelStory.self, StoryDay.self, StoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let old = Trip(title: "原旅程", destination: "杭州", startDate: date, endDate: date)
        let untouched = Trip(title: "仅本地", destination: "成都", startDate: date, endDate: date)
        context.insert(old); context.insert(untouched)
        let day = TripDay(date: date, title: "第一天", sortOrder: 0, trip: old)
        old.days = [day]
        let item = ItineraryItem(title: "西湖", category: .attraction, startTime: date, endTime: date.addingTimeInterval(3600), sortOrder: 0)
        item.isFixedTime = true; item.day = day; day.items = [item]
        try context.save()
        let snapshot = try XCTUnwrap(CloudRecordAdapter.records(context).first { $0.id == old.id })
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any])
        object["title"] = "来自 Android 的编辑"
        try CloudRecordAdapter.apply(JSONSerialization.data(withJSONObject: object), kind: "trip", context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Trip>()), 2)
        XCTAssertEqual(old.title, "来自 Android 的编辑")
        XCTAssertEqual(untouched.title, "仅本地")
        XCTAssertEqual(old.days.count, 1)
        XCTAssertEqual(old.allItems.count, 1)
        XCTAssertTrue(old.allItems[0].isFixedTime)
        XCTAssertEqual(old.allItems[0].title, "西湖")
    }
    func testStoryAndFavoriteApplyPreserveLocalRecordsAndMedia() throws {
        let container = try ModelContainer(for: Trip.self, TripDay.self, ItineraryItem.self, MediaReference.self, TravelStory.self, StoryDay.self, StoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let story = TravelStory(title: "足迹", destination: "杭州", startDate: date, endDate: date, summary: "原摘要")
        context.insert(story)
        let favorite = ItineraryItem(title: "收藏", category: .restaurant, startTime: date, endTime: date.addingTimeInterval(3600), sortOrder: 0)
        favorite.isFavorite = true; favorite.note = "保留备注"
        context.insert(favorite); try context.save()
        for kind in ["story", "favorite"] {
            let record = try XCTUnwrap(CloudRecordAdapter.records(context).first { $0.kind == kind })
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: record.data) as? [String: Any])
            object["title"] = kind + " 云端编辑"
            let payload = try JSONSerialization.data(withJSONObject: object)
            try CloudRecordAdapter.apply(payload, kind: kind, context: context)
            try CloudRecordAdapter.apply(payload, kind: kind, context: context)
        }
        XCTAssertEqual(story.title, "story 云端编辑")
        XCTAssertEqual(story.summary, "原摘要")
        XCTAssertEqual(favorite.title, "favorite 云端编辑")
        XCTAssertEqual(favorite.note, "保留备注")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TravelStory>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ItineraryItem>()), 1)
    }


    func testAutomaticDiscoveryLoadsAllKindsAndKeepsLocalCopiesOffline() async throws {
        let source = try ModelContainer(for: Trip.self, TripDay.self, ItineraryItem.self, MediaReference.self, TravelStory.self, StoryDay.self, StoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let date = Date()
        source.mainContext.insert(Trip(title: "共享旅程", destination: "测试", startDate: date, endDate: date))
        source.mainContext.insert(TravelStory(title: "共享足迹", destination: "测试", startDate: date, endDate: date, summary: "云端"))
        let favorite = ItineraryItem(title: "共享收藏", category: .restaurant, startTime: date, endTime: date, sortOrder: 0)
        favorite.isFavorite = true; source.mainContext.insert(favorite)
        try source.mainContext.save()
        let records = try CloudRecordAdapter.records(source.mainContext)
        let rows: [[String: Any]] = try records.map { record in
            ["id": record.id.uuidString, "kind": record.kind, "title": record.title, "payload": try JSONSerialization.jsonObject(with: record.data), "revision": 1]
        }
        let response = try JSONSerialization.data(withJSONObject: rows)
        var requestCount = 0
        var offline = false
        CloudStubURLProtocol.handler = { request in
            if request.url!.path.contains("triptrail_deleted_records") { return (200, Data("[]".utf8)) }
            requestCount += 1
            return (offline ? 503 : 200, response)
        }
        defer { CloudStubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CloudStubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let suite = "CloudDiscoveryTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = CloudSyncService(defaults: defaults, session: session, publicKeyOverride: "test-key")
        let target = try ModelContainer(for: Trip.self, TripDay.self, ItineraryItem.self, MediaReference.self, TravelStory.self, StoryDay.self, StoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        await cloud.sync(context: target.mainContext, automatic: true)
        XCTAssertEqual(try CloudRecordAdapter.records(target.mainContext).count, 3)
        XCTAssertEqual(cloud.bindings.count, 3)
        XCTAssertEqual(requestCount, 1)
        await cloud.sync(context: target.mainContext, automatic: true)
        XCTAssertEqual(requestCount, 1, "Repeated opening should use the navigation throttle")
        offline = true
        await cloud.sync(context: target.mainContext)
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(try CloudRecordAdapter.records(target.mainContext).count, 3)
        XCTAssertTrue(cloud.message.contains("本地"))
    }

    func testAutomaticDiscoveryDoesNotReplaceIndependentLocalRecord() async throws {
        let target = try ModelContainer(for: Trip.self, TripDay.self, ItineraryItem.self, MediaReference.self, TravelStory.self, StoryDay.self, StoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let date = Date()
        let trip = Trip(title: "本地编辑", destination: "本地", startDate: date, endDate: date)
        target.mainContext.insert(trip); try target.mainContext.save()
        let record = try XCTUnwrap(CloudRecordAdapter.records(target.mainContext).first)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: record.data) as? [String: Any])
        payload["title"] = "云端标题"
        let response = try JSONSerialization.data(withJSONObject: [["id": trip.id.uuidString, "kind": "trip", "title": "云端标题", "payload": payload, "revision": 2]])
        CloudStubURLProtocol.handler = { request in (200, request.url!.path.contains("triptrail_deleted_records") ? Data("[]".utf8) : response) }
        defer { CloudStubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CloudStubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let suite = "CloudCollisionTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = CloudSyncService(defaults: defaults, session: session, publicKeyOverride: "test-key")
        await cloud.sync(context: target.mainContext, kind: "trip", automatic: true)
        XCTAssertEqual(trip.title, "本地编辑")
        XCTAssertFalse(cloud.linked(record.key))
    }

    func testRecycleOfflineRestartCrossDeviceDeletionAndRestore() async throws {
        func container() throws -> ModelContainer {
            try ModelContainer(for: Trip.self, TripDay.self, ItineraryItem.self, MediaReference.self, TravelStory.self, StoryDay.self, StoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        let source = try container(); let date = Date()
        source.mainContext.insert(Trip(title: "可恢复旅程", destination: "测试", startDate: date, endDate: date))
        source.mainContext.insert(TravelStory(title: "可恢复足迹", destination: "测试", startDate: date, endDate: date, summary: "回忆"))
        let favorite = ItineraryItem(title: "可恢复收藏", category: .restaurant, startTime: date, endTime: date, sortOrder: 0)
        favorite.isFavorite = true; source.mainContext.insert(favorite); try source.mainContext.save()
        let records = try CloudRecordAdapter.records(source.mainContext)
        var deleted: Set<String> = []; var offline = false; var writes = 0
        CloudStubURLProtocol.handler = { request in
            if offline { return (503, Data("{}".utf8)) }
            let path = request.url!.path
            if path.contains("triptrail_trash_record") || path.contains("triptrail_restore_record") {
                var body = request.httpBody ?? Data()
                if body.isEmpty, let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(buffer, count: count) }
                }
                let object = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
                let id = (object["record_id"] as! String).lowercased()
                if path.contains("trash_record") { deleted.insert(id) } else { deleted.remove(id) }
                return (200, Data("null".utf8))
            }
            if path.contains("triptrail_save_record") { writes += 1; return (410, Data("{}".utf8)) }
            if path.contains("triptrail_deleted_records") {
                let rows: [[String: Any]] = records.filter { deleted.contains($0.id.uuidString.lowercased()) }.map {
                    ["id": $0.id.uuidString, "kind": $0.kind, "title": $0.title, "expires_at_ms": Date().addingTimeInterval(86400).timeIntervalSince1970 * 1000]
                }
                return (200, try! JSONSerialization.data(withJSONObject: rows))
            }
            let rows: [[String: Any]] = records.filter { !deleted.contains($0.id.uuidString.lowercased()) }.map {
                ["id": $0.id.uuidString, "kind": $0.kind, "title": $0.title, "revision": 2, "payload": try! JSONSerialization.jsonObject(with: $0.data)]
            }
            return (200, try! JSONSerialization.data(withJSONObject: rows))
        }
        defer { CloudStubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CloudStubURLProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let suiteA = "RecycleA-" + UUID().uuidString; let suiteB = "RecycleB-" + UUID().uuidString
        let defaultsA = UserDefaults(suiteName: suiteA)!; let defaultsB = UserDefaults(suiteName: suiteB)!
        defer { defaultsA.removePersistentDomain(forName: suiteA); defaultsB.removePersistentDomain(forName: suiteB) }
        let a = CloudSyncService(defaults: defaultsA, session: session, publicKeyOverride: "test")
        let b = CloudSyncService(defaults: defaultsB, session: session, publicKeyOverride: "test")
        let deviceA = try container(); let deviceB = try container()
        await a.sync(context: deviceA.mainContext); await b.sync(context: deviceB.mainContext)
        XCTAssertEqual(try CloudRecordAdapter.records(deviceA.mainContext).count, 3)
        offline = true
        for record in records { XCTAssertTrue(a.trash(id: record.id, kind: record.kind, context: deviceA.mainContext)) }
        await a.uploadPending(context: deviceA.mainContext)
        await Task.yield()
        await a.uploadPending(context: deviceA.mainContext)
        XCTAssertTrue(a.recycle.allSatisfy(\.pending))
        XCTAssertEqual(try CloudRecordAdapter.records(deviceA.mainContext).count, 0)
        let restarted = CloudSyncService(defaults: defaultsA, session: session, publicKeyOverride: "test")
        XCTAssertEqual(restarted.recycle.count, 3)
        offline = false
        await restarted.sync(context: deviceA.mainContext)
        XCTAssertEqual(deleted.count, 3)
        await b.sync(context: deviceB.mainContext)
        XCTAssertEqual(try CloudRecordAdapter.records(deviceB.mainContext).count, 0)
        XCTAssertEqual(b.recycle.count, 3)
        XCTAssertEqual(writes, 0, "Stale snapshots must not be uploaded after deletion")
        for entry in b.recycle { await b.restore(entry, context: deviceB.mainContext) }
        XCTAssertEqual(try CloudRecordAdapter.records(deviceB.mainContext).count, 3)
        await restarted.sync(context: deviceA.mainContext)
        XCTAssertEqual(try CloudRecordAdapter.records(deviceA.mainContext).count, 3)
        XCTAssertTrue(restarted.recycle.isEmpty)
    }

    func testLocalRecycleRestoresWithoutCloudAndRejectsExpiry() async throws {
        let container = try ModelContainer(for: Trip.self, TripDay.self, ItineraryItem.self, MediaReference.self, TravelStory.self, StoryDay.self, StoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext; let date = Date()
        let trip = Trip(title: "本地恢复", destination: "上海", startDate: date, endDate: date)
        context.insert(trip); try context.save()
        let suite = "LocalRecycle-" + UUID().uuidString; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = CloudSyncService(defaults: defaults, publicKeyOverride: "")
        XCTAssertTrue(cloud.trash(id: trip.id, kind: "trip", context: context))
        let entry = try XCTUnwrap(cloud.recycle.first)
        var expired = entry; expired.expiresAt = Date().addingTimeInterval(-1)
        await cloud.restore(expired, context: context)
        XCTAssertEqual(try CloudRecordAdapter.records(context).count, 0)
        await cloud.restore(entry, context: context)
        XCTAssertEqual(try CloudRecordAdapter.records(context).first?.title, "本地恢复")
        XCTAssertTrue(cloud.recycle.isEmpty)
    }

    // Explicit opt-in marker in the simulator sandbox; never runs against cloud during normal tests.
    func testLiveCloudBackupVersionRestoreAndDelete() async throws {
        let marker = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(".cloud-live-test")
        guard FileManager.default.fileExists(atPath: marker.path) else { throw XCTSkip("Live cloud test is opt-in") }
        defer { try? FileManager.default.removeItem(at: marker) }
        let source = try ModelContainer(for: Trip.self, TripDay.self, ItineraryItem.self, MediaReference.self, TravelStory.self, StoryDay.self, StoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let date = Date()
        let trip = Trip(title: "备份集成测试", destination: "测试", startDate: date, endDate: date)
        source.mainContext.insert(trip)
        let story = TravelStory(title: "备份测试足迹", destination: "测试", startDate: date, endDate: date, summary: "快照")
        source.mainContext.insert(story)
        let favorite = ItineraryItem(title: "备份测试收藏", category: .restaurant, startTime: date, endTime: date.addingTimeInterval(3600), sortOrder: 0)
        favorite.isFavorite = true
        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        try png.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }
        favorite.media = [MediaReference(localIdentifier: imageURL.absoluteString, kind: .image)]
        source.mainContext.insert(favorite)
        try source.mainContext.save()
        let package = try await DataBackupService.makeBackupPackage(from: source.mainContext)
        defer { try? FileManager.default.removeItem(at: package.url) }
        XCTAssertEqual(package.mediaCount, 1)
        XCTAssertTrue(package.skippedMedia.isEmpty)
        var created: [CloudBackupVersion] = []
        do {
            let firstID = try await CloudBackupService.upload(package.url)
            let firstVersions = try await CloudBackupService.list()
            let first = try XCTUnwrap(firstVersions.first { $0.id == firstID })
            created.append(first)
            let secondID = try await CloudBackupService.upload(package.url)
            let secondVersions = try await CloudBackupService.list()
            let second = try XCTUnwrap(secondVersions.first { $0.id == secondID })
            created.append(second)
            XCTAssertNotEqual(first.id, second.id)
            XCTAssertTrue(first.ready)
            let downloaded = try await CloudBackupService.download(first)
            defer { try? FileManager.default.removeItem(at: downloaded) }
            let destination = try ModelContainer(for: Trip.self, TripDay.self, ItineraryItem.self, MediaReference.self, TravelStory.self, StoryDay.self, StoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let result = try await DataBackupService.restoreBackup(from: downloaded, into: destination.mainContext)
            XCTAssertEqual(result.tripCount, 1)
            XCTAssertEqual(result.storyCount, 1)
            XCTAssertEqual(result.favoriteCount, 1)
            XCTAssertEqual(result.mediaReferenceCount, 1)
            let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<ItineraryItem>()).first)
            let media = try XCTUnwrap(restored.media.first)
            let exportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: exportDirectory) }
            let original = try await PhotoLibraryService.exportOriginal(identifier: media.localIdentifier, kind: media.kind, referenceID: media.id, to: exportDirectory)
            XCTAssertEqual(try Data(contentsOf: original.fileURL), png)
            let corrupt = CloudBackupVersion(id: first.id, created_at: first.created_at, object_path: first.object_path, bytes: first.bytes, deleting: false, ready: true, sha256: String(repeating: "0", count: 64), chunk_count: first.chunk_count)
            do {
                let invalid = try await CloudBackupService.download(corrupt)
                try? FileManager.default.removeItem(at: invalid)
                XCTFail("Checksum mismatch must reject the backup")
            } catch { XCTAssertTrue(error.localizedDescription.contains("校验失败")) }
        } catch {
            for version in created { try? await CloudBackupService.delete(version) }
            throw error
        }
        for version in created { try await CloudBackupService.delete(version) }
        let after = try await CloudBackupService.list()
        XCTAssertFalse(after.contains { row in created.contains { $0.id == row.id } })
    }


}


private final class CloudStubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { return }
        let (code, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
