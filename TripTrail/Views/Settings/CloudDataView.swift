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
    @State private var dismissedKey: String?
    @State private var detailsKey: String?
    @State private var error: String?
    private var record: CloudRemoteRecord? {
        cloud.remote.first { $0.kind == kind && cloud.conflicts.contains($0.key) }
    }
    var body: some View {
        Color.clear.frame(height: 0)
            .alert("内容冲突", isPresented: Binding(
                get: { record != nil && record?.key != dismissedKey && !cloud.presentedConflictKeys.contains(record?.key ?? "") && detailsKey == nil && error == nil },
                set: { if !$0 { dismissedKey = record?.key; if let record { cloud.presentedConflictKeys.insert(record.key) } } }
            )) {
                if let record {
                    Button("查看详情") { cloud.presentedConflictKeys.insert(record.key); dismissedKey = record.key; detailsKey = record.key }
                    Button("使用云端") { resolve(record.key, useCloud: true) }
                    Button("使用本地") { resolve(record.key, useCloud: false) }
                }
            } message: {
                Text("“\(record?.title ?? "内容")”存在冲突，请选择使用“云端”或“本地”版本。")
            }
            .sheet(isPresented: Binding(get: { detailsKey != nil }, set: { if !$0 { detailsKey = nil } })) {
                if let detailsKey { CloudConflictDetailsView(key: detailsKey) }
            }
            .alert("处理失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil; dismissedKey = nil } })) {
                Button("确定") { error = nil; dismissedKey = nil }
            } message: { Text(error ?? "") }
            .onChange(of: cloud.conflicts) { _, conflicts in
                if let dismissedKey, !conflicts.contains(dismissedKey) { self.dismissedKey = nil; cloud.presentedConflictKeys.remove(dismissedKey) }
            }
    }
    private func resolve(_ key: String, useCloud: Bool) {
        cloud.presentedConflictKeys.insert(key)
        dismissedKey = key
        Task {
            do { try await cloud.resolve(key, useCloud: useCloud, context: context) }
            catch { self.error = error.localizedDescription }
        }
    }
}

// The root presenter owns conflict alerts so detail screens do not show duplicate banners.
struct CloudSaveNotice: View {
    let id: UUID
    let kind: String
    var body: some View { EmptyView() }
}

struct CloudConflictDetailsView: View {
    let key: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cloud = CloudSyncService.shared
    @State private var rows: [CloudContentDifference] = []
    @State private var selections: [String: Bool] = [:]
    @State private var localFingerprint: String?
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
                                Picker("使用版本", selection: Binding(get: { selections[row.id] }, set: { selections[row.id] = $0 })) {
                                    Text("请选择").tag(Optional<Bool>.none)
                                    Text("云端").tag(Optional(true))
                                    Text("本地").tag(Optional(false))
                                }.pickerStyle(.segmented).disabled(resolving)

                            }
                        }
                        if !loading && error == nil && revision != nil && rows.isEmpty { Text("内容已一致，无需选择版本").foregroundStyle(.secondary) }
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    }.padding()
                }
                HStack {
                    Button("全部选云端") { selections = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, true) }) }.frame(maxWidth: .infinity)
                    Button("全部选本地") { selections = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, false) }) }.frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).disabled(loading || resolving || cloud.busy || revision == nil || rows.isEmpty).padding(.horizontal)
                Button("确认提交") { choose(false) }.buttonStyle(.borderedProminent)
                    .disabled(loading || resolving || cloud.busy || revision == nil || rows.isEmpty || selections.count != rows.count).padding()

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
        loading = true; error = nil; revision = nil; selections = [:]
        defer { loading = false }
        do {
            let parts = key.split(separator: ":")
            guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return }
            let remote = try await cloud.previewCloudVersion(id: id, kind: String(parts[0]))
            guard let local = try CloudRecordAdapter.records(context).first(where: { $0.key == key }) else { return }
            let remoteData = try CloudRecordAdapter.normalized(remote.payload, kind: remote.kind)
            localFingerprint = try local.fingerprint
            rows = try cloud.conflictRows(key, server: remote, local: local)
            let equivalent = try rows.isEmpty && cloud.clearEquivalentConflict(key, cloud: remoteData, local: local.data)
            if rows.isEmpty && !equivalent {
                try await cloud.resolve(key, useCloud: false, context: context, expectedRevision: remote.revision)
            }
            if rows.isEmpty && !equivalent && cloud.conflicts.contains(key) {
                rows = [CloudContentDifference(id: "baseline", label: "同步状态", cloud: "云端版本已更新", local: "同步基准或内部记录不同，请重新加载云端版本")]
            }
            revision = remote.revision
        } catch { self.error = error.localizedDescription }
    }
    private func choose(_ useCloud: Bool) {
        resolving = true; error = nil
        Task {
            defer { resolving = false }
            do { try await cloud.resolve(key, useCloud: useCloud, context: context, expectedRevision: revision, choices: Set(selections.filter { $0.value }.map(\.key)), selectedPaths: Set(selections.keys), expectedLocalFingerprint: localFingerprint); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}
