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

    @State private var imagePreviews: [UIImage?] = []
    @State private var imageMode = false
    @State private var imageItems: [PhotosPickerItem] = []
    @State private var inputText = ""
    @State private var parsedDraft: ItineraryJourneyDraft?
    @State private var importError: String?
    @State private var isRecognizing = false
    @FocusState private var isInputFocused: Bool

    init(trip: Trip, referenceDate: Date, targetDay: TripDay? = nil, isCreatingTrip: Bool = false, onCreated: ((Trip) -> Void)? = nil) {
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
        TripNavigationStack {
            Form {
                Section {
                    Picker("录入方式", selection: $imageMode) {
                        Text("文字").tag(false)
                        Text("截图").tag(true)
                    }.pickerStyle(.segmented)
                }
                if imageMode {
                    Section("安排截图") {
                        VStack(alignment: .leading, spacing: 12) {
                            if imageItems.isEmpty {
                                Text(targetDay == nil ? "上传多天行程，可包含多个安排" : "上传一天的行程，可包含多个安排")
                                    .font(.subheadline).foregroundStyle(.secondary)
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
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $inputText)
                            .focused($isInputFocused)
                            .frame(height: 230)
                            .scrollContentBackground(.hidden)
                            .clipped()
                    }
                    .frame(height: 230)
                    .clipped()

                } header: {
                    Text("安排内容")
                }
                }
            }
            .disabled(isRecognizing)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("智能录入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { isInputFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
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
                .background(.bar)
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
