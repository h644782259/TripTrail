import SwiftData
import SwiftUI

struct CloudDataView: View {
    @State private var confirmPull = false
    @Environment(\.modelContext) private var context
    @ObservedObject private var cloud = CloudSyncService.shared
    var body: some View {
        List {
            if !cloud.configured {
                Section {
                    Text("当前安装包未配置云端服务，可继续使用本地功能。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("云端内容") {
                ForEach([("trip", "旅程"), ("story", "足迹"), ("favorite", "收藏")], id: \.0) { kind, title in
                    NavigationLink(title) { CloudLibraryView(kind: kind) }
                        .disabled(!cloud.configured)
                }
                Button("拉取云端最新数据") { confirmPull = true }.disabled(!cloud.configured || cloud.busy)
                if cloud.busy { ProgressView("正在同步…") }
                if !cloud.message.isEmpty { Text(cloud.message).font(.footnote) }
            }
        }
        .navigationTitle("云端数据")
        .alert("拉取云端最新数据？", isPresented: $confirmPull) {
            Button("拉取并覆盖", role: .destructive) { Task { await cloud.pullAllCloudVersions(context: context) } }
            Button("取消", role: .cancel) { }
        } message: {
            Text("将用云端最新内容覆盖所有已关联的旅程、足迹和收藏。未同步的本地修改将丢失，纯本地项目不受影响。")
        }

    }
}

struct CloudLibraryEntry: Identifiable {
    let id: UUID
    let kind: String
    let title: String
    var key: String { "\(kind):\(id.uuidString.lowercased())" }

    static func entries(trips: [Trip], items: [ItineraryItem], kind: String) -> [CloudLibraryEntry] {
        if kind == "favorite" {
            return items.filter(\.isFavorite).map { CloudLibraryEntry(id: $0.id, kind: "favorite", title: $0.title) }
        }
        return trips.filter { (TripTimelineOrdering.phase(for: $0) == .history) == (kind == "story") }
            .map { CloudLibraryEntry(id: $0.id, kind: "trip", title: $0.title) }
    }
}

struct CloudLibraryView: View {
    let kind: String
    @Environment(\.modelContext) private var context
    @ObservedObject private var cloud = CloudSyncService.shared
    @Query private var trips: [Trip]
    @Query private var items: [ItineraryItem]
    @State private var error: String?
    @State private var resolution: String?
    private var storageKind: String { kind == "story" ? "trip" : kind }
    private var locals: [CloudLibraryEntry] {
        CloudLibraryEntry.entries(trips: trips, items: items, kind: kind)
    }
    var body: some View {
        List {
            Section {
                if !cloud.configured { Text("当前安装包未配置云端服务") }
                if cloud.busy { ProgressView("正在同步…") }
                if !cloud.message.isEmpty { Text(cloud.message).font(.footnote) }
            }
            Section("本地内容") {
                ForEach(locals) { local in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(local.title.isEmpty ? "未命名" : local.title); Spacer(); CloudBadge(id: local.id, kind: local.kind) }
                        if cloud.conflicts.contains(local.key) {
                            Button("内容冲突 · 查看详情") { resolution = local.key }
                        } else if cloud.linked(local.key) {
                            Text("云端项目").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("上传并设为云端模式") { run {
                                guard let record = try CloudRecordAdapter.records(context).first(where: { $0.key == local.key }) else { return }
                                try cloud.enable(record, context: context)
                                await cloud.uploadPending(context: context, key: local.key)
                            } }.disabled(!cloud.configured || cloud.busy)
                        }
                    }
                }
                if locals.isEmpty { Text("暂无本地内容").foregroundStyle(.secondary) }
            }

        }
        .navigationTitle(kind == "trip" ? "旅程" : kind == "story" ? "足迹" : "收藏")
        .toolbar { Button { Task { await cloud.sync(context: context, kind: storageKind, browse: true) } } label: { Image(systemName: "arrow.clockwise") }.disabled(!cloud.configured || cloud.busy) }
        .task { await cloud.sync(context: context, kind: storageKind, browse: true, automatic: true) }
        .sheet(isPresented: Binding(get: { resolution != nil }, set: { if !$0 { resolution = nil } })) {
            if let resolution { CloudConflictDetailsView(key: resolution) }
        }
        .alert("云端数据", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) { Task { do { try await action() } catch { self.error = error.localizedDescription } } }
}
struct CloudBadge: View {
    let id: UUID
    let kind: String
    var expandedHitTarget = false
    @Environment(\.modelContext) private var context
    @ObservedObject private var cloud = CloudSyncService.shared
    @State private var preview: CloudRemoteRecord?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        if cloud.linked("\(kind):\(id.uuidString.lowercased())") {
            Button {
                loading = true
                Task {
                    defer { loading = false }
                    do { preview = try await cloud.previewCloudVersion(id: id, kind: kind) }
                    catch { self.error = error.localizedDescription }
                }
            } label: {
                ZStack {
                    if loading { ProgressView().controlSize(.small) }
                    else { Image(systemName: "cloud").foregroundStyle(.secondary) }
                }
                .frame(minWidth: expandedHitTarget ? 44 : nil, minHeight: expandedHitTarget ? 44 : nil)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(loading)
            .accessibilityLabel("读取云端版本")
            .alert("用云端版本覆盖本地？", isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
                if let server = preview {
                    Button("覆盖本地", role: .destructive) {
                        loading = true
                        Task {
                            defer { loading = false }
                            do { try await cloud.replaceWithPreview(server, context: context) }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                if let server = preview {
                    Text("已读取“\(server.title)”的云端版本（版本 \(server.revision)）。覆盖后，未同步的本地修改将丢失，云端内容不会改变。")
                }
            }
            .alert("读取云端内容失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}
struct CloudTitle: View {
    let id: UUID
    let kind: String
    let title: String
    var trailingBadge = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title)
            if trailingBadge { Spacer(minLength: 5) }
            CloudBadge(id: id, kind: kind)
        }
    }
}

// Sheet dismissal is a user action, not a background polling trigger. Only dirty linked records upload.
private struct CloudItemSheet<Item: Identifiable, Sheet: View>: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var item: Item?
    var onDismiss: (() -> Void)?
    let sheet: (Item) -> Sheet
    func body(content: Content) -> some View {
        content.sheet(item: $item, onDismiss: {
            onDismiss?()
        }) { value in
            sheet(value).modifier(TripEditorPresentation())
        }
    }
}
private struct CloudBooleanSheet<Sheet: View>: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var isPresented: Bool
    var onDismiss: (() -> Void)?
    let sheet: () -> Sheet
    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: {
            onDismiss?()
        }) {
            sheet().modifier(TripEditorPresentation())
        }
    }
}
extension View {
    func cloudEditSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        modifier(CloudItemSheet(item: item, onDismiss: onDismiss, sheet: content))
    }
    func cloudEditSheet<Sheet: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Sheet) -> some View {
        modifier(CloudBooleanSheet(isPresented: isPresented, onDismiss: onDismiss, sheet: content))
    }
}


