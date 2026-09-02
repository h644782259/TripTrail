import SwiftData
import SwiftUI

struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var itineraryItems: [ItineraryItem]

    @State private var searchText = ""
    @State private var selectedCategory: PlaceCategory?
    @State private var showsNewFavorite = false
    @State private var favoriteToEdit: ItineraryItem?
    @State private var favoriteToDelete: ItineraryItem?

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
                                        onDelete: { favoriteToDelete = favorite }
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
        .searchable(text: $searchText, prompt: "搜索名称、地点或备注")
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
    let favorite: ItineraryItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onEdit) {
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
                        .lineLimit(2)

                    if !favorite.locationSummary.isEmpty {
                        Label(favorite.locationSummary, systemImage: "mappin.and.ellipse")
                            .lineLimit(2)
                    }

                    if !favorite.note.isEmpty {
                        Text(favorite.note)
                            .lineLimit(3)
                    }

                    Spacer(minLength: 0)

                    if !favorite.distanceText.isEmpty || favorite.cost > 0 {
                        HStack(spacing: 8) {
                            if !favorite.distanceText.isEmpty {
                                Label(favorite.distanceText, systemImage: "arrow.triangle.turn.up.right.diamond")
                                    .lineLimit(1)
                            }
                            if favorite.cost > 0 {
                                Text("¥\(favorite.cost, specifier: "%.0f")")
                            }
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                .padding(14)
                .background(Color.tripSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.tripMist.opacity(0.38), lineWidth: 0.8)
                }
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开编辑收藏")

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
            itineraryItems.filter { selectedIDs.contains($0.id) },
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
                            Text("可多选；导入后会按当天已有安排的结束时间依次排入，时间仍可逐项编辑。")
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
                    Button("导入 \(selectedIDs.count) 项") { importSelected() }
                        .disabled(selectedIDs.isEmpty)
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
