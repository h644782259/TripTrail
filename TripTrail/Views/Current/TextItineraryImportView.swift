import PhotosUI
import SwiftUI
import UIKit

struct TextItineraryImportView: View {
    @Environment(\.dismiss) private var dismiss
    let onCreated: ((Trip) -> Void)?
    let isCreatingTrip: Bool
    let trip: Trip
    let referenceDate: Date
    let targetDay: TripDay?
    let embedded: Bool

    @State private var imagePreviews: [UIImage?] = []
    @State private var imageMode = false
    @State private var imageItems: [PhotosPickerItem] = []
    @State private var inputText = ""
    @State private var parsedDraft: ItineraryJourneyDraft?
    @State private var importError: String?
    @State private var isRecognizing = false
    @FocusState private var isInputFocused: Bool

    init(trip: Trip, referenceDate: Date, targetDay: TripDay? = nil, isCreatingTrip: Bool = false, embedded: Bool = false, onCreated: ((Trip) -> Void)? = nil) {
        self.embedded = embedded
        self.onCreated = onCreated
        self.isCreatingTrip = isCreatingTrip
        self.trip = trip
        self.referenceDate = referenceDate
        self.targetDay = targetDay
    }

    var body: some View {
        Group {
            if let parsedDraft {
                ScreenshotItineraryImportView(
                    trip: trip,
                    draft: parsedDraft,
                    targetDay: targetDay,
                    isCreatingTrip: isCreatingTrip,
                    onCreated: onCreated,
                    onBack: { self.parsedDraft = nil },
                    onRetryRecognition: {
                        self.parsedDraft = nil
                        parseText()
                    }
                )
            } else {
                inputView
            }
        }
    }