struct CloudModeAction: View {
    let id: UUID
    let kind: String
    @Environment(\.modelContext) private var context
    @ObservedObject private var cloud = CloudSyncService.shared
    @State private var error: String?
    private var key: String { "\(kind):\(id.uuidString.lowercased())" }
    var body: some View {
        Group {
            if cloud.linked(key) {
                if cloud.conflicts.contains(key) {
                    Button("内容冲突 · 重新加载", systemImage: "arrow.clockwise") {
                        Task { do { try await cloud.resolve(key, useCloud: true, context: context) }
                            catch { self.error = error.localizedDescription } }
                    }.disabled(cloud.busy)
                }
            } else {
                Button("设为云端", systemImage: "cloud") {
                    Task {
                        do {
                            try context.save()
                            guard let record = try CloudRecordAdapter.records(context).first(where: { $0.key == key }) else { return }
                            try cloud.enable(record, context: context)
                            await cloud.uploadPending(context: context, key: key)
                            if !cloud.message.isEmpty { error = cloud.message }
                        } catch { self.error = error.localizedDescription }
                    }
                }
                .disabled(cloud.busy || !cloud.configured)
            }
        }
        .alert("云端数据", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("确定") { error = nil }
        } message: { Text(error ?? "") }
    }
}

struct RecycleBinView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var cloud = CloudSyncService.shared
    var body: some View {
        List {
            let entries = cloud.recycle.filter { $0.expiresAt > Date() && ($0.recoverable || $0.data != nil) }.sorted { $0.expiresAt > $1.expiresAt }
            if entries.isEmpty { Text("回收站为空").foregroundStyle(.secondary) }
            ForEach(entries, id: \.key) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                        Text("\(entry.kind == "trip" ? "旅程" : entry.kind == "story" ? "足迹" : "收藏") · \(entry.pending ? "待同步删除" : "保留至 " + entry.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if entry.cloud { Image(systemName: "cloud").foregroundStyle(.secondary) }
                    Button("恢复") { Task { await cloud.restore(entry, context: context) } }.disabled(cloud.busy)
                }
            }
            if !cloud.message.isEmpty { Text(cloud.message).font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("回收站（保留一天）")
        .task { await cloud.refreshRecycle(context: context) }
        .refreshable { await cloud.refreshRecycle(context: context) }
    }
}

