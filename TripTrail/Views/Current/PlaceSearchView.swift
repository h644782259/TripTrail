import SwiftUI

struct PlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let initialQuery: String
    let onSelect: (ResolvedPlace) -> Void

    @State private var query: String
    @State private var results: [ResolvedPlace] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    init(initialQuery: String, onSelect: @escaping (ResolvedPlace) -> Void) {
        self.initialQuery = initialQuery
        self.onSelect = onSelect
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        TripNavigationStack {
            Group {
                if isSearching && results.isEmpty {
                    ProgressView("正在查找地点…")
                } else if let errorMessage, results.isEmpty {
                    ContentUnavailableView("搜索失败", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                } else if results.isEmpty {
                    ContentUnavailableView("没有找到地点", systemImage: "mappin.slash", description: Text("试试加入城市、景区或街道名称。"))
                } else {
                    List(results) { place in
                        Button {
                            onSelect(place)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.tripLake)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.name).font(.headline).foregroundStyle(.primary)
                                    Text(place.address.isEmpty ? "地址信息暂缺" : place.address)
                                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("选择准确地点")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "地点、地址或城市")
            .submitLabel(.search)
            .onSubmit(of: .search) { performSearch() }
            .onChange(of: query) { _, newValue in
                scheduleSearch(for: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSearching { ProgressView() }
                    else { Button("搜索") { performSearch() }.disabled(query.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
            }
            .task { await search(keyword: initialQuery) }
            .onDisappear { searchTask?.cancel() }
        }
    }

    private func performSearch() {
        searchTask?.cancel()
        searchTask = Task { await search(keyword: query) }
    }

    private func scheduleSearch(for keyword: String) {
        searchTask?.cancel()
        errorMessage = nil
        results = []
        let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await search(keyword: normalized)
        }
    }

    @MainActor
    private func search(keyword: String) async {
        let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        errorMessage = nil
        do {
            let newResults = try await PlaceSearchService.search(normalized)
            guard !Task.isCancelled,
                  query.trimmingCharacters(in: .whitespacesAndNewlines) == normalized else { return }
            results = newResults
        } catch {
            guard !Task.isCancelled,
                  query.trimmingCharacters(in: .whitespacesAndNewlines) == normalized else { return }
            results = []
            errorMessage = "请检查网络后重试，或补充更完整的地点名称。"
        }
        if query.trimmingCharacters(in: .whitespacesAndNewlines) == normalized {
            isSearching = false
        }
    }
}
