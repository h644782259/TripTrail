import SwiftData
import SwiftUI

struct ScreenshotItineraryImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let trip: Trip
    let draft: ItineraryJourneyDraft
    let onBack: (() -> Void)?

    @State private var days: [ItineraryJourneyDayDraft]
    @State private var attachScreenshots: Bool
    @State private var showsRawText = false

    init(trip: Trip, draft: ItineraryJourneyDraft, onBack: (() -> Void)? = nil) {
        self.trip = trip
        self.draft = draft
        self.onBack = onBack
        _days = State(initialValue: draft.days)
        _attachScreenshots = State(initialValue: !draft.sourceAssetIdentifiers.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("识别结果", value: "\(days.count) 天")
                    Text(targetRangeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(days.indices), id: \.self) { dayIndex in
                    let targetNumber = firstTargetDayNumber + dayIndex
                    Section {
                        TextField("当天路线", text: $days[dayIndex].routeTitle)

                        ForEach(Array(days[dayIndex].items.indices), id: \.self) { itemIndex in
                            importItemEditor(
                                item: $days[dayIndex].items[itemIndex],
                                number: itemIndex + 1
                            )
                        }
                    } header: {
                        Text("第 \(targetNumber) 天")
                    }
                }

                if !draft.sourceAssetIdentifiers.isEmpty {
                    Section("原截图") {
                        Toggle("附到导入后的第一项安排", isOn: $attachScreenshots)
                    }
                }

                Section {
                    DisclosureGroup("查看识别原文", isExpanded: $showsRawText) {
                        Text(draft.rawText)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("确认识别结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(onBack == nil ? "取消" : "返回") {
                        if let onBack { onBack() } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加 \(days.count) 天") { save() }
                        .disabled(days.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func importItemEditor(
        item: Binding<ItineraryJourneyItemDraft>,
        number: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: item.isIncluded) {
                Label(
                    item.wrappedValue.title.isEmpty ? "安排 \(number)" : item.wrappedValue.title,
                    systemImage: item.wrappedValue.category.symbol
                )
                .font(.subheadline.weight(.semibold))
            }

            if item.wrappedValue.isIncluded {
                DisclosureGroup("调整内容") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("地点", text: item.title)
                        Picker("类型", selection: item.category) {
                            ForEach(PlaceCategory.allCases) { category in
                                Label(category.rawValue, systemImage: category.symbol).tag(category)
                            }
                        }
                        TwoTapDateRangePicker(
                            title: "日期与时间",
                            startTitle: "开始",
                            endTitle: "结束",
                            startDate: item.startTime,
                            endDate: item.endTime,
                            preservesTimeComponents: true,
                            showsTimeSelection: true
                        )
                        TextField("目的地或地址", text: item.address)
                        TextField("路程", text: item.distanceText)
                        TextField("预约信息", text: item.reservationInfo, axis: .vertical)
                        TextField("备注", text: item.note, axis: .vertical)
                            .lineLimit(2...6)
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }

    private var firstTargetDayNumber: Int {
        trip.sortedDays.count + 1
    }

    private var targetRangeText: String {
        guard !days.isEmpty else { return "没有可添加的日期" }
        let end = firstTargetDayNumber + days.count - 1
        if firstTargetDayNumber == end { return "将新增为第 \(end) 天" }
        return "将新增为第 \(firstTargetDayNumber)–\(end) 天"
    }

    private func save() {
        let editedDraft = ItineraryJourneyDraft(
            days: days,
            rawText: draft.rawText,
            sourceAssetIdentifiers: draft.sourceAssetIdentifiers
        )
        let createdDays = JourneyImportApplyService.append(
            editedDraft,
            to: trip,
            attachSourceImages: attachScreenshots
        )
        for day in createdDays {
            modelContext.insert(day)
            for item in day.items {
                modelContext.insert(item)
                for media in item.media { modelContext.insert(media) }
            }
        }
        dismiss()
    }
}
