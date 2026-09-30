import Combine
import CryptoKit
import Foundation
import SwiftData

struct CloudLocalRecord: Identifiable {
    let id: UUID
    let kind: String
    let title: String
    let data: Data
    let media: [MediaReference]
    var key: String { "\(kind):\(id.uuidString.lowercased())" }
    var fingerprint: String { get throws { try CloudJSON.fingerprint(data) } }
}
struct CloudRemoteRecord: Identifiable {
    let id: UUID
    let kind: String
    let title: String
    let revision: Int
    let payload: Data
    var key: String { "\(kind):\(id.uuidString.lowercased())" }
    init(_ object: [String: Any]) throws {
        guard let id = (object["id"] as? String).flatMap(UUID.init(uuidString:)),
              let kind = object["kind"] as? String, ["trip", "story", "favorite"].contains(kind),
              let revision = object["revision"] as? Int, revision > 0,
              let payload = object["payload"] as? [String: Any],
              let payloadID = (payload["id"] as? String).flatMap(UUID.init(uuidString:)), payloadID == id
        else { throw CloudSyncError.message("云端数据格式不受支持") }
        self.id = id; self.kind = kind; self.title = object["title"] as? String ?? "未命名"
        self.revision = revision
        self.payload = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}
struct CloudBinding: Codable {
    var revision: Int = 0
    var baseline: String = ""
    var origin: String
}
enum CloudSyncError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
enum CloudJSON {
    static func isValidMediaPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, UUID(uuidString: String(parts[0])) != nil else { return false }
        let file = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return file.count == 2 && file[0].count == 64
            && file[0].allSatisfy { "0123456789abcdef".contains($0) }
            && !file[1].isEmpty && file[1].allSatisfy { $0.isASCII && $0.isLetter || $0.isASCII && $0.isNumber }
    }

    static func transform(_ value: Any, media: ([String: Any]) throws -> [String: Any]) rethrows -> Any {
        if var object = value as? [String: Any] {
            if object["localIdentifier"] != nil { object = try media(object) }
            for key in object.keys { object[key] = try transform(object[key]!, media: media) }
            return object
        }
        if let array = value as? [Any] { return try array.map { try transform($0, media: media) } }
        return value
    }
    static func fingerprint(_ data: Data) throws -> String {
        let value = try JSONSerialization.jsonObject(with: data)
        let normalized = transform(value) { object in
            var result = object
            result["localIdentifier"] = result["id"]
            result.removeValue(forKey: "cloudPath")
            return result
        }
        return digest(try JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys]))
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

