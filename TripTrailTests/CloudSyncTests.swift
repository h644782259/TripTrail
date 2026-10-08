import XCTest
import SwiftData
import SwiftUI
@testable import TripTrail

@MainActor
final class CloudSyncTests: XCTestCase {
    func testConcurrentInsertionsMergeRelativeOrderWithoutIndexConflicts() {
        func items(_ ids: [String]) -> [[String: Any]] { ids.enumerated().map { ["id": $0.element, "sortOrder": $0.offset, "note": ""] } }
        let merged = CloudJSON.merge(base: items(["a", "b", "c"]), local: items(["a", "x", "b", "c"]), remote: items(["a", "b", "y", "c"]))
        XCTAssertTrue(merged.conflicts.isEmpty)
        let values = merged.value as! [[String: Any]]
        XCTAssertEqual(values.map { $0["id"] as! String }, ["a", "x", "b", "y", "c"])
        XCTAssertEqual(values.map { $0["sortOrder"] as! Int }, [0, 1, 2, 3, 4])
    }
    func testReorderAndRemoteContentEditBothSurvive() {
        let base: [[String: Any]] = [["id": "a", "sortOrder": 0, "note": "旧"], ["id": "b", "sortOrder": 1, "note": "旧"]]
        let local: [[String: Any]] = [["id": "b", "sortOrder": 0, "note": "旧"], ["id": "a", "sortOrder": 1, "note": "旧"]]
        let remote: [[String: Any]] = [["id": "a", "sortOrder": 0, "note": "新"], ["id": "b", "sortOrder": 1, "note": "旧"]]
        let merged = CloudJSON.merge(base: base, local: local, remote: remote)
        XCTAssertTrue(merged.conflicts.isEmpty)
        let values = merged.value as! [[String: Any]]
        XCTAssertEqual(values.map { $0["id"] as! String }, ["b", "a"])
        XCTAssertEqual(values[1]["note"] as? String, "新")
    }
    func testEmptyUneditedValuesMergeButExplicitClearConflicts() {
        XCTAssertTrue(CloudJSON.merge(base: nil, local: "", remote: "信息").conflicts.isEmpty)
        XCTAssertEqual(CloudJSON.merge(base: NSNull(), local: "信息", remote: " ").value as? String, "信息")
        XCTAssertEqual(CloudJSON.merge(base: "原内容", local: "", remote: "原内容").value as? String, "")
        XCTAssertFalse(CloudJSON.merge(base: "原内容", local: "", remote: "新内容").conflicts.isEmpty)
    }
    func testIndividualConflictChoicesPreserveIndependentChanges() {
        let merged = CloudJSON.merge(base: ["note": "旧", "title": "旧", "city": ""], local: ["note": "本地", "title": "本地", "city": "上海"], remote: ["note": "云端", "title": "云端", "city": ""], remoteChoices: ["/note"])
        let value = merged.value as? [String: String]
        XCTAssertEqual(value?["note"], "云端")
        XCTAssertEqual(value?["title"], "本地")
        XCTAssertEqual(value?["city"], "上海")
    }

