import SwiftUI
import UIKit

struct TextItineraryImportView: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let referenceDate: Date
    let targetDay: TripDay?

    @State private var inputText = ""
    @State private var parsedDraft: ItineraryJourneyDraft?
    @State private var importError: String?
    @State private var isRecognizing = false
    @FocusState private var isInputFocused: Bool

    init(trip: Trip, referenceDate: Date, targetDay: TripDay? = nil) {
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
                    HStack(spacing: 14) {
                        recognitionCapability(targetDay == nil ? "多天行程" : "当天安排", symbol: "calendar")
                        recognitionCapability("时间区间", symbol: "clock")
                        recognitionCapability("起终点", symbol: "arrow.left.arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("识别后会先展示完整结果，确认后才会保存。")
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text("粘贴一整段旅程文本\n支持 Day 1、Day 2…或第1天、第2天…\n也可以只输入一段安排")
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

                    HStack {
                        Button {
                            pasteFromClipboard()
                        } label: {
                            Label("粘贴剪贴板", systemImage: "doc.on.clipboard")
                        }

                        Button {
                            inputText = Self.exampleText
                            isInputFocused = false
                        } label: {
                            Label("填入示例", systemImage: "text.badge.plus")
                        }

                        Spacer(minLength: 8)
                        if !inputText.isEmpty {
                            Button("清空", role: .destructive) { inputText = "" }
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("粘贴或输入")
                } footer: {
                    Text(targetDay == nil ? "会按日期合并或接续到当前旅程。" : "识别结果只会添加到当前选中的这一天。")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(targetDay == nil ? "录入整段旅程" : "录入当天")
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
                        Label(isRecognizing ? "识别中…" : "识别内容", systemImage: "wand.and.stars")
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
                        || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                parsedDraft = try await SmartItineraryRecognitionService.recognizeJourneyText(
                    inputText,
                    referenceDate: referenceDate
                )
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}
