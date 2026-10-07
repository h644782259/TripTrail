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
    var payload: Data? = nil
    var localPayload: Data? = nil
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
    // Collection position is not an edit when entities already carry sortOrder.
    static func canonicalCollections(_ value: Any) -> Any {
        if let object = value as? [String: Any] { return object.mapValues(canonicalCollections) }
        if let array = value as? [Any] {
            let values = array.map(canonicalCollections)
            if values.allSatisfy({ ($0 as? [String: Any])?["id"] is String && ($0 as? [String: Any])?["sortOrder"] != nil }) {
                return values.sorted { (($0 as? [String: Any])?["id"] as? String ?? "").lowercased() < (($1 as? [String: Any])?["id"] as? String ?? "").lowercased() }
            }
            return values
        }
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
        return digest(try JSONSerialization.data(withJSONObject: canonicalCollections(normalized), options: [.sortedKeys]))
    }
    static func businessValue(_ value: Any) -> Any {
        if var object = value as? [String: Any] {
            if object["executionStatusRaw"] != nil, object["isTimePending"] as? Bool != true, object["isFavorite"] as? Bool != true {
                object.removeValue(forKey: "executionStatusRaw")
                object.removeValue(forKey: "isCompleted")
                object.removeValue(forKey: "isAutomaticCompletionOverridden")
            }
            for key in object.keys { object[key] = businessValue(object[key]!) }
            return object
        }
        if let array = value as? [Any] { return array.map(businessValue) }
        return value
    }
    static func businessFingerprint(_ data: Data) throws -> String {
        let value = businessValue(try JSONSerialization.jsonObject(with: data))
        return try fingerprint(JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }
    static func findEntity(_ value: Any, id: String) -> [String: Any]? {
        if let object = value as? [String: Any] {
            if (object["id"] as? String)?.lowercased() == id.lowercased() { return object }
            for child in object.values { if let found = findEntity(child, id: id) { return found } }
        }
        if let array = value as? [Any] { for child in array { if let found = findEntity(child, id: id) { return found } } }
        return nil
    }
    static func containsEntity(_ value: Any, id: String) -> Bool {
        if let object = value as? [String: Any] {
            return (object["id"] as? String)?.lowercased() == id.lowercased() || object.values.contains { containsEntity($0, id: id) }
        }
        if let array = value as? [Any] { return array.contains { containsEntity($0, id: id) } }
        return false
    }
    static func newEntityScope(_ value: Any, id: String) -> Any {
        guard var object = value as? [String: Any] else { return value }
        for key in ["days", "items", "entries"] {
            if let children = object[key] as? [Any] {
                object[key] = children.filter { containsEntity($0, id: id) }.map { newEntityScope($0, id: id) }
            }
        }
        return object
    }
    // Replace one entity in the saved snapshot, preserving every unrelated entity.
    static func scoped(_ base: Any, current: Any?, id: String) -> Any? {
        if var object = base as? [String: Any] {
            if (object["id"] as? String)?.lowercased() == id.lowercased() {
                guard var selected = current as? [String: Any] else { return current }
                for key in ["days", "items", "entries"] { selected[key] = object[key] }
                return selected
            }
            let fresh = current as? [String: Any] ?? [:]
            for key in object.keys where object[key] is [Any] || object[key] is [String: Any] {
                object[key] = scoped(object[key]!, current: fresh[key], id: id)
            }
            if let previousDays = (base as? [String: Any])?["days"] as? [[String: Any]],
               let freshDays = fresh["days"] as? [[String: Any]],
               previousDays.contains(where: { ($0["id"] as? String)?.lowercased() == id.lowercased() }),
               !freshDays.contains(where: { ($0["id"] as? String)?.lowercased() == id.lowercased() }) {
                // Deleting a day also changes schedule boundaries. Keep sibling content from the baseline.
                object["startDate"] = fresh["startDate"]; object["endDate"] = fresh["endDate"]
                object["days"] = (object["days"] as? [[String: Any]] ?? []).map { day in
                    guard let updated = freshDays.first(where: { ($0["id"] as? String)?.lowercased() == (day["id"] as? String)?.lowercased() }) else { return day }
                    var result = day
                    let shift = (updated["date"] as? Double ?? 0) - (day["date"] as? Double ?? 0)
                    result["sortOrder"] = updated["sortOrder"]; result["date"] = updated["date"]
                    if shift != 0, let items = day["items"] as? [[String: Any]] {
                        result["items"] = items.map { item in
                            var value = item
                            for field in ["startTime", "endTime"] { if let time = item[field] as? Double { value[field] = time + shift } }
                            return value
                        }
                    }
                    return result
                }
            }
            return object
        }
        if let array = base as? [Any] {
            let fresh = current as? [Any] ?? []
            var values = array.compactMap { value -> Any? in
                let valueID = (value as? [String: Any])?["id"] as? String
                let match = fresh.first { ((($0 as? [String: Any])?["id"] as? String)?.lowercased()) == valueID?.lowercased() }
                return scoped(value, current: match, id: id)
            }
            for value in fresh where containsEntity(value, id: id) {
                let valueID = (value as? [String: Any])?["id"] as? String
                if !array.contains(where: { (($0 as? [String: Any])?["id"] as? String)?.lowercased() == valueID?.lowercased() }) { values.append(newEntityScope(value, id: id)) }
            }
            return values
        }
        return base
    }
    struct MergeResult {
        let value: Any?
        let conflicts: [String]
    }
    // Compare against the shared ancestor, matching collections by stable entity ID.
    // Device-local media paths and automatically derived status are not user edits.
    static func merge(base: Any?, local: Any?, remote: Any?, preferLocal: Bool = true, path: String = "", remoteChoices: Set<String> = []) -> MergeResult {
        func equal(_ a: Any?, _ b: Any?) -> Bool {
            guard let a, let b else { return a == nil && b == nil }
            func normalized(_ value: Any) -> Any {
                transform(businessValue(value)) { media in
                    var result = media; result.removeValue(forKey: "cloudPath")
                    result["localIdentifier"] = result["id"]; return result
                }
            }
            return NSDictionary(dictionary: ["v": normalized(a)]).isEqual(to: ["v": normalized(b)])
        }
        if equal(local, remote) { return MergeResult(value: local, conflicts: []) }
        if equal(local, base) { return MergeResult(value: remote, conflicts: []) }
        if equal(remote, base) { return MergeResult(value: local, conflicts: []) }
        if let l = local as? [String: Any], let r = remote as? [String: Any], base == nil || base is [String: Any] {
            let b = base as? [String: Any] ?? [:]
            var result: [String: Any] = [:]; var conflicts: [String] = []
            for key in Set(b.keys).union(l.keys).union(r.keys).sorted() {
                if l["executionStatusRaw"] != nil, l["isTimePending"] as? Bool != true, l["isFavorite"] as? Bool != true, ["executionStatusRaw", "isCompleted", "isAutomaticCompletionOverridden"].contains(key) {
                    result[key] = r[key] ?? l[key]; continue
                }
                if l["localIdentifier"] != nil || r["localIdentifier"] != nil {
                    if key == "localIdentifier" { result[key] = l[key] ?? r[key]; continue }
                    if key == "cloudPath" { result[key] = r[key] ?? l[key]; continue }
                }
                let child = merge(base: b[key], local: l[key], remote: r[key], preferLocal: preferLocal, path: path + "/" + key, remoteChoices: remoteChoices)
                result[key] = child.value; conflicts += child.conflicts
            }
            return MergeResult(value: result, conflicts: conflicts)
        }
        if let l = local as? [Any], let r = remote as? [Any], base == nil || base is [Any] {
            let b = base as? [Any] ?? []
            func ids(_ values: [Any]) -> [String]? {
                let keys = values.compactMap { (($0 as? [String: Any])?["id"] as? String)?.lowercased() }
                return keys.count == values.count && Set(keys).count == keys.count ? keys : nil
            }
            if let bi = ids(b), let li = ids(l), let ri = ids(r) {
                let bm = Dictionary(uniqueKeysWithValues: zip(bi, b)), lm = Dictionary(uniqueKeysWithValues: zip(li, l)), rm = Dictionary(uniqueKeysWithValues: zip(ri, r))
                var values: [Any] = []; var conflicts: [String] = []
                // sortOrder is merged as an ordinary field; array position carries no identity.
                for id in ri + li.filter({ !ri.contains($0) }) + bi.filter({ !ri.contains($0) && !li.contains($0) }) {
                    let child = merge(base: bm[id], local: lm[id], remote: rm[id], preferLocal: preferLocal, path: path + "/" + id, remoteChoices: remoteChoices)
                    if let value = child.value { values.append(value) }; conflicts += child.conflicts
                }
                return MergeResult(value: values, conflicts: conflicts)
            }
        }
        return MergeResult(value: preferLocal && !remoteChoices.contains(path) ? local : remote, conflicts: [path])
    }
    static func retainingAncestor(_ value: Any?, ancestor: Any?, paths: Set<String>, path: String = "") -> Any? {
        if paths.contains(path) { return ancestor }
        guard paths.contains(where: { $0.hasPrefix(path + "/") }) else { return value }
        if let v = value as? [String: Any] ?? (ancestor as? [String: Any]).map({ _ in [:] }) {
            let a = ancestor as? [String: Any] ?? [:]; var result = v
            for key in Set(v.keys).union(a.keys) { result[key] = retainingAncestor(v[key], ancestor: a[key], paths: paths, path: path + "/" + key) }
            return result
        }
        if let v = value as? [Any] ?? (ancestor as? [Any]).map({ _ in [] }) {
            let a = ancestor as? [Any] ?? []
            var values: [Any] = []
            let ids = (v + a).compactMap { (($0 as? [String: Any])?["id"] as? String)?.lowercased() }
            var seen = Set<String>()
            for id in ids where seen.insert(id).inserted {
                let find: ([Any]) -> Any? = { $0.first { (($0 as? [String: Any])?["id"] as? String)?.lowercased() == id } }
                if let child = retainingAncestor(find(v), ancestor: find(a), paths: paths, path: path + "/" + id) { values.append(child) }
            }
            return values
        }
        return value
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
    private var pendingSaves: [String: CloudLocalRecord] = [:]
    var presentedConflictKeys: Set<String> = []
    func clearEquivalentConflict(_ key: String, cloud: Data, local: Data) throws -> Bool {
        guard try CloudJSON.businessFingerprint(cloud) == CloudJSON.businessFingerprint(local) else { return false }
        if var binding = bindings[key], let server = remote.first(where: { $0.key == key }) {
            binding.revision = server.revision; binding.payload = server.payload
            binding.localPayload = local; binding.baseline = try CloudJSON.fingerprint(local)
            bindings[key] = binding; persist()
        }
        conflicts.remove(key); pendingSaves.removeValue(forKey: key)
        return true
    }
    var projectURL: String { Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? "" }
    var publicKey: String {
        if let publicKeyOverride { return publicKeyOverride }
        let value = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
        return value.hasPrefix("$(") ? "" : value
    }
    var configured: Bool { !publicKey.isEmpty }
    private func isDirty(_ local: CloudLocalRecord, _ binding: CloudBinding) throws -> Bool {
        if let base = binding.localPayload {
            return try CloudJSON.businessFingerprint(local.data) != CloudJSON.businessFingerprint(base)
        }
        return try local.fingerprint != binding.baseline
    }
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
        if kind == "trip" {
            for adapter in try context.fetch(FetchDescriptor<TravelStory>()) where adapter.journey?.id == id { context.delete(adapter) }
            for item in try context.fetch(FetchDescriptor<Trip>()) where item.id == id { context.delete(item) }
        }
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
            Task { await uploadPending(context: context, key: record.key) }
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

    func previewUnusedCloudFiles() async throws -> [[String: String]] {
        guard configured else { throw CloudSyncError.message("当前安装包未配置云端服务") }
        await beginSync(); defer { endSync() }
        let data = try await request("rest/v1/rpc/triptrail_cleanup_candidates", method: "POST", body: Data("{}".utf8))
        return try JSONSerialization.jsonObject(with: data) as? [[String: String]] ?? []
    }
    func cleanUnusedCloudFiles(_ files: [[String: String]]) async throws -> Int {
        await beginSync(); defer { endSync() }
        let data = try await request("rest/v1/rpc/triptrail_cleanup_claim", method: "POST", body: try JSONSerialization.data(withJSONObject: ["files": files]))
        let rows = try JSONSerialization.jsonObject(with: data) as? [[String: String]] ?? []
        var count = 0
        for bucket in ["triptrail-media", "triptrail-backups"] {
            let paths = rows.filter { $0["bucket"] == bucket }.compactMap { $0["path"] }
            if !paths.isEmpty {
                let deleted = try await request("storage/v1/object/" + bucket, method: "DELETE", body: try JSONSerialization.data(withJSONObject: ["prefixes": paths]))
                count += (try JSONSerialization.jsonObject(with: deleted) as? [[String: Any]])?.count ?? 0
            }
        }
        return count
    }

    private func mediaAvailable(_ path: String) async throws -> Bool {
        do {
            let data = try await request("rest/v1/rpc/triptrail_media_available", method: "POST", body: try JSONSerialization.data(withJSONObject: ["media_path": path]))
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        } catch {
            // Before the migration is installed, upload a fresh path rather than reuse an uncertain file.
            if Task.isCancelled { throw CancellationError() }
            return false
        }
    }

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
                let dirty = try bindings[record.key].map { try isDirty(record, $0) } ?? true
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
            try migrateLegacyBindings(context: context)
            let existing = Set(try CloudRecordAdapter.records(context).map(\.key))
            for key in Array(bindings.keys) where !existing.contains(key) && !key.hasPrefix("story:") { bindings.removeValue(forKey: key) }
            persist()
        } catch is CancellationError { }
        catch { message = "云端暂不可用，继续使用本地数据：\(error.localizedDescription)" }
    }
    func refreshUnifiedJourneys(context: ModelContext) async {
        do { try UnifiedJourneyService.reconcile(context: context) }
        catch { message = "旅行数据整理失败：\(error.localizedDescription)" }
    }
    func uploadPending(context: ModelContext, key: String? = nil, entityID: UUID? = nil) async {
        guard configured else { return }
        await beginSync(); defer { endSync() }
        do {
            try context.save()
            try await flushDeletes(context: context)
            for record in try CloudRecordAdapter.records(context) where linked(record.key) && !isDeleted(record.key) && (key == nil || key == record.key) {
                pendingSaves.removeValue(forKey: record.key)
                guard let binding = bindings[record.key], try isDirty(record, binding) else { continue }
                // Existing collections must be saved through a specific editor.
                // Revision zero is the initial upload when creating/enabling cloud mode.
                guard binding.revision == 0 || record.kind == "favorite" || entityID != nil else {
                    throw CloudSyncError.message("请在具体内容的编辑页面点击保存")
                }
                // Check this record before uploading so stale copies enter conflict resolution.
                do {
                    try await loadRemote(ids: [record.id.uuidString.lowercased()])
                    guard let current = try CloudRecordAdapter.records(context).first(where: { $0.key == record.key }) else { continue }
                    var selected = current
                    if let entityID {
                        guard let baseline = bindings[current.key]?.localPayload else {
                            throw CloudSyncError.message("请先重新加载云端内容，再保存单条修改")
                        }
                        let base = try JSONSerialization.jsonObject(with: baseline)
                        let fresh = try JSONSerialization.jsonObject(with: current.data)
                        var object = CloudJSON.scoped(base, current: fresh, id: entityID.uuidString)!
                        if current.kind == "story", let parent = CloudJSON.findEntity(fresh, id: entityID.uuidString)?["storyDayID"] as? String,
                           !CloudJSON.containsEntity(base, id: parent) {
                            object = CloudJSON.scoped(object, current: fresh, id: parent)!
                        }
                        if entityID == current.id, var metadata = base as? [String: Any], let fields = fresh as? [String: Any] {
                            for (field, value) in fields where !(value is [Any]) && (!(value is [String: Any]) || field == "coverMedia") { metadata[field] = value }
                            if (current.kind == "trip" || current.kind == "story") && fields["coverMedia"] == nil { metadata.removeValue(forKey: "coverMedia") }
                            object = metadata
                        }
                        selected = CloudLocalRecord(id: current.id, kind: current.kind, title: (object as? [String: Any])?["title"] as? String ?? current.title,
                            data: try JSONSerialization.data(withJSONObject: object), media: current.media)
                    }
                    guard try isDirty(selected, binding) else { continue }
                    for attempt in 0...2 {
                        do { try await syncOne(selected, context: context, allowUpload: true); break }
                        catch {
                            guard error.localizedDescription.contains("409"), attempt < 2 else { throw error }
                            try await loadRemote(ids: [selected.id.uuidString.lowercased()])
                        }
                    }
                }
                catch {
                    if error.localizedDescription.contains("重新加载") { conflicts.insert(record.key) }
                    message = "本地已保存，云端待同步：\(error.localizedDescription)"
                }
            }
        } catch { message = "本地保存失败：\(error.localizedDescription)" }
    }

    private func migrateLegacyBindings(context: ModelContext) throws {
        let localIDs = Set(try CloudRecordAdapter.records(context).filter { $0.kind == "trip" }.map(\.id))
        for (key, binding) in bindings where key.hasPrefix("story:") && binding.origin == projectURL {
            let payload = binding.payload.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let sourceID = (payload?["sourceTripID"] as? String).flatMap(UUID.init(uuidString:))
            let originalID = String(key.dropFirst(6)).lowercased()
            let targetID = sourceID.flatMap { localIDs.contains($0) ? $0 : nil } ?? UUID(uuidString: originalID)
            guard let server = remote.first(where: { $0.kind == "trip" && $0.id == targetID }) else { continue }
            if bindings[server.key] == nil {
                let baseline = try CloudRecordAdapter.normalized(server.payload, kind: "trip")
                bindings[server.key] = CloudBinding(revision: server.revision, baseline: try CloudJSON.fingerprint(baseline), origin: projectURL, payload: server.payload, localPayload: baseline)
            }
            bindings.removeValue(forKey: key)
        }
        persist()
    }
    private func requireUnifiedSchema() async throws {
        do { _ = try await request("rest/v1/triptrail_trips?select=journalSummary&limit=0") }
        catch {
            throw CloudSyncError.message("无法确认云端统一旅行结构，请检查连接及升级 SQL。本地数据已保留：\(error.localizedDescription)")
        }
    }
    private func loadRemote(kind: String? = nil, ids: [String]? = nil) async throws {
        try await requireUnifiedSchema()
        var result: [CloudRemoteRecord] = []; var offset = 0
        let kind = kind == "story" ? "trip" : kind
        let filter = ids.map { "&id=in.(" + $0.joined(separator: ",") + ")" } ?? kind.map { "&kind=eq." + $0 } ?? ""
        while true {
            let data = try await request("rest/v1/triptrail_cloud_records?select=*&order=id.asc&limit=100&offset=\(offset)" + filter)
            guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw CloudSyncError.message("云端返回了无效列表") }
            for row in array where row["kind"] as? String == "trip" {
                guard let payload = row["payload"] as? [String: Any], payload["journalSummary"] != nil else {
                    throw CloudSyncError.message("云端尚未升级统一旅行结构，本地数据已保留")
                }
            }
            result += try array.filter { $0["kind"] as? String != "story" }.map(CloudRemoteRecord.init)
            if array.count < 100 { break }; offset += array.count
        }
        if let ids { let set = Set(ids); remote.removeAll { set.contains($0.id.uuidString.lowercased()) } }
        else if let kind { remote.removeAll { $0.kind == kind } }
        else { remote = [] }
        remote += result; message = ""
    }
    private func syncOne(_ local: CloudLocalRecord, context: ModelContext, allowUpload: Bool = false) async throws {
        guard var binding = bindings[local.key] else { return }
        let server = remote.first { $0.key == local.key }
        if let server, try clearEquivalentConflict(local.key, cloud: CloudRecordAdapter.normalized(server.payload, kind: server.kind), local: local.data) { return }
        let dirty = try isDirty(local, binding)
        var comparisonRevision = server?.revision
        if let server, let base = binding.localPayload {
            let remoteData = try CloudRecordAdapter.normalized(server.payload, kind: server.kind)
            if try CloudJSON.businessFingerprint(base) == CloudJSON.businessFingerprint(remoteData) {
                binding.revision = server.revision; binding.payload = server.payload
                bindings[local.key] = binding; persist(); comparisonRevision = server.revision
            } else { comparisonRevision = binding.revision + 1 }
        }
        switch CloudSyncDecision.choose(localChanged: dirty, baseRevision: binding.revision, remoteRevision: comparisonRevision) {
        case .conflict:
            guard let server, let baseline = binding.localPayload else {
                conflicts.insert(local.key); message = "缺少同步基准，本地修改已保留，请重新加载"; return
            }
            let merged = CloudJSON.merge(base: try JSONSerialization.jsonObject(with: baseline), local: try JSONSerialization.jsonObject(with: local.data), remote: try JSONSerialization.jsonObject(with: CloudRecordAdapter.normalized(server.payload, kind: server.kind)))
            if !merged.conflicts.isEmpty {
                if allowUpload { pendingSaves[local.key] = local }
                conflicts.insert(local.key); message = "检测到内容冲突，请选择使用“云端”/“本地”版本"; return
            }
            if allowUpload {
                let selected = CloudLocalRecord(id: local.id, kind: local.kind, title: (merged.value as? [String: Any])?["title"] as? String ?? local.title, data: try JSONSerialization.data(withJSONObject: merged.value!), media: local.media)
                try await send(selected, revision: server.revision, context: context)
            } else {
                try await receive(server, replacing: local, context: context, preserving: merged.value)
            }
        case .download:
            if let server { try await receive(server, replacing: local, context: context) }
        case .upload:
            guard allowUpload else { return }
            try await send(local, revision: binding.revision, context: context)
        case .missing:
            throw CloudSyncError.message("云端记录已不存在，本地副本仍保留")
        case .unchanged:
            conflicts.remove(local.key)
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
    func pullAllCloudVersions(context: ModelContext) async {
        guard configured else { return }
        await beginSync(); defer { endSync() }
        do {
            try context.save()
            try await loadRemote()
            let records = remote
            var updated = 0
            var failed = 0
            for (index, server) in records.enumerated() {
                try Task.checkCancellation()
                message = "正在拉取云端数据（\(index + 1)/\(records.count)）"
                let local = try CloudRecordAdapter.records(context).first { $0.key == server.key }
                guard !isDeleted(server.key), local == nil || linked(server.key) else { continue }
                do {
                    try await receive(server, replacing: local, context: context)
                    updated += 1
                } catch is CancellationError { throw CancellationError() }
                catch { failed += 1 }
            }
            message = failed == 0 ? "已拉取 \(updated) 项云端最新内容" : "已更新 \(updated) 项，\(failed) 项未能下载，原本地内容已保留，可重试"
        } catch is CancellationError { message = "拉取已中止，未更新的本地内容已保留" }
        catch { message = "无法拉取云端数据，本地内容已保留：\(error.localizedDescription)" }
    }

    func previewCloudVersion(id: UUID, kind: String) async throws -> CloudRemoteRecord {
        await beginSync(); defer { endSync() }
        try await loadRemote(ids: [id.uuidString.lowercased()])
        guard let server = remote.first(where: { $0.id == id && $0.kind == kind }) else {
            throw CloudSyncError.message("云端已不存在这条内容，本地内容仍保留")
        }
        return server
    }

    func replaceWithPreview(_ server: CloudRemoteRecord, context: ModelContext) async throws {
        await beginSync(); defer { endSync() }
        guard let local = try CloudRecordAdapter.records(context).first(where: { $0.key == server.key }) else {
            throw CloudSyncError.message("本地内容已变化，请重新打开后再试")
        }
        try await receive(server, replacing: local, context: context)
    }

    func resolve(_ key: String, useCloud: Bool, context: ModelContext, expectedRevision: Int? = nil) async throws {
        guard !busy else { return }; busy = true; defer { endSync() }
        try await loadRemote(ids: [String(key.split(separator: ":").last ?? "")])
        guard let local = try CloudRecordAdapter.records(context).first(where: { $0.key == key }), let server = remote.first(where: { $0.key == key }) else { return }
        if let expectedRevision, server.revision != expectedRevision { throw CloudSyncError.message("云端内容已更新，请刷新详情后再选择") }
        guard let baseline = bindings[key]?.localPayload else {
            guard useCloud else { throw CloudSyncError.message("缺少同步基准，请先重新加载") }
            try await receive(server, replacing: local, context: context); return
        }
        conflicts.remove(key)
        let base = try JSONSerialization.jsonObject(with: baseline)
        let remoteValue = try JSONSerialization.jsonObject(with: CloudRecordAdapter.normalized(server.payload, kind: server.kind))
        if let pending = pendingSaves[key] {
            let merged = CloudJSON.merge(base: base, local: try JSONSerialization.jsonObject(with: pending.data), remote: remoteValue, preferLocal: !useCloud)
            let selected = CloudLocalRecord(id: local.id, kind: local.kind, title: (merged.value as? [String: Any])?["title"] as? String ?? local.title, data: try JSONSerialization.data(withJSONObject: merged.value!), media: local.media)
            try await send(selected, revision: server.revision, context: context, remoteChoices: useCloud ? Set(merged.conflicts) : [])
        } else {
            let merged = CloudJSON.merge(base: base, local: try JSONSerialization.jsonObject(with: local.data), remote: remoteValue, preferLocal: !useCloud)
            try await receive(server, replacing: local, context: context, preserving: merged.value)
        }
        pendingSaves.removeValue(forKey: key)
    }
    private func send(_ local: CloudLocalRecord, revision: Int, context: ModelContext, remoteChoices: Set<String> = []) async throws {
        if local.kind == "trip" { try await requireUnifiedSchema() }
        guard !isDeleted(local.key) else { return }
        let hash = try local.fingerprint
        let ancestor = bindings[local.key]?.localPayload
        let beforeSend = try CloudRecordAdapter.records(context).first { $0.key == local.key }
        var paths: [String: String] = [:]
        if let baseline = bindings[local.key]?.payload {
            _ = CloudJSON.transform(try JSONSerialization.jsonObject(with: baseline)) { value in
                if let id = value["id"] as? String, let path = value["cloudPath"] as? String { paths[id] = path }
                return value
            }
        }
        var neededMediaIDs = Set<String>()
        _ = CloudJSON.transform(try JSONSerialization.jsonObject(with: local.data)) { value in
            if let id = value["id"] as? String {
                neededMediaIDs.insert(id.lowercased())
                if let path = value["cloudPath"] as? String { paths[id] = path }
            }
            return value
        }
        for media in local.media where neededMediaIDs.contains(media.id.uuidString.lowercased()) {
            let cacheKey = "\(projectURL)|\(media.localIdentifier)"
            if let path = mediaPaths[cacheKey], try await mediaAvailable(path) { paths[media.id.uuidString] = path; continue }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let asset = try await PhotoLibraryService.exportOriginal(identifier: media.localIdentifier, kind: media.kind, referenceID: media.id, to: directory)
            let bytes = try Data(contentsOf: asset.fileURL)
            let suffix = asset.fileURL.pathExtension.lowercased().filter { $0.isLetter || $0.isNumber }
            let path = "\(UUID().uuidString.lowercased())/\(CloudJSON.digest(bytes)).\(suffix.isEmpty ? "bin" : suffix)"
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
        var body: [String: Any] = ["record_id": local.id.uuidString, "record_kind": local.kind, "record_title": local.title, "record_payload": payload, "expected_revision": revision]
        if let baseline = bindings[local.key]?.payload { body["record_base_payload"] = try JSONSerialization.jsonObject(with: baseline) }
        let rpc = revision == 0 ? "triptrail_save_record" : "triptrail_patch_record"
        if revision > 0 && body["record_base_payload"] == nil { body["record_base_payload"] = NSNull() }
        do {
            let data = try await request("rest/v1/rpc/" + rpc, method: "POST", body: try JSONSerialization.data(withJSONObject: body))
            let decoded = try JSONSerialization.jsonObject(with: data)
            guard let object = decoded as? [String: Any] ?? (decoded as? [[String: Any]])?.first else { throw CloudSyncError.message("保存响应格式错误") }
            let server = try CloudRemoteRecord(object)
            if let current = try CloudRecordAdapter.records(context).first(where: { $0.key == local.key }) {
                let initial = CloudJSON.merge(base: try JSONSerialization.jsonObject(with: ancestor ?? local.data), local: try JSONSerialization.jsonObject(with: beforeSend?.data ?? current.data), remote: try JSONSerialization.jsonObject(with: CloudRecordAdapter.normalized(server.payload, kind: server.kind)), remoteChoices: remoteChoices)
                let merged = CloudJSON.merge(base: try JSONSerialization.jsonObject(with: beforeSend?.data ?? current.data), local: try JSONSerialization.jsonObject(with: current.data), remote: initial.value)
                try await receive(server, replacing: current, context: context, preserving: merged.value, ancestor: ancestor, unresolvedPaths: Set(initial.conflicts).subtracting(remoteChoices))
                if !merged.conflicts.isEmpty || initial.conflicts.contains(where: { !remoteChoices.contains($0) }) { conflicts.insert(local.key) }
            } else {
                bindings[local.key] = CloudBinding(revision: server.revision, baseline: hash, origin: projectURL, payload: server.payload, localPayload: local.data)
            }
            remote.removeAll { $0.key == server.key }; remote.append(server); persist()
            message = "已同步，本地副本已保留"
        } catch {
            if error.localizedDescription.contains("TRIPTRAIL_MEDIA_RETIRED") {
                for media in local.media { mediaPaths.removeValue(forKey: "\(projectURL)|\(media.localIdentifier)") }
                defaults.set(mediaPaths, forKey: "cloud.relational.mediaPaths")
            }
            throw error
        }
    }
    private func receive(_ server: CloudRemoteRecord, replacing local: CloudLocalRecord?, context: ModelContext, preserving: Any? = nil, ancestor: Data? = nil, unresolvedPaths: Set<String> = []) async throws {
        guard !isDeleted(server.key) else { return }
        let before = try local?.fingerprint
        let object = try JSONSerialization.jsonObject(with: CloudRecordAdapter.normalized(server.payload, kind: server.kind))
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
        let baselineData = try CloudRecordAdapter.normalized(JSONSerialization.data(withJSONObject: restored), kind: server.kind)
        let merged = preserving.map { value in CloudJSON.transform(value) { media in
            var result = media
            if let id = media["id"] as? String, let identifier = identifiers[id], (media["localIdentifier"] as? String ?? "").isEmpty { result["localIdentifier"] = identifier }
            return result
        } } ?? restored
        try CloudRecordAdapter.apply(JSONSerialization.data(withJSONObject: merged), kind: server.kind, context: context)
        var localBaseline = baselineData
        if let ancestor, !unresolvedPaths.isEmpty {
            let hybrid = CloudJSON.retainingAncestor(try JSONSerialization.jsonObject(with: baselineData), ancestor: try JSONSerialization.jsonObject(with: ancestor), paths: unresolvedPaths)
            localBaseline = try JSONSerialization.data(withJSONObject: hybrid!)
        }
        bindings[server.key] = CloudBinding(revision: server.revision, baseline: try CloudJSON.fingerprint(baselineData), origin: projectURL, payload: server.payload, localPayload: localBaseline)
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
        if http.statusCode == 409 {
            throw CloudSyncError.message("HTTP 409：云端内容刚有新的修改，本地已保留，请再次保存")
        }
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

struct CloudContentDifference: Identifiable {
    let id: String
    let label: String
    let cloud: String
    let local: String
    static func compare(cloud: Data, local: Data) throws -> [CloudContentDifference] {
        let labels = ["title": "标题", "destination": "目的地", "licensePlate": "车牌", "note": "补充说明", "journalNote": "回忆", "journalSummary": "旅程回忆", "summary": "回忆", "journalDetails": "当天说明", "details": "当天说明", "arrangementNote": "补充说明", "supplementalInfo": "补充说明", "journalSupplement": "补充记录", "city": "城市", "startDate": "开始日期", "endDate": "结束日期", "date": "日期", "startTime": "开始时间", "endTime": "结束时间", "timeLabel": "时间", "isTimePending": "时间待定", "isFixedTime": "固定时间", "executionStatusRaw": "完成状态", "categoryRaw": "类型", "attractionTypeRaw": "景点类型", "transportRaw": "交通方式", "locationModeRaw": "地点形式", "placeName": "地点", "placeAddress": "地点地址", "originName": "出发地", "originAddress": "出发地地址", "destinationName": "目的地", "destinationAddress": "目的地地址", "address": "地址", "cost": "花费", "reservationInfo": "预约信息", "sortOrder": "顺序", "latitude": "纬度", "longitude": "经度", "originLatitude": "出发地纬度", "originLongitude": "出发地经度", "destinationLatitude": "目的地纬度", "destinationLongitude": "目的地经度", "coverZoom": "封面缩放", "coverOffsetX": "封面水平位置", "coverOffsetY": "封面垂直位置", "isFavorite": "收藏状态", "isCompleted": "完成状态", "isAutomaticCompletionOverridden": "手动完成状态"]
        func flatten(_ value: Any, key: String = "", parent: String = "") -> [String: (String, String)] {
            var result: [String: (String, String)] = [:]
            guard let object = value as? [String: Any] else { return result }
            let title = object["title"] as? String ?? ""
            let heading = [parent, title].filter { !$0.isEmpty }.joined(separator: " / ")
            for field in labels.keys where object[field] != nil {
                let raw = object[field]!
                var text = raw is NSNull ? "" : String(describing: raw)
                if ["startDate", "endDate", "date", "startTime", "endTime"].contains(field), let number = raw as? NSNumber {
                    let date = Date(timeIntervalSince1970: number.doubleValue / 1000)
                    text = date.formatted(date: .abbreviated, time: field.hasSuffix("Time") ? .shortened : .omitted)
                }
                if ["isTimePending", "isFixedTime"].contains(field), let flag = raw as? Bool { text = flag ? "是" : "否" }
                result[key + "/" + field] = ([heading, labels[field]!].filter { !$0.isEmpty }.joined(separator: " · "), text)
            }
            result[key + "/exists"] = (heading.isEmpty ? "内容" : heading, "存在")
            for collection in ["days", "items", "entries"] {
                for child in object[collection] as? [[String: Any]] ?? [] {
                    let id = (child["id"] as? String ?? "").lowercased()
                    result.merge(flatten(child, key: key + "/" + collection + "/" + id, parent: heading)) { _, new in new }
                }
            }
            if let media = object["media"] as? [[String: Any]] {
                for asset in media {
                    let id = (asset["id"] as? String ?? "").lowercased()
                    let caption = asset["caption"] as? String ?? ""
                    let kind = asset["kindRaw"] as? String ?? ""
                    let order = (asset["sortOrder"] as? Int ?? 0) + 1
                    result[key + "/media/" + id] = (heading + " · 照片与视频", "第 \(order) 项 · \(kind == "视频" || kind == "video" ? "视频" : "照片")" + (caption.isEmpty ? "" : " · " + caption))
                }
            }
            if let cover = object["coverMedia"] as? [String: Any] {
                let identity = (cover["id"] as? String ?? "").lowercased()
                result[key + "/cover"] = (heading + " · 封面", identity)
            }
            for field in object.keys where labels[field] == nil && !["id", "days", "items", "entries", "media", "coverMedia", "localIdentifier", "cloudPath"].contains(field) && !field.lowercased().hasSuffix("id") && !field.lowercased().hasSuffix("ids") {
                let raw = object[field]!
                if !(raw is [Any]) && !(raw is [String: Any]) {
                    result[key + "/" + field] = (heading + " · " + field, raw is NSNull ? "" : String(describing: raw))
                }
            }
            return result
        }
        let remote = flatten(CloudJSON.businessValue(try JSONSerialization.jsonObject(with: cloud)))
        let device = flatten(CloudJSON.businessValue(try JSONSerialization.jsonObject(with: local)))
        return Set(remote.keys).union(device.keys).sorted().compactMap { key in
            let left = remote[key]; let right = device[key]
            guard left?.1 != right?.1 else { return nil }
            return CloudContentDifference(id: key, label: right?.0 ?? left?.0 ?? "内容", cloud: key.hasSuffix("/cover") ? (left == nil ? "未设置" : "云端封面") : left?.1 ?? "—", local: key.hasSuffix("/cover") ? (right == nil ? "未设置" : "本地封面") : right?.1 ?? "—")
        }
    }
}
