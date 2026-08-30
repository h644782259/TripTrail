import SwiftData
import SwiftUI

struct IncomingSharedJourney: Identifiable {
    let id = UUID()
    let fileURL: URL
    let preview: SharedJourneyPreview
}

struct SharedJourneyImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let incoming: IncomingSharedJourney
    @State private var isImported = false
    @State private var isImporting = false
    @State private var message: String?

    private var preview: SharedJourneyPreview { incoming.preview }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header
                    if !preview.overview.isEmpty {
                        Text(preview.overview)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardSurface()
                    }
                    ForEach(Array(preview.days.enumerated()), id: \.element.id) { index, day in
                        daySection(day, index: index)
                    }
                    Text(preview.summary.mediaCount > 0
                         ? "收藏时会将 \(preview.summary.mediaCount) 个媒体原件写入系统相簿。"
                         : "收藏后会保存为可编辑的独立副本。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 12)
                }
                .padding()
            }
            .background(Color.tripCanvas)
            .navigationTitle("来自旅迹的分享")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: collect) {
                    Label(
                        isImported ? "已添加到我的旅迹" : (isImporting ? "正在添加…" : "添加到我的旅迹"),
                        systemImage: isImported ? "checkmark.circle.fill" : (isImporting ? "hourglass" : "bookmark.fill")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImported || isImporting)
                .padding()
                .background(.bar)
            }
            .alert("收藏提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(preview.summary.kind.displayName, systemImage: preview.summary.kind == .trip ? "map.fill" : "book.closed.fill")
                .font(.caption.bold())
                .foregroundStyle(Color.tripLake)
            Text(preview.summary.title)
                .font(.largeTitle.bold())
            if !preview.summary.destination.isEmpty {
                Label(preview.summary.destination, systemImage: "mappin.and.ellipse")
                    .font(.headline)
            }
            Text("\(preview.startDate.chineseDateText) — \(preview.endDate.chineseDateText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(preview.summary.dayCount) 天 · \(preview.summary.placeCount) 个地点")
                .font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func daySection(_ day: SharedJourneyPreview.Day, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(day.title.isEmpty ? "第 \(index + 1) 天" : day.title)
                    .font(.headline)
                Spacer()
                Text(day.date.compactDayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !day.narrative.isEmpty {
                Text(day.narrative)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if day.places.isEmpty {
                Text("这一天没有具体地点")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(day.places) { place in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(Color.tripLake)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(place.title).font(.subheadline.bold())
                                Spacer(minLength: 8)
                                Text(place.time).font(.caption2).foregroundStyle(.secondary)
                            }
                            let detail = [place.category, place.address, place.note]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · ")
                            if !detail.isEmpty {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .cardSurface()
    }

    private func collect() {
        isImporting = true
        Task {
            do {
                let result = try await SharedJourneyService.importJourney(from: incoming.fileURL, into: modelContext)
                isImported = true
                message = result.wasAlreadyPresent
                    ? "这份\(result.summary.kind.displayName)已经在你的旅迹中。"
                    : "已添加\(result.summary.importDescription)，现在可以在\(result.summary.kind == .trip ? "行程" : "足迹")页继续编辑。"
            } catch {
                message = error.localizedDescription
            }
            isImporting = false
        }
    }
}