@MainActor
final class CloudSyncService: ObservableObject {
    static let shared = CloudSyncService()
    @Published private(set) var bindings: [String: CloudBinding] = [:]
    @Published private(set) var remote: [CloudRemoteRecord] = []
    @Published private(set) var busy = false
    @Published var message = ""
    @Published private(set) var conflicts: Set<String> = []
    var projectURL: String { Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? "" }
    var publicKey: String {
        if let publicKeyOverride { return publicKeyOverride }
        let value = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
        return value.hasPrefix("$(") ? "" : value
    }
    var configured: Bool { !publicKey.isEmpty }
    private var lastAutomaticCheck: [String: Date] = [:]
    private var syncWaiters: [CheckedContinuation<Void, Never>] = []
    private func beginSync() async {
        if busy { await withCheckedContinuation { syncWaiters.append($0) } }
        busy = true
    }
    private func endSync() {
        if syncWaiters.isEmpty { busy = false } else { syncWaiters.removeFirst().resume() }
    }
    private var mediaPaths: [String: String] = [:]
    private let defaults: UserDefaults
    private let session: URLSession
    private let publicKeyOverride: String?
    init(defaults: UserDefaults = .standard, session: URLSession = .shared, publicKeyOverride: String? = nil) {
        self.defaults = defaults
        self.session = session
        self.publicKeyOverride = publicKeyOverride
        if let data = defaults.data(forKey: "cloud.relational.bindings"), let value = try? JSONDecoder().decode([String: CloudBinding].self, from: data) { bindings = value }
        if FileManager.default.fileExists(atPath: recycleURL.path) {
            do { recycle = try JSONDecoder().decode([RecycleEntry].self, from: Data(contentsOf: recycleURL)) }
            catch { recycleReadError = "回收站读取失败，请保留应用数据：\(error.localizedDescription)"; message = recycleReadError! }
        }
        mediaPaths = defaults.dictionary(forKey: "cloud.relational.mediaPaths") as? [String: String] ?? [:]
    }
    struct RecycleEntry: Codable, Identifiable {
        var id: UUID
        var kind: String
        var title: String
        var data: Data?
        var expiresAt: Date
        var cloud: Bool
        var pending: Bool
        var operationID: UUID? = nil
        var recoverable: Bool = true
        var key: String { "\(kind):\(id.uuidString.lowercased())" }
    }
    private var recycleReadError: String?
    @Published private(set) var recycle: [RecycleEntry] = []
    private var recycleURL: URL {
        let namespace = defaults.string(forKey: "cloud.recycle.namespace") ?? UUID().uuidString
        defaults.set(namespace, forKey: "cloud.recycle.namespace")
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recycle-\(namespace).json")
    }
    private func saveRecycle(_ value: [RecycleEntry]) throws {
        try FileManager.default.createDirectory(at: recycleURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: recycleURL, options: .atomic)
        recycle = value
    }
    func isDeleted(_ key: String) -> Bool { recycleReadError != nil || recycle.contains { $0.key == key } }
    private func removeLocal(_ id: UUID, kind: String, context: ModelContext) throws {
        if kind == "trip" { for item in try context.fetch(FetchDescriptor<Trip>()) where item.id == id { context.delete(item) } }
        if kind == "story" { for item in try context.fetch(FetchDescriptor<TravelStory>()) where item.id == id { context.delete(item) } }
        if kind == "favorite" { for item in try context.fetch(FetchDescriptor<ItineraryItem>()) where item.id == id && item.isFavorite { context.delete(item) } }
        try context.save()
    }
    @discardableResult
    func trash(id: UUID, kind: String, context: ModelContext) -> Bool {
        do {
            if let recycleReadError { throw CloudSyncError.message(recycleReadError) }
            guard let record = try CloudRecordAdapter.records(context).first(where: { $0.id == id && $0.kind == kind }) else { return false }
            let cloud = linked(record.key)
            let entry = RecycleEntry(id: id, kind: kind, title: record.title, data: record.data, expiresAt: Date().addingTimeInterval(86400), cloud: cloud, pending: cloud, operationID: cloud ? UUID() : nil)
            // Persist intent first: after a crash the next sync completes removal before any upload.
            try saveRecycle(recycle.filter { $0.key != record.key } + [entry])
            try removeLocal(id, kind: kind, context: context)
            bindings.removeValue(forKey: record.key); conflicts.remove(record.key); persist()
            remote.removeAll { $0.key == record.key }
            Task { await uploadPending(context: context) }
            return true
        } catch { message = "删除未完成：\(error.localizedDescription)"; return false }
    }
    private func recycleRPC(_ name: String, _ entry: RecycleEntry) async throws {
        var body: [String: Any] = ["record_id": entry.id.uuidString, "record_kind": entry.kind]
        if name == "triptrail_trash_record", let operationID = entry.operationID { body["operation_id"] = operationID.uuidString }
        _ = try await request("rest/v1/rpc/" + name, method: "POST", body: JSONSerialization.data(withJSONObject: body))
    }
    private func flushDeletes(context: ModelContext) async throws {
        if let recycleReadError { throw CloudSyncError.message(recycleReadError) }
        for entry in recycle {
            if (entry.pending && linked(entry.key)) || !entry.cloud {
                try removeLocal(entry.id, kind: entry.kind, context: context)
                bindings.removeValue(forKey: entry.key); persist()
            }
            if entry.pending {
                try await recycleRPC("triptrail_trash_record", entry)
                var updated = recycle
                if let index = updated.firstIndex(where: { $0.key == entry.key }) { updated[index].pending = false }
                try saveRecycle(updated)
            }
        }
        try saveRecycle(recycle.map { item in var value = item; if value.expiresAt <= Date() { value.data = nil }; return value })
    }
    private func loadDeletions(context: ModelContext) async throws {
        var entries: [RecycleEntry] = []; var offset = 0
        while true {
            let data = try await request("rest/v1/triptrail_deleted_records?select=*&order=kind.asc,id.asc&limit=100&offset=\(offset)")
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw CloudSyncError.message("回收站响应无效") }
            for row in rows {
                guard let raw = row["id"] as? String, let id = UUID(uuidString: raw), let kind = row["kind"] as? String, let expiry = row["expires_at_ms"] as? Double else { throw CloudSyncError.message("回收站数据无效") }
                entries.append(RecycleEntry(id: id, kind: kind, title: row["title"] as? String ?? "未命名", data: nil, expiresAt: Date(timeIntervalSince1970: expiry / 1000), cloud: true, pending: false, recoverable: row["recoverable"] as? Bool ?? true))
            }
            if rows.count < 100 { break }; offset += rows.count
        }
        let retained = recycle.filter { !$0.cloud || $0.pending }
        try saveRecycle(retained + entries.filter { entry in !retained.contains { $0.key == entry.key } }.map { entry in
            var value = entry
            if value.expiresAt > Date() { value.data = recycle.first { $0.key == value.key }?.data }
            return value
        })
        for entry in entries where linked(entry.key) {
            try removeLocal(entry.id, kind: entry.kind, context: context)
            bindings.removeValue(forKey: entry.key); conflicts.remove(entry.key)
        }
        remote.removeAll { isDeleted($0.key) }; persist()
    }
    func refreshRecycle(context: ModelContext) async {
        await beginSync(); defer { endSync() }
        do {
            try await flushDeletes(context: context)
            if configured {
                try await loadDeletions(context: context)
                _ = try await request("rest/v1/rpc/triptrail_purge_recycle", method: "POST", body: Data("{}".utf8))
            }
        } catch { message = "回收站暂未同步：\(error.localizedDescription)" }
    }
    func restore(_ entry: RecycleEntry, context: ModelContext) async {
        await beginSync(); defer { endSync() }
        do {
            guard entry.expiresAt > Date() else { throw CloudSyncError.message("已超过 24 小时，无法恢复") }
            guard try !CloudRecordAdapter.records(context).contains(where: { $0.key == entry.key }) else { throw CloudSyncError.message("已有同名标识的本地内容，未覆盖") }
            if entry.cloud {
                // Finish an uncertain delete before restoring; retries cannot reset its server deadline.
                if entry.pending { try await recycleRPC("triptrail_trash_record", entry) }
                try await recycleRPC("triptrail_restore_record", entry)
                try await loadRemote(ids: [entry.id.uuidString.lowercased()])
                if let server = remote.first(where: { $0.key == entry.key }) {
                    try saveRecycle(recycle.filter { $0.key != entry.key })
                    try await receive(server, replacing: nil, context: context)
                } else if let data = entry.data {
                    try CloudRecordAdapter.apply(data, kind: entry.kind, context: context)
                    if let record = try CloudRecordAdapter.records(context).first(where: { $0.key == entry.key }) { try enable(record, context: context) }
                } else { throw CloudSyncError.message("云端内容不存在") }
            } else if let data = entry.data { try CloudRecordAdapter.apply(data, kind: entry.kind, context: context) }
            try saveRecycle(recycle.filter { $0.key != entry.key })
            lastAutomaticCheck.removeAll(); message = "已恢复"
        } catch { message = "恢复失败：\(error.localizedDescription)" }
    }

    func linked(_ key: String) -> Bool { bindings[key]?.origin == projectURL }
    func enable(_ record: CloudLocalRecord, context: ModelContext) throws {
        guard configured else { throw CloudSyncError.message("当前安装包未配置云端服务") }
        try context.save()
        bindings[record.key] = bindings[record.key] ?? CloudBinding(origin: projectURL)
        persist()
    }
    func restoreBackup(from url: URL, into context: ModelContext) async throws -> TripTrailBackupSummary {
        await beginSync()
        defer { endSync() }
        let summary = try await DataBackupService.restoreBackup(from: url, into: context)
        detachAll()
        let restoredKeys = Set(try CloudRecordAdapter.records(context).map(\.key))
        try saveRecycle(recycle.filter { $0.cloud || !restoredKeys.contains($0.key) })
        return summary
    }
    func detachAll() { bindings.removeAll(); conflicts.removeAll(); persist() }
    private func persist() { defaults.set(try? JSONEncoder().encode(bindings), forKey: "cloud.relational.bindings") }

    func sync(context: ModelContext, kind: String? = nil, recordID: UUID? = nil, browse: Bool = false, automatic: Bool = false) async {
        guard configured else { return }
        await beginSync(); defer { endSync() }
        guard !Task.isCancelled else { return }
        do {
            try context.save()
            try await flushDeletes(context: context)
            let all = try CloudRecordAdapter.records(context)
            let candidates = all.filter { linked($0.key) && (kind == nil || $0.kind == kind) && (recordID == nil || $0.id == recordID) }
            let now = Date()
            let records = try candidates.filter { record in
                let dirty = try record.fingerprint != bindings[record.key]?.baseline
                return CloudRefreshPolicy.shouldRequest(automatic: automatic, dirty: dirty, lastCheck: lastAutomaticCheck[record.key], now: now)
            }
            let catalogKey = "catalog:" + (kind ?? "all")
            let fetchCatalog = (browse || recordID == nil) && CloudRefreshPolicy.shouldRequest(automatic: automatic, dirty: !records.isEmpty, lastCheck: lastAutomaticCheck[catalogKey], now: now)
            guard fetchCatalog || !records.isEmpty else { return }
            try await loadDeletions(context: context)
            if fetchCatalog {
                try await loadRemote(kind: kind)
                lastAutomaticCheck[catalogKey] = now
            } else {
                let ids = records.map { $0.id.uuidString.lowercased() }
                for start in stride(from: 0, to: ids.count, by: 100) {
                    try await loadRemote(ids: Array(ids[start..<min(start + 100, ids.count)]))
                }
            }
            for snapshot in records {
                try Task.checkCancellation()
                // Refresh the snapshot after awaiting the request so in-flight local edits are never overwritten.
                guard linked(snapshot.key), let record = try CloudRecordAdapter.records(context).first(where: { $0.key == snapshot.key }) else { continue }
                do {
                    try await syncOne(record, context: context)
                    lastAutomaticCheck[record.key] = now
                } catch is CancellationError { throw CancellationError() }
                catch { message = "本地已保留，稍后重试：\(error.localizedDescription)" }
            }
            if fetchCatalog {
                // Discover shared records on opening the feature; keep independent local copies untouched.
                for server in remote.filter({ kind == nil || $0.kind == kind }) {
                    try Task.checkCancellation()
                    guard try !CloudRecordAdapter.records(context).contains(where: { $0.key == server.key }) else { continue }
                    do {
                        try await receive(server, replacing: nil, context: context)
                        lastAutomaticCheck[server.key] = now
                    } catch is CancellationError { throw CancellationError() }
                    catch { message = "部分云端内容暂未加载，本地数据已保留：\(error.localizedDescription)" }
                }
            }
            let existing = Set(try CloudRecordAdapter.records(context).map(\.key))
            for key in Array(bindings.keys) where !existing.contains(key) { bindings.removeValue(forKey: key) }
            persist()
        } catch is CancellationError { }
        catch { message = "云端暂不可用，继续使用本地数据：\(error.localizedDescription)" }
    }
    func archiveFinishedTrips(context: ModelContext, relativeTo date: Date = Date()) async {
        do {
            _ = try StoryArchiveService.archiveFinishedTrips(modelContext: context, relativeTo: date)
            let trips = try context.fetch(FetchDescriptor<Trip>())
            let endedCloudIDs = Set(trips.filter {
                TripTimelineOrdering.phase(for: $0, relativeTo: date) == .history && linked("trip:\($0.id.uuidString.lowercased())")
            }.map(\.id))
            let stories = try context.fetch(FetchDescriptor<TravelStory>()).filter { story in
                story.sourceTripID.map { endedCloudIDs.contains($0) } ?? false
            }
            let storyIDs = Set(stories.map(\.id))
            for record in try CloudRecordAdapter.records(context) where record.kind == "story" && storyIDs.contains(record.id) && !linked(record.key) {
                try enable(record, context: context)
            }
            if !storyIDs.isEmpty { await uploadPending(context: context) }
        } catch { message = "自动整理足迹未完成：\(error.localizedDescription)" }
    }

    func uploadAfterEdit(context: ModelContext) {
        Task { await uploadPending(context: context) }
    }

    func uploadPending(context: ModelContext) async {
        guard configured else { return }
        await beginSync(); defer { endSync() }
        do {
            try context.save()
            try await flushDeletes(context: context)
            for record in try CloudRecordAdapter.records(context) where linked(record.key) && !isDeleted(record.key) {
                guard let binding = bindings[record.key], try record.fingerprint != binding.baseline else { continue }
                // Save events only upload the changed snapshot, without pulling the cloud catalog.
                do { try await send(record, revision: binding.revision, context: context) }
                catch { message = "本地已保存，云端待同步：\(error.localizedDescription)" }
            }
        } catch { message = "本地保存失败：\(error.localizedDescription)" }
    }

    private func loadRemote(kind: String? = nil, ids: [String]? = nil) async throws {
        var result: [CloudRemoteRecord] = []; var offset = 0
        let filter = ids.map { "&id=in.(" + $0.joined(separator: ",") + ")" } ?? kind.map { "&kind=eq." + $0 } ?? ""
        while true {
            let data = try await request("rest/v1/triptrail_cloud_records?select=*&order=id.asc&limit=100&offset=\(offset)" + filter)
            guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw CloudSyncError.message("云端返回了无效列表") }
            result += try array.map(CloudRemoteRecord.init)
            if array.count < 100 { break }; offset += array.count
        }
        if let ids { let set = Set(ids); remote.removeAll { set.contains($0.id.uuidString.lowercased()) } }
        else if let kind { remote.removeAll { $0.kind == kind } }
        else { remote = [] }
        remote += result; message = ""
    }
    private func syncOne(_ local: CloudLocalRecord, context: ModelContext) async throws {
        guard let binding = bindings[local.key] else { return }
        let server = remote.first { $0.key == local.key }
        let dirty = try local.fingerprint != binding.baseline
        switch CloudSyncDecision.choose(localChanged: dirty, baseRevision: binding.revision, remoteRevision: server?.revision) {
        case .conflict:
            conflicts.insert(local.key); message = "有内容在本地和云端同时修改，请在云端数据中选择保留版本"
        case .download:
            if let server { try await receive(server, replacing: local, context: context) }
        case .upload:
            try await send(local, revision: binding.revision, context: context)
        case .missing:
            throw CloudSyncError.message("云端记录已不存在，本地副本仍保留")
        case .unchanged:
            // A matching record revision does not guarantee its local media still exists.
            if let server, local.media.contains(where: { !PhotoLibraryService.isLocallyAvailable($0.localIdentifier) }) {
                try await receive(server, replacing: local, context: context)
            }
        }
    }
    func acquire(_ server: CloudRemoteRecord, context: ModelContext) async throws {
        guard !busy else { throw CloudSyncError.message("正在同步，请稍后再试") }
        guard !(try CloudRecordAdapter.records(context)).contains(where: { $0.key == server.key }) else { throw CloudSyncError.message("本地已有同一条内容，请在本地内容中启用云端模式") }
        busy = true; defer { endSync() }
        try await receive(server, replacing: nil, context: context)
    }
    func resolve(_ key: String, useCloud: Bool, context: ModelContext) async throws {
        guard !busy else { return }; busy = true; defer { endSync() }
        try await loadRemote(ids: [String(key.split(separator: ":").last ?? "")])
        guard let local = try CloudRecordAdapter.records(context).first(where: { $0.key == key }), let server = remote.first(where: { $0.key == key }) else { return }
        if useCloud { try await receive(server, replacing: local, context: context) }
        else { try await send(local, revision: server.revision, context: context) }
        conflicts.remove(key)
    }
    private func send(_ local: CloudLocalRecord, revision: Int, context: ModelContext) async throws {
        guard !isDeleted(local.key) else { return }
        let hash = try local.fingerprint
        var paths: [String: String] = [:]
        for media in local.media {
            let cacheKey = "\(projectURL)|\(media.localIdentifier)"
            if let path = mediaPaths[cacheKey] { paths[media.id.uuidString] = path; continue }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let asset = try await PhotoLibraryService.exportOriginal(identifier: media.localIdentifier, kind: media.kind, referenceID: media.id, to: directory)
            let bytes = try Data(contentsOf: asset.fileURL)
            let suffix = asset.fileURL.pathExtension.lowercased().filter { $0.isLetter || $0.isNumber }
            let path = "\(local.id.uuidString.lowercased())/\(CloudJSON.digest(bytes)).\(suffix.isEmpty ? "bin" : suffix)"
            _ = try await request("storage/v1/object/triptrail-media/\(path)", method: "POST", body: bytes, contentType: "application/octet-stream", allowDuplicate: true)
            paths[media.id.uuidString] = path; mediaPaths[cacheKey] = path
            defaults.set(mediaPaths, forKey: "cloud.relational.mediaPaths")
        }
        let object = try JSONSerialization.jsonObject(with: local.data)
        let payload = CloudJSON.transform(object) { value in
            var result = value; result["cloudPath"] = paths[value["id"] as? String ?? ""]
            result["localIdentifier"] = ""; return result
        }
        guard !isDeleted(local.key) else { return }
        let body: [String: Any] = ["record_id": local.id.uuidString, "record_kind": local.kind, "record_title": local.title, "record_payload": payload, "expected_revision": revision]
        do {
            let data = try await request("rest/v1/rpc/triptrail_save_record", method: "POST", body: try JSONSerialization.data(withJSONObject: body))
            let decoded = try JSONSerialization.jsonObject(with: data)
            guard let object = decoded as? [String: Any] ?? (decoded as? [[String: Any]])?.first else { throw CloudSyncError.message("保存响应格式错误") }
            let server = try CloudRemoteRecord(object)
            // Baseline is exactly the sent snapshot. Edits made during upload stay dirty.
            bindings[local.key] = CloudBinding(revision: server.revision, baseline: hash, origin: projectURL)
            remote.removeAll { $0.key == server.key }; remote.append(server); persist()
            message = "已同步，本地副本已保留"
        } catch { if error.localizedDescription.contains("409") { conflicts.insert(local.key) }; throw error }
    }
    private func receive(_ server: CloudRemoteRecord, replacing local: CloudLocalRecord?, context: ModelContext) async throws {
        guard !isDeleted(server.key) else { return }
        let before = try local?.fingerprint
        let object = try JSONSerialization.jsonObject(with: server.payload)
        var descriptors: [[String: Any]] = []
        _ = CloudJSON.transform(object) { value in descriptors.append(value); return value }
        var identifiers: [String: String] = [:]
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("CloudMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for media in descriptors {
            guard let path = media["cloudPath"] as? String, CloudJSON.isValidMediaPath(path),
                  let id = media["id"] as? String else { throw CloudSyncError.message("云端媒体信息不完整，本地数据未替换") }
            let file = directory.appendingPathComponent(CloudJSON.digest(Data(projectURL.utf8)) + "-" + path.replacingOccurrences(of: "/", with: "-"))
            if !FileManager.default.fileExists(atPath: file.path) {
                let bytes = try await request("storage/v1/object/triptrail-media/\(path)")
                let expected = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                guard CloudJSON.digest(bytes) == expected else { throw CloudSyncError.message("云端媒体校验失败") }
                try bytes.write(to: file, options: .atomic)
            }
            identifiers[id] = file.absoluteString
            mediaPaths["\(projectURL)|\(file.absoluteString)"] = path
        }
        guard !isDeleted(server.key) else { return }
        let current = try CloudRecordAdapter.records(context).first { $0.key == server.key }
        guard try current?.fingerprint == before else { throw CloudSyncError.message("下载期间本地内容有变化，将在下次同步处理") }
        let restored = CloudJSON.transform(object) { value in
            var result = value; result["localIdentifier"] = identifiers[value["id"] as? String ?? ""] ?? ""; return result
        }
        try CloudRecordAdapter.apply(JSONSerialization.data(withJSONObject: restored), kind: server.kind, context: context)
        guard let applied = try CloudRecordAdapter.records(context).first(where: { $0.key == server.key }) else { return }
        bindings[server.key] = CloudBinding(revision: server.revision, baseline: try applied.fingerprint, origin: projectURL)
        persist(); defaults.set(mediaPaths, forKey: "cloud.relational.mediaPaths")
        conflicts.remove(server.key); message = "已获取最新云端内容，并保存到本地"
    }
    func request(_ path: String, method: String = "GET", body: Data? = nil, contentType: String = "application/json", allowDuplicate: Bool = false) async throws -> Data {
        guard let url = URL(string: projectURL + "/" + path) else { throw CloudSyncError.message("Project URL 无效") }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = path.contains("triptrail-backups") ? 180 : 30
        request.setValue(publicKey, forHTTPHeaderField: "apikey")
        if publicKey.split(separator: ".").count == 3 { request.setValue("Bearer \(publicKey)", forHTTPHeaderField: "Authorization") }
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudSyncError.message("无效网络响应") }
        if allowDuplicate, http.statusCode == 409 { return data }
        if allowDuplicate, http.statusCode == 400, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], value["error"] as? String == "Duplicate" { return data }
        guard (200..<300).contains(http.statusCode) else { throw CloudSyncError.message("HTTP \(http.statusCode)：云端服务暂不可用，本地内容仍保留") }
        return data
    }
}

