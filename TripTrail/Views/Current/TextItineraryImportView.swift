import SwiftUI

struct TextItineraryImportView: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var inputText = ""
    @State private var parsedDraft: ItineraryJourneyDraft?
    @State private var importError: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Group {
            if let parsedDraft {
                ScreenshotItineraryImportView(
                    trip: trip,
                    draft: parsedDraft,
                    onBack: { self.parsedDraft = nil }
                )
            } else {
                inputView
            }
        }
    }

    private var inputView: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text("粘贴一整段行程文本\n支持 Day 1、Day 2…或第1天、第2天…\n也可以只输入一段安排")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $inputText)
                            .focused($isInputFocused)
                            .frame(minHeight: 210)
                            .scrollContentBackground(.hidden)
                    }
                    HStack {
                        Spacer()
                        if !inputText.isEmpty {
                            Button("清空", role: .destructive) { inputText = "" }
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("粘贴或输入")
                } footer: {
                    Text("多天内容会按顺序创建并追加到当前行程末尾。")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("文本智能录入")
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
                    Label("识别内容", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .alert("文本识别", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("知道了", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func parseText() {
        isInputFocused = false
        do {
            parsedDraft = try ScreenshotItineraryImportService.parseJourneyInputText(
                inputText,
                referenceDate: trip.startDate
            )
        } catch {
            importError = error.localizedDescription
        }
    }
}