struct CloudVersionNotice: View {
    let kind: String
    @Environment(\.modelContext) private var context
    @ObservedObject private var cloud = CloudSyncService.shared
    @State private var error: String?
    @State private var showsDetails = false
    var body: some View {
        if let record = cloud.remote.first(where: { $0.kind == kind && cloud.conflicts.contains($0.key) }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("“\(record.title)”与云端内容不同").font(.subheadline.bold()).lineLimit(2)
                Text("检测到内容冲突，请选择使用“云端”/“本地”版本")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("云端") { resolve(record.key, useCloud: true) }
                    Button("本地") { resolve(record.key, useCloud: false) }
                    Button("查看详情") { showsDetails = true }
                    Spacer()
                }.font(.subheadline).disabled(cloud.busy)
                if cloud.busy { ProgressView().controlSize(.small) }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .padding(12)
            .background(Color.tripSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.tripLake.opacity(0.3)))
            .padding(.horizontal, 12).padding(.vertical, 4)
            .sheet(isPresented: $showsDetails) { CloudConflictDetailsView(key: record.key) }
        }
    }
    private func resolve(_ key: String, useCloud: Bool) {
        error = nil
        Task {
            do { try await cloud.resolve(key, useCloud: useCloud, context: context) }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct CloudSaveNotice: View {
    let id: UUID
    let kind: String
    @Environment(\.modelContext) private var context
    @ObservedObject private var cloud = CloudSyncService.shared
    @State private var showsDetails = false
    private var key: String { "\(kind):\(id.uuidString.lowercased())" }
    private func resolve(_ useCloud: Bool) {
        Task { do { try await cloud.resolve(key, useCloud: useCloud, context: context) }
            catch { cloud.message = error.localizedDescription } }
    }
    var body: some View {
        if cloud.conflicts.contains(key) {
            VStack(alignment: .leading, spacing: 8) {
                Text("检测到内容冲突，请选择使用“云端”/“本地”版本")
                HStack {
                    Button("查看详情") { showsDetails = true }
                    Button("云端") { resolve(true) }
                    Button("本地") { resolve(false) }
                }.disabled(cloud.busy)
            }.font(.footnote).padding().background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .sheet(isPresented: $showsDetails) { CloudConflictDetailsView(key: key) }
        }
    }
}

struct CloudConflictDetailsView: View {
    let key: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cloud = CloudSyncService.shared
    @State private var rows: [CloudContentDifference] = []
    @State private var revision: Int?
    @State private var loading = true
    @State private var resolving = false
    @State private var error: String?
    var body: some View {
        TripNavigationStack {
            VStack(spacing: 0) {
                if loading { ProgressView().padding() }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("云端").frame(maxWidth: .infinity); Text("本地").frame(maxWidth: .infinity) }
                            .font(.subheadline.bold()).foregroundStyle(Color.tripLakeText)
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.label).font(.caption).foregroundStyle(.secondary)
                                HStack(alignment: .top, spacing: 8) {
                                    Text(row.cloud.isEmpty ? "未填写" : row.cloud).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Color.tripLake.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                                    Text(row.local.isEmpty ? "未填写" : row.local).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                                }.font(.subheadline).textSelection(.enabled)
                            }
                        }
                        if !loading && rows.isEmpty { Text("当前未发现可展示的内容差异").foregroundStyle(.secondary) }
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    }.padding()
                }
                HStack {
                    Button("使用云端") { choose(true) }.frame(maxWidth: .infinity)
                    Button("使用本地") { choose(false) }.frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).disabled(loading || resolving || cloud.busy || revision == nil).padding()
            }
            .navigationTitle("内容差异").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(resolving) }
                ToolbarItem(placement: .confirmationAction) { Button("刷新") { Task { await load() } }.disabled(loading || resolving) }
            }
            .task { await load() }
        }.interactiveDismissDisabled(resolving)
    }
    @MainActor private func load() async {
        loading = true; error = nil; revision = nil
        defer { loading = false }
        do {
            let parts = key.split(separator: ":")
            guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return }
            let remote = try await cloud.previewCloudVersion(id: id, kind: String(parts[0]))
            guard let local = try CloudRecordAdapter.records(context).first(where: { $0.key == key }) else { return }
            rows = try CloudContentDifference.compare(cloud: CloudRecordAdapter.normalized(remote.payload, kind: remote.kind), local: local.data)
            revision = remote.revision
        } catch { self.error = error.localizedDescription }
    }
    private func choose(_ useCloud: Bool) {
        resolving = true; error = nil
        Task {
            defer { resolving = false }
            do { try await cloud.resolve(key, useCloud: useCloud, context: context, expectedRevision: revision); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}
