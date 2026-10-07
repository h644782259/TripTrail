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
    @State private var favoriteToOpen: ItineraryItem?
    @State private var placeMessage: String?

    @ScaledMetric(relativeTo: .body) private var minimumCardHeight: CGFloat = 240
    private func columns(for width: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 2)
    }

    private func cardHeight(in size: CGSize) -> CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad && size.width >= 600 {
            let cardWidth = (size.width - 24 - 4) / 2
            return cardWidth * 4 / 3
        }
        return max(minimumCardHeight, (size.height - 12) / 2)
    }

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
                GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 8) {

                        if favorites.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                                .frame(minHeight: 320)
                        } else {
                            LazyVGrid(columns: columns(for: geometry.size.width), spacing: 4) {
                                ForEach(favorites) { favorite in
                                    FavoriteArrangementCard(
                                        favorite: favorite,
                                        cardHeight: cardHeight(in: geometry.size),
                                        onEdit: { favoriteToEdit = favorite },
                                        onDelete: { favoriteToDelete = favorite },
                                        onNavigate: { favoriteToOpen = favorite }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 96)
                }
                }
            }
        }
        .background(Color.tripCanvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            TripListSearchBar(text: $searchText, prompt: "搜索名称、城市、地点或备注") { filterMenu }
                .padding(.horizontal).padding(.top, 8).padding(.bottom, 2)
                .background(Color.tripCanvas)
        }
        .overlay(alignment: .bottomTrailing) {
            TripFloatingCreateButton(title: "新建收藏") { showsNewFavorite = true }
        }
        .cloudEditSheet(isPresented: $showsNewFavorite) {
            ItemEditorView(day: nil, mode: .favorite)
        }
        .cloudEditSheet(item: $favoriteToEdit) {
            ItemEditorView(day: nil, item: $0, mode: .favorite)
                .task(id: $0.id) { await CloudSyncService.shared.sync(context: modelContext, kind: "favorite", recordID: favoriteToEdit?.id, automatic: true) }
        }
        .tripBottomSheet(item: $favoriteToOpen) { favorite in
            NavigationOptionsSheet(
                onAmap: {
                    guard let target = favorite.locationTargets.last else {
                        placeMessage = "请先为这条收藏填写地点。"
                        return
                    }
                    Task {
                        let result = await AmapService.openPlace(name: target.name, address: target.address)
                        placeMessage = result.message(destinationName: target.displayName)
                    }
                },
                onXiaohongshu: { openDiscovery(.xiaohongshu, title: favorite.title) },
                onDouyin: { openDiscovery(.douyin, title: favorite.title) }
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
                guard CloudSyncService.shared.trash(id: favorite.id, kind: "favorite", context: modelContext) else { return }
                favoriteToDelete = nil
            }
            Button("取消", role: .cancel) { favoriteToDelete = nil }
        } message: { favorite in
            Text("“\(favorite.title)”将移入回收站，24 小时内可恢复。云端收藏会同步删除，已导入旅程的安排不受影响。")
        }
    }

    private func openDiscovery(_ platform: PlaceDiscoveryPlatform, title: String) {
        Task {
            let opened = await PlaceDiscoveryService.open(platform, name: title, address: "")
            if !opened {
                placeMessage = "暂时无法打开\(platform.displayName)，请检查网络或稍后重试。"
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("类型", selection: $selectedCategory) {
                Label("全部类型", systemImage: "square.grid.2x2").tag(nil as PlaceCategory?)
                ForEach(PlaceCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.symbol).tag(Optional(category))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedCategory?.rawValue ?? "全部类型")
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline)
            .foregroundStyle(Color.tripLakeText)
            .fixedSize()
            .frame(minHeight: 44)
        }
        .accessibilityLabel(selectedCategory == nil ? "按类型筛选收藏" : "按类型筛选收藏，已有条件")
    }

}

private struct FavoriteArrangementCard: View {
    let favorite: ItineraryItem
    let cardHeight: CGFloat
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onNavigate: () -> Void

