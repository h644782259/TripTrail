import SwiftData
import SwiftUI

struct ScreenshotItineraryImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let trip: Trip
    let draft: ItineraryJourneyDraft
    let targetDay: TripDay?
    let onBack: (() -> Void)?
    let onRetryRecognition: (() -> Void)?

    @State private var days: [ItineraryJourneyDayDraft]
    @State private var attachScreenshots: Bool

    init(
        trip: Trip,
        draft: ItineraryJourneyDraft,
        targetDay: TripDay? = nil,
        onBack: (() -> Void)? = nil,
        onRetryRecognition: (() -> Void)? = nil
    ) {
        self.trip = trip
        self.draft = draft
        self.targetDay = targetDay
        self.onBack = onBack
        self.onRetryRecognition = onRetryRecognition
        _days = State(initialValue: Self.scopedDays(from: draft.days, targetDay: targetDay))
        _attachScreenshots = State(initialValue: !draft.sourceAssetIdentifiers.isEmpty)
    }

    var body: some View {
        TripNavigationStack {
            Form {
                Section {
                    if let recognitionNotice = draft.recognitionNotice {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(recognitionNotice, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.orange)
                                .accessibilityLabel("识别方式提示：\(recognitionNotice)")

                            if let onRetryRecognition {
                                Button {
                                    onRetryRecognition()
                                } label: {
                                    Label("重试大模型", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        recognitionMetric(value: days.count, label: "天")
                        Divider().frame(height: 28)
                        recognitionMetric(value: includedItems.count, label: "个安排")
                        Divider().frame(height: 28)
                        recognitionMetric(value: recognizedLocationCount, label: "个地点")
                    }
                    .frame(maxWidth: .infinity)

                    Text(importPreviewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("识别概览")
                } footer: {
                    Text("下方内容已全部展开，可在保存前修改。")
                }

                ForEach(Array(days.indices), id: \.self) { dayIndex in
                    Section {
                        ForEach(Array(days[dayIndex].items.indices), id: \.self) { itemIndex in
                            importItemEditor(
                                item: $days[dayIndex].items[itemIndex],
                                number: itemIndex + 1
                            )
                            if itemIndex < days[dayIndex].items.count - 1 {
                                Divider()
                            }
                        }
                    } header: {
                        Text(dayHeaderText(for: days[dayIndex], dayIndex: dayIndex))
                    }
                }

                if !draft.sourceAssetIdentifiers.isEmpty {
                    Section("原截图") {
                        Toggle("附到导入后的第一项安排", isOn: $attachScreenshots)
                    }
                }

            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(targetDay == nil ? "录入整段旅程" : "录入当天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(onBack == nil ? "取消" : "返回") {
                        if let onBack { onBack() } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
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
        VStack(alignment: .leading, spacing: 12) {
            Label(
                item.wrappedValue.title.isEmpty ? "安排 \(number)" : item.wrappedValue.title,
                systemImage: item.wrappedValue.category.symbol
            )
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        editorFieldLabel("安排名称/说明")
                        TextField("例如：游览世纪公园", text: item.title)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        editorFieldLabel("补充说明")
                        TextField("例如：先寄存行李", text: item.note, axis: .vertical)
                            .lineLimit(2...5)
                    }
                    Picker("类型", selection: item.category) {
                        ForEach(PlaceCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.symbol).tag(category)
                        }
                    }
                    TwoTapDateRangePicker(
                        title: "时间",
                        startTitle: "开始",
                        endTitle: "结束",
                        startDate: item.startTime,
                        endDate: item.endTime,
                        preservesTimeComponents: true,
                        showsTimeSelection: true,
                        showsEndpointTitles: false
                    )
                    Picker("地点类型", selection: item.locationMode) {
                        ForEach(ArrangementLocationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if item.wrappedValue.locationMode == .single {
                        VStack(alignment: .leading, spacing: 6) {
                            editorFieldLabel("地点名称")
                            TextField("例如：上海世纪公园", text: item.placeName)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            editorFieldLabel("详细地址（选填）")
                            TextField("用于提高地图匹配准确度", text: item.placeAddress, axis: .vertical)
                                .lineLimit(1...3)
                        }
                    } else {
                        locationFields(title: "出发地", name: item.originName, address: item.originAddress)
                        locationFields(title: "目的地", name: item.destinationName, address: item.destinationAddress)
                    }
                    HStack(spacing: 8) {
                        Text("¥").foregroundStyle(.secondary)
                        TextField("输入金额", value: item.cost, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    Picker("前往方式", selection: item.transport) {
                        ForEach(TransportMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        editorFieldLabel("路程说明")
                        TextField("例如：6.8 km · 25 分钟", text: item.distanceText)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        editorFieldLabel("预约信息")
                        TextField("航班号、车次或订单信息", text: item.reservationInfo, axis: .vertical)
                            .lineLimit(1...4)
                    }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    private var firstTargetDayNumber: Int {
        trip.sortedDays.count + 1
    }

    private var includedItems: [ItineraryJourneyItemDraft] {
        days.flatMap(\.items).filter(\.isIncluded)
    }

    private var recognizedLocationCount: Int {
        includedItems.reduce(into: 0) { count, item in
            switch item.locationMode {
            case .single:
                if !item.placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
            case .route:
                if !item.originName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
                if !item.destinationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
            }
        }
    }

    private var importPreviewText: String {
        if let targetDay {
            let title = targetDay.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let dayTitle = title.isEmpty ? targetDay.date.formatted(.dateTime.month().day()) : title
            return "将把 \(includedItems.count) 个安排添加到“\(dayTitle)”。"
        }
        let editedDraft = ItineraryJourneyDraft(
            days: days,
            rawText: draft.rawText,
            sourceAssetIdentifiers: draft.sourceAssetIdentifiers
        )
        let preview = JourneyImportApplyService.preview(editedDraft, for: trip)
        if preview.existingDayCount > 0 {
            return "将合并到 \(preview.existingDayCount) 个已有日期，并新增 \(preview.newDayCount) 天。"
        }
        return "将新增 \(preview.newDayCount) 天到当前旅程。"
    }

    private static func scopedDays(
        from sourceDays: [ItineraryJourneyDayDraft],
        targetDay: TripDay?
    ) -> [ItineraryJourneyDayDraft] {
        guard let targetDay else { return sourceDays }
        let notes = sourceDays
            .map(\.note)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return [
            ItineraryJourneyDayDraft(
                sourceDayNumber: 1,
                date: targetDay.date,
                routeTitle: "",
                note: notes,
                items: sourceDays.flatMap(\.items)
            )
        ]
    }

    private func recognitionMetric(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline.bold())
                .foregroundStyle(Color.tripLake)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func dayHeaderText(for day: ItineraryJourneyDayDraft, dayIndex: Int) -> String {
        let targetNumber = targetDayNumber(for: day, fallbackIndex: dayIndex)
        guard let date = day.date else { return "第 \(targetNumber) 天" }
        return "\(date.formatted(.dateTime.month().day().weekday())) · 第 \(targetNumber) 天"
    }

    private func targetDayNumber(
        for day: ItineraryJourneyDayDraft,
        fallbackIndex: Int
    ) -> Int {
        guard let date = day.date else { return firstTargetDayNumber + fallbackIndex }
        let calendar = Calendar.current
        let editedDraft = ItineraryJourneyDraft(
            days: days,
            rawText: draft.rawText,
            sourceAssetIdentifiers: draft.sourceAssetIdentifiers
        )
        let plannedDates = JourneyImportApplyService.preview(editedDraft, for: trip).dates
        var dates = trip.days.map { calendar.startOfDay(for: $0.date) }
        for plannedDate in plannedDates where !dates.contains(where: {
            calendar.isDate($0, inSameDayAs: plannedDate)
        }) {
            dates.append(calendar.startOfDay(for: plannedDate))
        }
        dates.sort()
        let targetDate = calendar.startOfDay(for: date)
        return (dates.firstIndex { calendar.isDate($0, inSameDayAs: targetDate) } ?? fallbackIndex) + 1
    }

    private func save() {
        let editedDraft = ItineraryJourneyDraft(
            days: days,
            rawText: draft.rawText,
            sourceAssetIdentifiers: draft.sourceAssetIdentifiers
        )
        let result = JourneyImportApplyService.append(
            editedDraft,
            to: trip,
            attachSourceImages: attachScreenshots
        )
        for day in result.createdDays { modelContext.insert(day) }
        for item in result.createdItems { modelContext.insert(item) }
        for media in result.createdMedia { modelContext.insert(media) }
        dismiss()
    }

    private func editorFieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func locationFields(
        title: String,
        name: Binding<String>,
        address: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            editorFieldLabel(title)
            TextField("地点名称", text: name)
            TextField("详细地址（选填）", text: address, axis: .vertical)
                .lineLimit(1...3)
        }
    }
}