enum CloudSyncDecision: Equatable {
    case upload, download, conflict, missing, unchanged
    static func choose(localChanged: Bool, baseRevision: Int, remoteRevision: Int?) -> Self {
        guard let remoteRevision else { return baseRevision == 0 ? .upload : .missing }
        if remoteRevision != baseRevision { return localChanged ? .conflict : .download }
        return localChanged ? .upload : .unchanged
    }
}

// A timestamp is checked only on user navigation, never by a scheduled task.
enum CloudRefreshPolicy {
    static func shouldRequest(automatic: Bool, dirty: Bool, lastCheck: Date?, now: Date) -> Bool {
        !automatic || dirty || lastCheck == nil || now.timeIntervalSince(lastCheck!) >= 60
    }
}

struct CloudBackupVersion: Decodable, Identifiable {
    let id: UUID
    let created_at: String
    let object_path: String
    let bytes: Int64
    let deleting: Bool
    let ready: Bool
    let sha256: String
    let chunk_count: Int
    var title: String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: created_at) ?? ISO8601DateFormatter().date(from: created_at)
        return date?.formatted(date: .numeric, time: .standard) ?? created_at
    }
}

@MainActor
enum CloudBackupService {
    static let chunkSize = 8 * 1024 * 1024
    static func list() async throws -> [CloudBackupVersion] {
        var result: [CloudBackupVersion] = []
        while true {
            let data = try await CloudSyncService.shared.request("rest/v1/triptrail_backups?select=*&order=created_at.desc,id.desc&limit=100&offset=\(result.count)")
            let page = try JSONDecoder().decode([CloudBackupVersion].self, from: data)
            result += page
            if page.count < 100 { return result }
        }
    }
    @discardableResult
    static func upload(_ url: URL) async throws -> UUID {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else { throw CloudSyncError.message("备份文件为空") }
        let id = UUID().uuidString.lowercased()
        let path = id + ".triptrailbackup"
        let count = (size + chunkSize - 1) / chunkSize
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var digest = SHA256()
        while let bytes = try file.read(upToCount: chunkSize), !bytes.isEmpty { digest.update(data: bytes) }
        let checksum = digest.finalize().map { String(format: "%02x", $0) }.joined()
        try file.seek(toOffset: 0)
        let cloud = CloudSyncService.shared
        let body = try JSONSerialization.data(withJSONObject: ["id": id, "object_path": path, "bytes": size, "format_version": 1, "sha256": checksum, "chunk_count": count])
        _ = try await cloud.request("rest/v1/triptrail_backups", method: "POST", body: body)
        do {
            for index in 0..<count {
                guard let bytes = try file.read(upToCount: chunkSize), !bytes.isEmpty else { throw CloudSyncError.message("备份文件读取不完整") }
                _ = try await cloud.request("storage/v1/object/triptrail-backups/" + path + "/\(index)", method: "POST", body: bytes, contentType: "application/octet-stream")
            }
            _ = try await cloud.request("rest/v1/triptrail_backups?id=eq." + id, method: "PATCH", body: Data("{\"ready\":true}".utf8))
            return UUID(uuidString: id)!
        } catch {
            throw CloudSyncError.message("上传未完成或结果未确认，请在备份管理中刷新查看。未完成的版本可删除后重新上传。")
        }
    }
    static func download(_ version: CloudBackupVersion) async throws -> URL {
        guard !version.deleting && version.ready else { throw CloudSyncError.message("该版本尚未完成或正在删除。") }
        guard version.bytes > 0, version.chunk_count == (version.bytes + Int64(chunkSize) - 1) / Int64(chunkSize) else { throw CloudSyncError.message("备份版本信息无效") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".triptrailbackup")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        do {
            var digest = SHA256()
            var size: Int64 = 0
            for index in 0..<version.chunk_count {
                let data = try await CloudSyncService.shared.request("storage/v1/object/authenticated/triptrail-backups/" + version.object_path + "/\(index)")
                guard data.count <= chunkSize else { throw CloudSyncError.message("备份分块大小无效") }
                try file.write(contentsOf: data)
                digest.update(data: data); size += Int64(data.count)
            }
            let checksum = digest.finalize().map { String(format: "%02x", $0) }.joined()
            guard size == version.bytes && checksum == version.sha256 else { throw CloudSyncError.message("备份文件校验失败，请重新下载。") }
            try file.synchronize()
            _ = try DataBackupService.inspectBackup(at: url)
            return url
        } catch { try? FileManager.default.removeItem(at: url); throw error }
    }
    static func delete(_ version: CloudBackupVersion) async throws {
        let cloud = CloudSyncService.shared
        let endpoint = "rest/v1/triptrail_backups?id=eq." + version.id.uuidString.lowercased()
        _ = try await cloud.request(endpoint, method: "PATCH", body: Data("{\"deleting\":true}".utf8))
        for start in stride(from: 0, to: version.chunk_count, by: 100) {
            let paths = (start..<min(start + 100, version.chunk_count)).map { version.object_path + "/\($0)" }
            _ = try await cloud.request("storage/v1/object/triptrail-backups", method: "DELETE", body: JSONSerialization.data(withJSONObject: ["prefixes": paths]))
        }
        _ = try await cloud.request(endpoint, method: "DELETE")
    }
}

