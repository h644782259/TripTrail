import SwiftUI

struct StoryMediaCarousel: View {
    let media: [MediaReference]
    let height: CGFloat
    var onSelect: ((MediaReference) -> Void)?
    var onDelete: ((MediaReference) -> Void)?

    @State private var currentPage = 0

    init(
        media: [MediaReference],
        height: CGFloat,
        onSelect: ((MediaReference) -> Void)? = nil,
        onDelete: ((MediaReference) -> Void)? = nil
    ) {
        self.media = media
        self.height = height
        self.onSelect = onSelect
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TabView(selection: $currentPage) {
                ForEach(Array(media.enumerated()), id: \.element.id) { index, item in
                    AssetThumbnail(identifier: item.localIdentifier, showsVideoBadge: item.kind == .video)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect?(item) }
                        .accessibilityLabel(item.kind == .video ? "第 \(index + 1) 个视频" : "第 \(index + 1) 张照片")
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if media.count > 1 {
                    Text("\(min(currentPage + 1, media.count)) / \(media.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.58), in: Capsule())
                        .padding(10)
                        .accessibilityLabel("第 \(min(currentPage + 1, media.count)) 页，共 \(media.count) 页")
                }
            }
            .overlay(alignment: .bottom) {
                if media.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(media.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == currentPage ? Color.white : Color.white.opacity(0.55))
                                .frame(width: index == currentPage ? 14 : 5, height: 5)
                        }
                    }
                    .padding(.bottom, 13)
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: media.map(\.id)) { _, identifiers in
                if identifiers.isEmpty {
                    currentPage = 0
                } else {
                    currentPage = min(currentPage, identifiers.count - 1)
                }
            }

            if let onDelete, !media.isEmpty {
                let safePage = min(currentPage, media.count - 1)
                let item = media[safePage]
                Button(role: .destructive) {
                    onDelete(item)
                } label: {
                    Label(item.kind == .video ? "删除当前视频" : "删除当前照片", systemImage: "trash")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityHint("需要再次确认")
            }
        }
    }
}