    func testConflictDiffMatchesStableIDsAndOmitsStorageMetadata() throws {
        let remote: [String: Any] = ["id": "trip", "title": "旅程", "days": [["id": "DAY", "title": "当天", "items": [["id": "A", "title": "安排A", "note": "云端说明"], ["id": "B", "title": "安排B", "note": "相同"]]]], "media": [["id": "M", "kindRaw": "image", "sortOrder": 0, "localIdentifier": "remote", "cloudPath": "path"]]]
        let local: [String: Any] = ["id": "trip", "title": "旅程", "days": [["id": "day", "title": "当天", "items": [["id": "b", "title": "安排B", "note": "相同"], ["id": "a", "title": "安排A", "note": "本地说明"]]]], "media": [["id": "m", "kindRaw": "image", "sortOrder": 0, "localIdentifier": "device"]]]
        let rows = try CloudContentDifference.compare(cloud: JSONSerialization.data(withJSONObject: remote), local: JSONSerialization.data(withJSONObject: local))
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].label.contains("安排A"))
        XCTAssertEqual(rows[0].cloud, "云端说明")
        XCTAssertEqual(rows[0].local, "本地说明")
    }

    func testConflictDetailsIncludesCoordinatesAndCoverWithoutStoragePaths() throws {
        let remote: [String: Any] = ["id": "trip", "latitude": 38.4, "coverMedia": ["id": "cover-a", "cloudPath": "secret"]]
        let local: [String: Any] = ["id": "trip", "latitude": 39.4, "coverMedia": ["id": "cover-b", "localIdentifier": "device"]]
        let rows = try CloudContentDifference.compare(cloud: JSONSerialization.data(withJSONObject: remote), local: JSONSerialization.data(withJSONObject: local))
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.contains { $0.label.contains("纬度") })
        XCTAssertTrue(rows.contains { $0.label.contains("封面") && $0.cloud == "云端封面" })
        XCTAssertFalse(rows.contains { $0.cloud.contains("secret") || $0.local.contains("cover-b") })
    }

    func testCloudLibraryRenderingDoesNotSaveOrCreateJourneyAdapters() throws {
        let container = try ModelContainer(for: Trip.self, TripDay.self, ItineraryItem.self, MediaReference.self, TravelStory.self, StoryDay.self, StoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let now = Date()
        let trip = Trip(title: "列表旅程", destination: "宁夏", startDate: now, endDate: now)
        context.insert(trip)
        try context.save()
        for _ in 0..<20 {
            _ = CloudLibraryEntry.entries(trips: [trip], items: [], kind: "trip")
            _ = CloudLibraryEntry.entries(trips: [trip], items: [], kind: "story")
        }
        XCTAssertFalse(context.hasChanges)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TravelStory>()).isEmpty)
    }

    func testScopedBlankDayDeletionPreservesSiblingDraftAndRemoteChanges() throws {
        let base: [String: Any] = ["id": "trip", "endDate": 2, "days": [["id": "first", "date": 1, "sortOrder": 0, "note": "saved", "items": []], ["id": "blank", "date": 2, "sortOrder": 1, "items": []]]]
        let current: [String: Any] = ["id": "trip", "endDate": 1, "days": [["id": "first", "date": 1, "sortOrder": 0, "note": "unsubmitted", "items": []]]]
        let selected = try XCTUnwrap(CloudJSON.scoped(base, current: current, id: "blank") as? [String: Any])
        XCTAssertFalse(CloudJSON.containsEntity(selected, id: "blank"))
        XCTAssertEqual(CloudJSON.findEntity(selected, id: "first")?["note"] as? String, "saved")
        XCTAssertEqual(selected["endDate"] as? Int, 1)
        var remote = base
        remote["days"] = [["id": "first", "date": 1, "sortOrder": 0, "note": "remote update", "items": []], ["id": "blank", "date": 2, "sortOrder": 1, "items": []]]
        let merged = CloudJSON.merge(base: base, local: selected, remote: remote)
        XCTAssertTrue(merged.conflicts.isEmpty)
        let received = try XCTUnwrap(merged.value)
        XCTAssertFalse(CloudJSON.containsEntity(received, id: "blank"))
        XCTAssertEqual(CloudJSON.findEntity(received, id: "first")?["note"] as? String, "remote update")
    }

    func testPhotoDisplayOrderIsStableWhenRelationshipArrivalOrderChanges() {
        let a = MediaReference(localIdentifier: "a", kind: .image, sortOrder: 0)
        let b = MediaReference(localIdentifier: "b", kind: .image, sortOrder: 0)
        a.createdAt = Date(timeIntervalSince1970: 1); b.createdAt = a.createdAt
        a.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        b.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        XCTAssertEqual([b, a].sorted(by: MediaReference.precedes).map(\.id), [a, b].sorted(by: MediaReference.precedes).map(\.id))
    }
    func testEditorKeepsDraggedOrderAndAppendsNewPhotos() {
        let assets = ["a", "b", "c"].map { AssetMediaPreviewItem(identifier: $0, kind: .image) }
        let ordered = ReorderableMediaGrid<EmptyView, EmptyView>.ordered(assets, order: ["removed", "b", "a"])
        XCTAssertEqual(ordered.map(\.identifier), ["b", "a", "c"])
    }
    func testCollectionArrivalOrderIsNotAnEditButPhotoOrderIs() throws {
        let photos: [[String: Any]] = [["id": "a", "sortOrder": 0, "localIdentifier": "a"], ["id": "b", "sortOrder": 1, "localIdentifier": "b"]]
        let first = try JSONSerialization.data(withJSONObject: ["id": "trip", "media": photos])
        let reordered = try JSONSerialization.data(withJSONObject: ["id": "trip", "media": Array(photos.reversed())])
        XCTAssertEqual(try CloudJSON.fingerprint(first), try CloudJSON.fingerprint(reordered))
        var changed = photos; changed[0]["sortOrder"] = 1; changed[1]["sortOrder"] = 0
        XCTAssertNotEqual(try CloudJSON.fingerprint(first), try CloudJSON.fingerprint(JSONSerialization.data(withJSONObject: ["id": "trip", "media": changed])))
    }
    func testThreeWayMergeIndependentFieldsAndEntities() throws {
        let base: [String: Any] = ["id": "trip", "items": [["id": "a", "note": "old", "title": "old"], ["id": "b", "note": "old"]]]
        let local: [String: Any] = ["id": "trip", "items": [["id": "a", "note": "local", "title": "old"], ["id": "b", "note": "old"]]]
        let remote: [String: Any] = ["id": "trip", "items": [["id": "b", "note": "remote"], ["id": "a", "note": "old", "title": "remote title"]]]
        let result = CloudJSON.merge(base: base, local: local, remote: remote)
        XCTAssertTrue(result.conflicts.isEmpty)
        let a = try XCTUnwrap(CloudJSON.findEntity(result.value!, id: "a"))
        XCTAssertEqual(a["note"] as? String, "local")
        XCTAssertEqual(a["title"] as? String, "remote title")
        XCTAssertEqual(CloudJSON.findEntity(result.value!, id: "b")?["note"] as? String, "remote")
    }
    func testConflictChoicePreservesNonConflictingFields() throws {
        let base: [String: Any] = ["id": "a", "note": "old", "title": "old", "address": "old"]
        let local: [String: Any] = ["id": "a", "note": "local", "title": "local", "address": "old"]
        let remote: [String: Any] = ["id": "a", "note": "remote", "title": "old", "address": "remote"]
        for preferLocal in [true, false] {
            let result = CloudJSON.merge(base: base, local: local, remote: remote, preferLocal: preferLocal)
            XCTAssertEqual(result.conflicts, ["/note"])
            let value = try XCTUnwrap(result.value as? [String: Any])
            XCTAssertEqual(value["note"] as? String, preferLocal ? "local" : "remote")
            XCTAssertEqual(value["title"] as? String, "local")
            XCTAssertEqual(value["address"] as? String, "remote")
        }
    }
    func testThreeWayDeletionAndConcurrentMediaAddition() throws {
        let base: [String: Any] = ["id": "a", "note": "old"]
        let edited: [String: Any] = ["id": "a", "note": "new"]
        XCTAssertNil(CloudJSON.merge(base: base, local: nil, remote: base).value)
        XCTAssertFalse(CloudJSON.merge(base: base, local: nil, remote: edited).conflicts.isEmpty)
        let result = CloudJSON.merge(base: [] as [Any], local: [["id": "l", "localIdentifier": "device"]], remote: [["id": "r", "localIdentifier": "", "cloudPath": "remote"]])
        XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertEqual((result.value as? [Any])?.count, 2)
    }
    func testDayMetadataSaveDoesNotIncludePendingItemEdits() throws {
        let base: [String: Any] = ["id": "day", "title": "old", "note": "旧当天说明", "items": [["id": "a", "note": "old"]]]
        let local: [String: Any] = ["id": "day", "title": "new", "note": "新当天说明", "items": [["id": "a", "note": "pending"]]]
        let selected = try XCTUnwrap(CloudJSON.scoped(base, current: local, id: "day"))
        XCTAssertEqual(CloudJSON.findEntity(selected, id: "a")?["note"] as? String, "old")
        XCTAssertEqual((selected as? [String: Any])?["title"] as? String, "new")
        XCTAssertEqual((selected as? [String: Any])?["note"] as? String, "新当天说明")
        let selectedItem = try XCTUnwrap(CloudJSON.scoped(["id": "trip", "days": []], current: ["id": "trip", "days": [local]], id: "a"))
        XCTAssertEqual(CloudJSON.findEntity(selectedItem, id: "a")?["note"] as? String, "pending")
    }
    func testScopedSaveMergesCloudAndRetainsUnsubmittedSibling() async throws {
        let date = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        let target = try ModelContainer(for: Trip.self, TripDay.self, ItineraryItem.self, MediaReference.self, TravelStory.self, StoryDay.self, StoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let trip = Trip(title: "范围保存", destination: "旧城市", startDate: date, endDate: date)
        let day = TripDay(date: date, title: "当天", sortOrder: 0)
        let a = ItineraryItem(title: "安排 A", category: .restaurant, startTime: date, endTime: date.addingTimeInterval(3600), sortOrder: 0)
        let b = ItineraryItem(title: "安排 B", category: .restaurant, startTime: date, endTime: date.addingTimeInterval(3600), sortOrder: 1)
        let aID = a.id; let bID = b.id
        day.items = [a, b]; a.day = day; b.day = day; trip.days = [day]; day.trip = trip
        JourneyHierarchyService.normalizeTripDaySchedule(trip)
        target.mainContext.insert(trip); try target.mainContext.save()
        let original = try XCTUnwrap(CloudRecordAdapter.records(target.mainContext).first)
        let normalized = try JSONSerialization.jsonObject(with: CloudRecordAdapter.normalized(original.data, kind: "trip"))
        XCTAssertNotNil(CloudJSON.findEntity(normalized, id: aID.uuidString), "归一化不能丢失安排")
        var serverValue = try JSONSerialization.jsonObject(with: original.data) as! [String: Any]
        var revision = 1; var uploads = 0; var submitted: [String: Any]?
        CloudStubURLProtocol.handler = { request in
            if request.url!.path.contains("triptrail_deleted_records") { return (200, Data("[]".utf8)) }
            if request.url!.path.contains("triptrail_patch_record") || request.url!.path.contains("triptrail_save_record") {
                uploads += 1
                var bytes = request.httpBody ?? Data()
                if bytes.isEmpty, let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(buffer, count: count) }
                }
                let body = try! JSONSerialization.jsonObject(with: bytes) as! [String: Any]
                submitted = body["record_payload"] as? [String: Any]; serverValue = submitted!; revision += 1
                return (200, try! JSONSerialization.data(withJSONObject: ["id": trip.id.uuidString, "kind": "trip", "title": "范围保存", "revision": revision, "payload": serverValue]))
            }
            return (200, try! JSONSerialization.data(withJSONObject: [["id": trip.id.uuidString, "kind": "trip", "title": "范围保存", "revision": revision, "payload": serverValue]]))
        }
        defer { CloudStubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CloudStubURLProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let suite = "ScopedMerge-" + UUID().uuidString; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let initialBinding = CloudBinding(revision: 1, baseline: try original.fingerprint, origin: Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? "", payload: original.data, localPayload: original.data)
        defaults.set(try JSONEncoder().encode([original.key: initialBinding]), forKey: "cloud.relational.bindings")
        let cloud = CloudSyncService(defaults: defaults, session: session, publicKeyOverride: "test-key")
        // The fixture starts from a shared, already synchronized version.

        let items = try target.mainContext.fetch(FetchDescriptor<ItineraryItem>())
        items.first { $0.id == aID }!.note = "A 主动保存"
        items.first { $0.id == bID }!.note = "B 尚未提交"
        var remoteB = CloudJSON.findEntity(serverValue, id: bID.uuidString)!; remoteB["note"] = "B 云端修改"
        // Change only B on the other device; A must save without uploading B's pending local edit.
        var cloudFresh = serverValue
        var days = cloudFresh["days"] as! [[String: Any]]
        var cloudItems = days[0]["items"] as! [[String: Any]]
        cloudItems = cloudItems.map { ($0["id"] as? String)?.lowercased() == bID.uuidString.lowercased() ? remoteB : $0 }
        days[0]["items"] = cloudItems; cloudFresh["days"] = days; cloudFresh["destination"] = "云端城市"
        serverValue = cloudFresh; revision += 1
        let currentValue = try JSONSerialization.jsonObject(with: CloudRecordAdapter.records(target.mainContext).first!.data)
        let selectedValue = CloudJSON.scoped(try JSONSerialization.jsonObject(with: original.data), current: currentValue, id: aID.uuidString)!
        XCTAssertEqual(CloudJSON.findEntity(selectedValue, id: aID.uuidString)?["note"] as? String, "A 主动保存", "构建保存范围")
        let remoteValue = try JSONSerialization.jsonObject(with: CloudRecordAdapter.normalized(JSONSerialization.data(withJSONObject: cloudFresh), kind: "trip"))
        let mergedValue = CloudJSON.merge(base: try JSONSerialization.jsonObject(with: original.data), local: selectedValue, remote: remoteValue)
        XCTAssertNotNil(CloudJSON.findEntity(mergedValue.value!, id: aID.uuidString), "构建合并结果")
        await cloud.uploadPending(context: target.mainContext, key: original.key, entityID: aID)
        XCTAssertEqual(uploads, 1)
        XCTAssertEqual(CloudJSON.findEntity(submitted!, id: aID.uuidString)?["note"] as? String, "A 主动保存")
        XCTAssertEqual(CloudJSON.findEntity(submitted!, id: bID.uuidString)?["note"] as? String, "B 云端修改")
        let applied = try XCTUnwrap(CloudRecordAdapter.records(target.mainContext).first)
        let value = try JSONSerialization.jsonObject(with: applied.data)
        XCTAssertEqual(CloudJSON.findEntity(value, id: bID.uuidString)?["note"] as? String, "B 尚未提交")
        XCTAssertEqual((value as? [String: Any])?["destination"] as? String, "云端城市")
        await cloud.uploadPending(context: target.mainContext, key: original.key, entityID: aID)
        XCTAssertEqual(uploads, 1, "同一安排未再修改时不能重复提交")
        await cloud.uploadPending(context: target.mainContext, key: original.key, entityID: bID)
        XCTAssertEqual(uploads, 1, "B 的冲突不能因为 A 已保存而被静默覆盖")
        XCTAssertTrue(cloud.conflicts.contains(original.key))
        try await cloud.resolve(original.key, useCloud: false, context: target.mainContext)
        XCTAssertEqual(uploads, 2)
        XCTAssertEqual(CloudJSON.findEntity(submitted!, id: bID.uuidString)?["note"] as? String, "B 尚未提交")
    }

    func testAutomaticStatusChangesDoNotMarkUneditedContentDirty() throws {
        let base: [String: Any] = ["id": "a", "executionStatusRaw": "未开始", "isCompleted": false, "isTimePending": false]
        var fresh = base; fresh["executionStatusRaw"] = "已完成"; fresh["isCompleted"] = true
        let encode: ([String: Any]) throws -> Data = { try JSONSerialization.data(withJSONObject: $0) }
        XCTAssertEqual(try CloudJSON.businessFingerprint(encode(base)), try CloudJSON.businessFingerprint(encode(fresh)))
        var pending = base; pending["isTimePending"] = true
        var completedPending = fresh; completedPending["isTimePending"] = true
        XCTAssertNotEqual(try CloudJSON.businessFingerprint(encode(pending)), try CloudJSON.businessFingerprint(encode(completedPending)))
    }
    func testSavingOneEntityPreservesOtherPendingChanges() throws {
        let base: [String: Any] = ["id": "trip", "title": "saved", "days": [["id": "day", "items": [["id": "a", "note": "old"], ["id": "b", "note": "old"]]]]]
        let fresh: [String: Any] = ["id": "trip", "title": "unsaved title", "days": [["id": "day", "items": [["id": "a", "note": "saved edit"], ["id": "b", "note": "unsaved edit"], ["id": "c", "note": "new"]]]]]
        let saved = try XCTUnwrap(CloudJSON.scoped(base, current: fresh, id: "a") as? [String: Any])
        XCTAssertEqual(saved["title"] as? String, "saved")
        let days = try XCTUnwrap(saved["days"] as? [[String: Any]])
        let items = try XCTUnwrap(days[0]["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0]["note"] as? String, "saved edit")
        XCTAssertEqual(items[1]["note"] as? String, "old")
        let added = try XCTUnwrap(CloudJSON.scoped(base, current: fresh, id: "c") as? [String: Any])
        let addedDays = try XCTUnwrap(added["days"] as? [[String: Any]])
        XCTAssertEqual((addedDays[0]["items"] as? [[String: Any]])?.count, 3)
    }

    func testFreshInstallDownloadsDayCity() async throws {
        let id = UUID().uuidString
        let payload: [String: Any] = ["id": id, "title": "城市同步", "destination": "宁夏", "startDate": 1790870400000, "endDate": 1790870400000, "note": "", "createdAt": 1790870400000, "days": [["id": UUID().uuidString, "date": 1790870400000, "title": "第一天", "city": "银川", "note": "", "sortOrder": 0, "items": []]]]
        var response = try JSONSerialization.data(withJSONObject: [["id": id, "kind": "trip", "title": "城市同步", "payload": payload, "revision": 20]])
        var uploads = 0
        CloudStubURLProtocol.handler = { request in
            if (request.url!.path.contains("triptrail_save_record") || request.url!.path.contains("triptrail_patch_record")) { uploads += 1; return (409, Data("{}".utf8)) }
            if request.url!.path.contains("triptrail_deleted_records") { return (200, Data("[]".utf8)) }
            return (200, response)
        }
        defer { CloudStubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CloudStubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let suite = "FreshCity-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = CloudSyncService(defaults: defaults, session: session, publicKeyOverride: "test-key")
        let target = try ModelContainer(for: Trip.self, TripDay.self, ItineraryItem.self, MediaReference.self, TravelStory.self, StoryDay.self, StoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        await cloud.sync(context: target.mainContext, kind: "trip", automatic: true)
        let trip = try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<Trip>()).first)
        XCTAssertEqual(trip.sortedDays.first?.city, "银川")
        let saved = try XCTUnwrap(CloudRecordAdapter.records(target.mainContext).first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved.data) as? [String: Any])
        XCTAssertEqual((object["days"] as? [[String: Any]])?.first?["city"] as? String, "银川")
        trip.note = "本地编辑"
        var conflictingPayload = payload; conflictingPayload["note"] = "云端编辑"
        response = try JSONSerialization.data(withJSONObject: [["id": id, "kind": "trip", "title": "城市同步", "payload": conflictingPayload, "revision": 21]])
        await cloud.uploadPending(context: target.mainContext)
        XCTAssertEqual(uploads, 0)
        XCTAssertTrue(cloud.conflicts.contains(saved.key))
        XCTAssertEqual(trip.note, "本地编辑")
        XCTAssertEqual(trip.sortedDays.first?.city, "银川")
        let preview = try await cloud.previewCloudVersion(id: trip.id, kind: "trip")
        XCTAssertEqual(preview.revision, 21)
        XCTAssertEqual(trip.note, "本地编辑", "读取预览不能覆盖本地")
        XCTAssertEqual(uploads, 0)
        try await cloud.replaceWithPreview(preview, context: target.mainContext)
        XCTAssertEqual(trip.note, "云端编辑")
        XCTAssertEqual(trip.sortedDays.first?.city, "银川")
        XCTAssertFalse(cloud.conflicts.contains(saved.key))
        XCTAssertEqual(uploads, 0, "覆盖本地不能写入云端")
        let pureLocal = Trip(title: "仅本地", destination: "成都", startDate: Date(), endDate: Date())
        target.mainContext.insert(pureLocal)
        var newerPayload = payload
        newerPayload["note"] = "云端新说明"
        response = try JSONSerialization.data(withJSONObject: [["id": id, "kind": "trip", "title": "城市同步", "payload": newerPayload, "revision": 22]])
        await cloud.sync(context: target.mainContext, kind: "trip")
        XCTAssertEqual(trip.note, "云端新说明", "本地未改时应自动读取云端更新")
        XCTAssertFalse(cloud.conflicts.contains(saved.key))
        await cloud.pullAllCloudVersions(context: target.mainContext)
        XCTAssertEqual(trip.note, "云端新说明")
        XCTAssertEqual(trip.sortedDays.first?.city, "银川")
        XCTAssertTrue(try target.mainContext.fetch(FetchDescriptor<Trip>()).contains { $0.id == pureLocal.id })
        XCTAssertFalse(cloud.conflicts.contains(saved.key))
        XCTAssertEqual(uploads, 0, "全局拉取不能上传本地内容")
        trip.note = "只在本地修改"
        newerPayload["note"] = trip.note
        let uploadedResponse = try JSONSerialization.data(withJSONObject: ["id": id, "kind": "trip", "title": "城市同步", "payload": newerPayload, "revision": 23])
        CloudStubURLProtocol.handler = { request in
            if request.url!.path.contains("triptrail_deleted_records") { return (200, Data("[]".utf8)) }
            if (request.url!.path.contains("triptrail_save_record") || request.url!.path.contains("triptrail_patch_record")) { uploads += 1; return (200, uploadedResponse) }
            return (200, response)
        }
        await cloud.uploadPending(context: target.mainContext)
        XCTAssertEqual(uploads, 1, "云端未变时本地编辑在主动保存时应上传")
        XCTAssertFalse(cloud.conflicts.contains(saved.key))
        XCTAssertEqual(cloud.bindings[saved.key]?.revision, 23)
        await cloud.uploadPending(context: target.mainContext)
        XCTAssertEqual(uploads, 1, "成功上传后不应重复上传")

    }

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
            if (path.contains("triptrail_save_record") || path.contains("triptrail_patch_record")) { writes += 1; return (410, Data("{}".utf8)) }
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