struct CloudStorageUsage: Codable {
    let database_bytes: Int64
    let object_bytes: Int64
    let measured_at_ms: Int64
    var measuredAt: Date { Date(timeIntervalSince1970: Double(measured_at_ms) / 1000) }
    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension CloudSyncService {
    func cachedStorageUsage() -> CloudStorageUsage? {
        guard let data = defaults.data(forKey: "cloud.storageUsage." + projectURL) else { return nil }
        return try? JSONDecoder().decode(CloudStorageUsage.self, from: data)
    }

    func storageUsage() async throws -> CloudStorageUsage {
        let key = "cloud.storageUsage." + projectURL
        if let cached = cachedStorageUsage(),
           Date().timeIntervalSince(cached.measuredAt) >= 0,
           Date().timeIntervalSince(cached.measuredAt) < 86400 {
            return cached
        }
        let data = try await request("rest/v1/rpc/triptrail_storage_usage", method: "POST", body: Data("{}".utf8))
        guard let value = try JSONDecoder().decode([CloudStorageUsage].self, from: data).first,
              value.database_bytes >= 0, value.object_bytes >= 0 else {
            throw CloudSyncError.message("容量统计暂不可用")
        }
        defaults.set(try JSONEncoder().encode(value), forKey: key)
        return value
    }
}