    private var inputView: some View {
        SmartImportNavigation(embedded: embedded) {
            SmartImportLayout(embedded: embedded) {
                Section {
                    SmartImportModeTabs(imageMode: $imageMode)
                }
                if imageMode {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            if imageItems.isEmpty {
                                Text(targetDay == nil ? "上传多天行程，可包含多个安排" : "上传一天的行程，可包含多个安排")
                                    .font(.body).foregroundStyle(.tertiary)
                                    .padding(.horizontal, 5).padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                                ForEach(imageItems.indices, id: \.self) { index in
                                    Color.clear.aspectRatio(1, contentMode: .fit)
                                        .overlay {
                                            if index < imagePreviews.count, let image = imagePreviews[index] {
                                                Image(uiImage: image).resizable().scaledToFill()
                                            } else { ProgressView() }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(alignment: .topTrailing) {
                                            Button { imageItems.remove(at: index) } label: {
                                                Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, .black.opacity(0.55))
                                                    .frame(width: 36, height: 36)
                                            }.buttonStyle(.plain).accessibilityLabel("移除截图")
                                        }
                                }
                                if imageItems.count < (targetDay == nil ? 6 : 3) {
                                    PhotosPicker(selection: $imageItems, maxSelectionCount: targetDay == nil ? 6 : 3, matching: .images) {
                                        RoundedRectangle(cornerRadius: 12).fill(Color.tripLake.opacity(0.045))
                                            .aspectRatio(1, contentMode: .fit)
                                            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.tripLake.opacity(0.52), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])) }
                                            .overlay { Image(systemName: "plus").font(.title2).foregroundStyle(Color.tripLake) }
                                    }.buttonStyle(.plain).accessibilityLabel("添加截图")
                                }
                            }
                        }
                        .listRowSeparator(.hidden)
                        .task(id: imageItems) {
                            imagePreviews = []
                            var previews: [UIImage?] = []
                            for item in imageItems {
                                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                                    previews.append(image)
                                } else { previews.append(nil) }
                            }
                            guard !Task.isCancelled else { return }
                            imagePreviews = previews
                        }
                    }
                } else {
                Section {
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text(targetDay == nil ? "粘贴多天行程，可包含多个安排" : "粘贴一天的行程，可包含多个安排")
                                .font(.body).foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $inputText).clearableText($inputText, alignment: .topTrailing)
                            .focused($isInputFocused)
                            .frame(height: embedded ? nil : 230)
                            .frame(maxHeight: embedded ? .infinity : nil)
                            .scrollContentBackground(.hidden)
                            .clipped()
                    }
                    .frame(height: embedded ? nil : 230)
                            .frame(maxHeight: embedded ? .infinity : nil)
                    .clipped()

                }
                }
            }
            .disabled(isRecognizing)
            .scrollDismissesKeyboard(.interactively)
            .smartImportTitle(embedded: embedded)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { isInputFocused = false }
                }
            }
            .smartImportFooter(embedded: embedded) {
                Button {
                    parseText()
                } label: {
                    HStack {
                        if isRecognizing { ProgressView().controlSize(.small) }
                        Label(isRecognizing ? "识别中…" : "开始识别", systemImage: "wand.and.stars")
                    }
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                    .foregroundStyle(
                        trimmedInputIsEmpty && !isRecognizing
                            ? Color.tripInk.opacity(0.58)
                            : Color.white
                    )
                    .padding(.vertical, 13)
                    .background(
                        trimmedInputIsEmpty && !isRecognizing
                            ? Color.tripMist.opacity(0.52)
                            : Color.tripLake,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    isRecognizing
                        || trimmedInputIsEmpty
                )
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color.clear)
            }
            .alert("文本识别", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                if !trimmedInputIsEmpty {
                    Button("重试") {
                        importError = nil
                        parseText()
                    }
                }
                Button("知道了", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private var trimmedInputIsEmpty: Bool {
        imageMode ? imageItems.isEmpty : inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func recognitionCapability(_ title: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(Color.tripLake)
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            importError = "剪贴板里还没有可识别的文本。"
            return
        }
        inputText = text
        isInputFocused = false
    }

    private static let exampleText = """
    9月25日
    09:00–10:30 游览上海世纪公园
    地点：上海世纪公园

    14:00–15:00 前往虹桥机场
    出发地：上海世纪公园
    目的地：上海虹桥国际机场 T2
    """

    private func parseText() {
        isInputFocused = false
        isRecognizing = true
        Task { @MainActor in
            defer { isRecognizing = false }
            do {
                if imageMode {
                    var images: [Data] = []
                    var identifiers: [String] = []
                    for item in imageItems {
                        if let data = try await item.loadTransferable(type: Data.self) {
                            images.append(data)
                            if let id = item.itemIdentifier { identifiers.append(id) }
                        }
                    }
                    guard !images.isEmpty else { throw ScreenshotItineraryImportError.unreadableImage }
                    parsedDraft = try await SmartItineraryRecognitionService.recognizeJourney(
                        imageDatas: images, referenceDate: referenceDate, sourceAssetIdentifiers: identifiers
                    )
                } else {
                parsedDraft = try await SmartItineraryRecognitionService.recognizeJourneyText(
                    inputText,
                    referenceDate: referenceDate
                )
                }
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

struct SmartImportNavigation<Content: View>: View {
    let embedded: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        if embedded { content() } else { TripNavigationStack { content() } }
    }
}
struct SmartImportLayout<Content: View>: View {
    let embedded: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        if embedded { VStack(alignment: .leading, spacing: 16) { content() }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }
        else { Form { content() } }
    }
}
extension View {
    @ViewBuilder func smartImportTitle(embedded: Bool) -> some View {
        if embedded { self } else { self.navigationTitle("智能录入") }
    }
}
struct SmartImportModeTabs: View {
    @Binding var imageMode: Bool
    var body: some View {
        HStack(spacing: 12) {
            modeButton("文字", image: false)
            modeButton("截图", image: true)
        }
    }
    private func modeButton(_ title: String, image: Bool) -> some View {
        Button { imageMode = image } label: {
            VStack(spacing: 6) {
                Text(title).font(.headline.weight(imageMode == image ? .semibold : .regular)).padding(.vertical, 9)
                Capsule().fill(imageMode == image ? Color.tripLake : .clear).frame(height: 2)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
                .foregroundStyle(imageMode == image ? Color.tripLakeText : .secondary)
        }.buttonStyle(.plain)
        .accessibilityAddTraits(imageMode == image ? .isSelected : [])
    }
}

extension View {
    @ViewBuilder func smartImportFooter<Footer: View>(embedded: Bool, @ViewBuilder footer: () -> Footer) -> some View {
        self.padding(embedded ? 12 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 0, content: footer)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.tripInk.opacity(0.12), lineWidth: 1))
    }
}

struct SmartCreationMethodTabs: View {
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(["智能录入", "普通新建"], id: \.self) { method in
                Button { selection = method } label: {
                    HStack(spacing: 5) {
                        if method == "智能录入" { Image(systemName: "wand.and.stars").font(.caption) }
                        Text(method).font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(selection == method ? Color.tripSurface : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                .foregroundStyle(selection == method ? Color.tripLakeText : .secondary)
                .accessibilityAddTraits(selection == method ? .isSelected : [])
            }
        }.padding(3).background(Color.tripMist.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SmartEditorLayout<Content: View>: View {
    let smart: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        if smart {
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(.horizontal, 24).padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(uiColor: .systemGroupedBackground))
        } else {
            Form { content() }
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}
