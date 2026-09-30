import SwiftData
import SwiftUI

struct CloudDataView: View {
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
                    NavigationLink("☁️ \(title)") { CloudLibraryView(kind: kind) }
                        .disabled(!cloud.configured)
                }
                Button("立即同步") { Task { await cloud.sync(context: context) } }.disabled(!cloud.configured || cloud.busy)
                if cloud.busy { ProgressView("正在同步…") }
                if !cloud.message.isEmpty { Text(cloud.message).font(.footnote) }
            }
        }
        .navigationTitle("云端数据")

    }
}

struct CloudLibraryView: View {
    let kind: String
    @Environment(\.modelContext) private var context
    @ObservedObject private var cloud = CloudSyncService.shared
    @Query private var trips: [Trip]
    @Query private var stories: [TravelStory]
    @Query private var items: [ItineraryItem]
    @State private var error: String?
    @State private var resolution: String?
    private var locals: [CloudLocalRecord] { (try? CloudRecordAdapter.records(context).filter { $0.kind == kind }) ?? [] }
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
                        HStack { Text(local.title.isEmpty ? "未命名" : local.title); Spacer(); CloudBadge(id: local.id, kind: kind) }
                        if cloud.conflicts.contains(local.key) {
                            Button("本地与云端都有修改 · 选择版本") { resolution = local.key }
                        } else if cloud.linked(local.key) {
                            Text("云端项目").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("上传并设为云端模式") { run {
                                try cloud.enable(local, context: context); await cloud.sync(context: context, kind: kind, recordID: local.id)
                            } }.disabled(!cloud.configured || cloud.busy)
                        }
                    }
                }
                if locals.isEmpty { Text("暂无本地内容").foregroundStyle(.secondary) }
            }

        }
        .navigationTitle("☁️ " + (kind == "trip" ? "旅程" : kind == "story" ? "足迹" : "收藏"))
        .toolbar { Button { Task { await cloud.sync(context: context, kind: kind, browse: true) } } label: { Image(systemName: "arrow.clockwise") }.disabled(!cloud.configured || cloud.busy) }
        .task { await cloud.sync(context: context, kind: kind, browse: true, automatic: true) }
        .confirmationDialog("同一条内容在本地和云端都已修改。请选择要保留的版本，另一版本将被替换。", isPresented: Binding(get: { resolution != nil }, set: { if !$0 { resolution = nil } }), titleVisibility: .visible) {
            if let key = resolution {
                Button("使用云端版本", role: .destructive) { run { try await cloud.resolve(key, useCloud: true, context: context) }; resolution = nil }
                Button("以本地版本更新云端", role: .destructive) { run { try await cloud.resolve(key, useCloud: false, context: context) }; resolution = nil }
            }
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
    @ObservedObject private var cloud = CloudSyncService.shared
    var body: some View {
        if cloud.linked("\(kind):\(id.uuidString.lowercased())") { Image(systemName: "cloud").foregroundStyle(.secondary).accessibilityLabel("云端模式，本地副本已保留") }
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
            CloudSyncService.shared.uploadAfterEdit(context: context)
        }, content: sheet)
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
            CloudSyncService.shared.uploadAfterEdit(context: context)
        }, content: sheet)
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
            if !cloud.linked(key) {
                Button("设为云端", systemImage: "cloud") {
                    Task {
                        do {
                            try context.save()
                            guard let record = try CloudRecordAdapter.records(context).first(where: { $0.key == key }) else { return }
                            try cloud.enable(record, context: context)
                            await cloud.sync(context: context, kind: kind, recordID: id)
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