    private var footerCity: String {
        let value = FavoriteArrangementService.city(for: favorite)
        return value == "未设置城市" ? "" : value
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 4) {
                Button(action: onNavigate) {
                    CloudTitle(id: favorite.id, kind: "favorite", title: favorite.title.isEmpty ? "未命名收藏" : favorite.title, trailingBadge: true)
                        .font(.headline).foregroundStyle(Color.tripLakeText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("选择高德地图、小红书或抖音打开；长按打开功能菜单")

                }

                if let media = favorite.media.sorted(by: MediaReference.precedes).first {
                    Color.clear.frame(maxHeight: .infinity)
                        .overlay {
                            AssetThumbnail(identifier: media.localIdentifier, showsVideoBadge: media.kind == .video)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    FavoriteDefaultCover(category: favorite.category)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if !favorite.note.isEmpty {
                    Text(favorite.note)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.tail)
                }
                GeometryReader { proxy in
                    let baseFont = UIFont.preferredFont(forTextStyle: .caption1)
                    let price = favorite.cost > 0 ? String(format: "¥%.0f", favorite.cost) : ""
                    let textWidth = [favorite.category.rawValue, footerCity].reduce(CGFloat.zero) {
                        $0 + ($1 as NSString).size(withAttributes: [.font: baseFont]).width
                    }
                    let fittingScale = min(1, max(0.5, (proxy.size.width - 42) / max(1, textWidth)))
                    let scale = footerCity.count > 4 ? max(0.85, fittingScale) : fittingScale
                    let priceWidth = (price as NSString).size(withAttributes: [.font: baseFont]).width
                    let showsPrice = !price.isEmpty && (textWidth + priceWidth) * scale + 42 <= proxy.size.width
                    HStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: favorite.arrangementSymbol).font(.tripSystem(size: 14))
                            Text(favorite.category.rawValue).fixedSize()
                        }
                        .foregroundStyle(Color.tripLakeText)
                        .padding(.horizontal, 6).padding(.vertical, 5)
                        .background(Color.tripLake.opacity(0.11), in: Capsule())
                        Spacer(minLength: 0)
                        if !footerCity.isEmpty {
                            Text(footerCity).lineLimit(1).truncationMode(.tail)
                                .fixedSize(horizontal: footerCity.count <= 4, vertical: false)
                        }
                        if showsPrice { Text(price).fixedSize() }
                    }
                    .font(.tripSystem(size: baseFont.pointSize * scale))
                    .frame(width: proxy.size.width, alignment: .leading)
                }
                .frame(height: 30)

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
                .contextMenu {
                    CloudModeAction(id: favorite.id, kind: "favorite")
                    Divider()
                    Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
                }
                .accessibilityAction(named: "编辑收藏", onEdit)
                .accessibilityAction(named: "删除收藏", onDelete)
                .accessibilityHint("轻点编辑，长按打开功能菜单")


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
        if let trip = day.trip {
            Task {
                for item in created {
                    await CloudSyncService.shared.uploadPending(context: modelContext,
                        key: "trip:\(trip.id.uuidString.lowercased())", entityID: item.id)
                }
            }
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

            Image(systemName: favorite.arrangementSymbol)
                            .foregroundStyle(Color.tripLakeText)
                .frame(width: 34, height: 34)
                .background(Color.tripLake.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                CloudTitle(id: favorite.id, kind: "favorite", title: favorite.title)
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

private struct FavoriteDefaultCover: View {
    let category: PlaceCategory
    private var style: (Color, String) {
        switch category {
        case .attraction: (Color(red: 0.24, green: 0.55, blue: 0.46), "mountain.2.fill")
        case .restaurant: (Color(red: 0.78, green: 0.43, blue: 0.27), "fork.knife")
        case .hotel: (Color(red: 0.43, green: 0.46, blue: 0.68), "bed.double.fill")
        case .transport: (Color(red: 0.28, green: 0.52, blue: 0.70), "tram.fill")
        default: (Color(red: 0.67, green: 0.52, blue: 0.32), "suitcase.rolling.fill")
        }
    }
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [style.0.opacity(0.18), style.0.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.3)).frame(width: proxy.size.width * 0.8)
                    .offset(x: proxy.size.width * 0.4, y: -proxy.size.height * 0.3)
                Circle().fill(style.0.opacity(0.14)).frame(width: proxy.size.width * 1.4)
                    .offset(x: -proxy.size.width * 0.3, y: proxy.size.height * 0.5)
                Image(systemName: style.1).resizable().scaledToFit()
                    .frame(width: proxy.size.width * 0.43, height: proxy.size.height * 0.45)
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: style.0.opacity(0.2), radius: 10, y: 5)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityLabel("\(category.rawValue)默认封面")
    }
}
