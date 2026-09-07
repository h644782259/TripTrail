import SwiftData
import SwiftUI
import UIKit

struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var itineraryItems: [ItineraryItem]

    @State private var searchText = ""
    @State private var selectedCategory: PlaceCategory?
    @State private var showsNewFavorite = false
    @State private var favoriteToEdit: ItineraryItem?
    @State private var favoriteToDelete: ItineraryItem?
    @State private var locationToOpen: JourneyLocationTarget?
    @State private var placeMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12, alignment: .top)
    ]

    private var favorites: [ItineraryItem] {
        FavoriteArrangementService.filtered(
            itineraryItems,
            searchText: searchText,
            category: selectedCategory
        )
    }

    private var favoriteCount: Int {
        itineraryItems.filter(\.isFavorite).count
    }

    var body: some View {
        Group {
            if favoriteCount == 0 {
                ContentUnavailableView {
                    Label("还没有收藏", systemImage: "heart.circle")
                } description: {
                    Text("把想去的景点、餐厅或特别地点先收起来，有计划时再导入旅程。")
                } actions: {
                    Button("新建收藏", systemImage: "plus") {
                        showsNewFavorite = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        filterBar

                        if favorites.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                                .frame(minHeight: 320)
                        } else {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(favorites) { favorite in
                                    FavoriteArrangementCard(
                                        favorite: favorite,
                                        onEdit: { favoriteToEdit = favorite },
                                        onDelete: { favoriteToDelete = favorite },
                                        onNavigate: { locationToOpen = $0 }
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 96)
                }
            }
        }
        .background(Color.tripCanvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索名称、城市、地点或备注")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsNewFavorite = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建收藏")
            }
        }
        .sheet(isPresented: $showsNewFavorite) {
            ItemEditorView(day: nil, mode: .favorite)
        }
        .sheet(item: $favoriteToEdit) {
            ItemEditorView(day: nil, item: $0, mode: .favorite)
        }
        .sheet(item: $locationToOpen) { target in
            NavigationOptionsSheet(
                onAmap: {
                    Task {
                        let result = await AmapService.openPlace(name: target.name, address: target.address)
                        placeMessage = result.message(destinationName: target.displayName)
                    }
                },
                onXiaohongshu: { openDiscovery(.xiaohongshu, target: target) },
                onDouyin: { openDiscovery(.douyin, target: target) }
            )
        }
        .alert("提示", isPresented: Binding(
            get: { placeMessage != nil },
            set: { if !$0 { placeMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { placeMessage = nil }
        } message: {
            Text(placeMessage ?? "")
        }
        .alert("删除收藏？", isPresented: Binding(
            get: { favoriteToDelete != nil },
            set: { if !$0 { favoriteToDelete = nil } }
        ), presenting: favoriteToDelete) { favorite in
            Button("确认删除", role: .destructive) {
                modelContext.delete(favorite)
                favoriteToDelete = nil
            }
            Button("取消", role: .cancel) { favoriteToDelete = nil }
        } message: { favorite in
            Text("“\(favorite.title)”将从收藏中删除，已导入旅程的安排不受影响。")
        }
    }

    private func openDiscovery(_ platform: PlaceDiscoveryPlatform, target: JourneyLocationTarget) {
        Task {
            let opened = await PlaceDiscoveryService.open(platform, name: target.name, address: target.address)
            if !opened {
                placeMessage = "暂时无法打开\(platform.displayName)，请检查网络或稍后重试。"
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Label("\(favoriteCount) 个想去的地方", systemImage: "heart.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.tripInk)

            Spacer(minLength: 8)

            Menu {
                Button {
                    selectedCategory = nil
                } label: {
                    if selectedCategory == nil {
                        Label("全部类型", systemImage: "checkmark")
                    } else {
                        Text("全部类型")
                    }
                }
                ForEach(PlaceCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        if selectedCategory == category {
                            Label(category.rawValue, systemImage: "checkmark")
                        } else {
                            Label(category.rawValue, systemImage: category.symbol)
                        }
                    }
                }
            } label: {
                Label(selectedCategory?.rawValue ?? "全部类型", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(14)
        .background(Color.tripSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct FavoriteArrangementCard: View {
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 280
    let favorite: ItineraryItem
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onNavigate: (JourneyLocationTarget) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: favorite.category.symbol)
                        Text(favorite.category.rawValue)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.tripLakeText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.tripLake.opacity(0.11), in: Capsule())

                    Text(favorite.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)

                    let city = FavoriteArrangementService.city(for: favorite)
                    if !city.isEmpty, city != "未设置城市" {
                        Label(city, systemImage: "building.2")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }

                    ForEach(favorite.locationTargets) { target in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Button { onNavigate(target) } label: {
                                Label(target.displayName, systemImage: target.role == .origin ? "location.circle" : "mappin.and.ellipse")
                                    .lineLimit(1)
                                    .multilineTextAlignment(.leading)
                                    .foregroundStyle(Color.tripLakeText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("选择地图或搜索平台打开地点")
                            LocationCopyButton(text: target.displayName)
                        }
                    }

                    if !favorite.note.isEmpty {
                        Text(favorite.note)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    if favorite.cost > 0 {
                        HStack(spacing: 8) {
                            if favorite.cost > 0 {
                                Text("¥\(favorite.cost, specifier: "%.0f")")
                            }
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: cardHeight - 28, alignment: .topLeading)
                .padding(14)
                .background(Color.tripSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.tripMist.opacity(0.38), lineWidth: 0.8)
                }
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .onTapGesture(perform: onEdit)
                .accessibilityAction(named: "编辑收藏", onEdit)

            Menu {
                Button("编辑收藏", systemImage: "pencil", action: onEdit)
                Button("删除收藏", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.bold())
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(favorite.title)更多操作")
        }
    }
}

struct FavoriteImportSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var itineraryItems: [ItineraryItem]

    let day: TripDay
    @State private var searchText = ""
    @State private var selectedCategory: PlaceCategory?
    @State private var selectedIDs: Set<UUID> = []

    private var favorites: [ItineraryItem] {
        FavoriteArrangementService.filtered(
            itineraryItems,
            searchText: searchText,
            category: selectedCategory
        )
    }

    private var selectedFavorites: [ItineraryItem] {
        FavoriteArrangementService.filtered(
            itineraryItems.filter { favorite in selectedIDs.contains(favorite.id) && !day.items.contains { $0.sourceFavoriteID == favorite.id } },
            searchText: "",
            category: nil
        )
    }

    var body: some View {
        TripNavigationStack {
            Group {
                if itineraryItems.contains(where: \.isFavorite) {
                    List {
                        Section {
                            categoryPicker

                        } footer: {
                            Text("可多选，接在当天安排之后，时间可调整。")
                        }

                        Section("收藏安排") {
                            if favorites.isEmpty {
                                ContentUnavailableView.search(text: searchText)
                            } else {
                                ForEach(favorites) { favorite in
                                    Button {
                                        toggle(favorite)
                                    } label: {
                                        FavoriteSelectionRow(
                                            favorite: favorite,
                                            isSelected: selectedIDs.contains(favorite.id)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(day.items.contains { $0.sourceFavoriteID == favorite.id })
                                    if day.items.contains(where: { $0.sourceFavoriteID == favorite.id }) {
                                        Text("已在当天").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "收藏夹还是空的",
                        systemImage: "heart.circle",
                        description: Text("先到“收藏”页录入想去的地方。")
                    )
                }
            }
            .navigationTitle("从收藏导入")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索收藏")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入 \(selectedFavorites.count) 项") { importSelected() }
                        .disabled(selectedFavorites.isEmpty)
                }
            }
        }
    }

    private var categoryPicker: some View {
        Picker("类型筛选", selection: $selectedCategory) {
            Text("全部").tag(PlaceCategory?.none)
            ForEach(PlaceCategory.allCases) { category in
                Text(category.rawValue).tag(Optional(category))
            }
        }
        .pickerStyle(.menu)
    }

    private func toggle(_ favorite: ItineraryItem) {
        if selectedIDs.contains(favorite.id) {
            selectedIDs.remove(favorite.id)
        } else {
            selectedIDs.insert(favorite.id)
        }
    }

    private func importSelected() {
        let created = FavoriteArrangementService.importFavorites(selectedFavorites, into: day)
        for item in created {
            modelContext.insert(item)
            item.media.forEach(modelContext.insert)
        }
        dismiss()
    }
}

private struct FavoriteSelectionRow: View {
    let favorite: ItineraryItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.tripLake : .secondary)

            Image(systemName: favorite.category.symbol)
                            .foregroundStyle(Color.tripLakeText)
                .frame(width: 34, height: 34)
                .background(Color.tripLake.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(favorite.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(favorite.locationSummary.isEmpty ? favorite.category.rawValue : favorite.locationSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(favorite.title)，\(isSelected ? "已选择" : "未选择")")
    }
}


struct LocationCopyButton: View {
    let text: String
    @State private var copied = false
    @State private var copyCount = 0

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            copyCount += 1
        } label: {
            Text(Image(systemName: copied ? "checkmark" : "doc.on.doc"))
                .font(.caption)
                .foregroundStyle(Color.tripLakeText)
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "已复制" : "复制\(text)")
        .overlay(alignment: .topTrailing) {
            if copied {
                Text("已复制").font(.caption2).foregroundStyle(.primary)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .fixedSize().offset(y: -24).allowsHitTesting(false)
            }
        }
        .task(id: copyCount) {
            guard copyCount > 0 else { return }
            do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }
            copied = false
        }
    }
}
