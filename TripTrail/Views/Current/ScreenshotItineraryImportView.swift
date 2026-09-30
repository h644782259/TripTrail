import SwiftData
import SwiftUI

struct ScreenshotItineraryImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let trip: Trip
    let isCreatingTrip: Bool
    let draft: ItineraryJourneyDraft
    let targetDay: TripDay?
    let onCreated: ((Trip) -> Void)?
    let onBack: (() -> Void)?
    let onRetryRecognition: (() -> Void)?

    @State private var newTripTitle: String
    @State private var newTripLicensePlate = ""
    @State private var newTripDestination: String
    @State private var newTripStartDate: Date
    @State private var days: [ItineraryJourneyDayDraft]
    @State private var attachScreenshots: Bool

    init(
        trip: Trip,
        draft: ItineraryJourneyDraft,
        targetDay: TripDay? = nil,
        isCreatingTrip: Bool = false,
        onCreated: ((Trip) -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        onRetryRecognition: (() -> Void)? = nil
    ) {
        self.trip = trip
        self.isCreatingTrip = isCreatingTrip
        self.onCreated = onCreated
        let firstPlace = draft.days.flatMap(\.items).map { $0.placeName.isEmpty ? $0.destinationName : $0.placeName }.first { !$0.isEmpty } ?? ""
        let destination = draft.suggestedDestination.isEmpty ? firstPlace : draft.suggestedDestination
        _newTripDestination = State(initialValue: destination)
        _newTripTitle = State(initialValue: draft.suggestedTitle.isEmpty ? (destination.isEmpty ? "我的新旅程" : "\(destination)之旅") : draft.suggestedTitle)
        _newTripStartDate = State(initialValue: draft.days.compactMap(\.date).min() ?? trip.startDate)
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
                if isCreatingTrip {
                    Section("创建旅程") {
                        TextField("旅程名称", text: $newTripTitle).clearableText($newTripTitle)
                        TextField("目的地（选填）", text: $newTripDestination).clearableText($newTripDestination)
                        TextField("车牌号（选填）", text: $newTripLicensePlate).clearableText($newTripLicensePlate)
                            .onChange(of: newTripLicensePlate) { _, value in
                                let formatted = value.formattedLicensePlate
                                if newTripLicensePlate != formatted { newTripLicensePlate = formatted }
                            }.textInputAutocapitalization(.characters).autocorrectionDisabled()
                        if days.allSatisfy({ $0.date == nil }) {
                            DatePicker("出发日期", selection: $newTripStartDate, displayedComponents: .date)
                            Text("没有具体日期的安排将从出发日开始按天生成。")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("按识别到的日期生成旅程；可在下方核对每日安排。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
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

                    Text(targetDay == nil ? "可录入多天、多个安排。" : "请上传一天的行程，支持多个安排。")
                        .font(.footnote.weight(.medium))
                    if targetDay != nil && draft.days.count > 1 {
                        Text("识别到多天内容，当前入口会将安排合并到所选一天。需要保留多天时，请返回整段旅程入口。")
                            .font(.caption).foregroundStyle(.orange)
                    }
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
            .navigationTitle(isCreatingTrip ? "智能创建旅程" : targetDay == nil ? "录入整段旅程" : "录入当天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(onBack == nil ? "取消" : "返回") {
                        if let onBack { onBack() } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreatingTrip ? "创建旅程" : "保存") { save() }
                        .disabled(includedItems.isEmpty || includedItems.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!$0.isTimePending && $0.startTime >= $0.endTime) } || (isCreatingTrip && newTripTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
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
                        TextField("例如：游览世纪公园", text: item.title).clearableText(item.title)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        editorFieldLabel("补充说明")
                        TextField("例如：先寄存行李", text: item.note, axis: .vertical).clearableText(item.note)
                            .lineLimit(2...5)
                    }
                    Picker("类型", selection: item.category) {
                        ForEach(PlaceCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.symbol).tag(category)
                        }
                    }
                    Toggle("时间待定", isOn: item.isTimePending)
                        .onChange(of: item.wrappedValue.isTimePending) { _, pending in
                            if pending { item.wrappedValue.isFixedTime = false }
                        }
                    if !item.wrappedValue.isTimePending {
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
                        Toggle("固定时间", isOn: item.isFixedTime)
                        Text("开启后，排序或拖拽时不会自动调整此安排的时间")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("地点类型", selection: item.locationMode) {
                        ForEach(ArrangementLocationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if item.wrappedValue.locationMode == .single {
                        VStack(alignment: .leading, spacing: 6) {
                            editorFieldLabel("地点名称")
                            TextField("例如：上海世纪公园", text: item.placeName).clearableText(item.placeName)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            editorFieldLabel("详细地址（选填）")
                            TextField("用于提高地图匹配准确度", text: item.placeAddress, axis: .vertical).clearableText(item.placeAddress)
                                .lineLimit(1...3)
                        }
                    } else {
                        locationFields(title: "出发地", name: item.originName, address: item.originAddress)
                        locationFields(title: "目的地", name: item.destinationName, address: item.destinationAddress)
                    }
                    HStack(spacing: 8) {
                        Text("¥").foregroundStyle(.secondary)
                        TripAmountInput(value: item.cost)
                            .keyboardType(.decimalPad)
                    }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
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
        let preview = JourneyImportApplyService.preview(editedDraft, for: planningTrip, replaceEmptySchedule: targetDay == nil)
        if isCreatingTrip {
            return "将创建旅程并生成 \(preview.totalDayCount) 天、\(includedItems.count) 个安排。"
        }
        if preview.reusedEmptyDayCount > 0 {
            return "将填入 \(preview.reusedEmptyDayCount) 个空白天，并新增 \(preview.newDayCount) 天；已有安排会保留。"
        }
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
        let edited = ItineraryJourneyDraft(days: days, rawText: draft.rawText, sourceAssetIdentifiers: [])
        guard let date = JourneyImportApplyService.plannedDate(for: day, in: edited, trip: planningTrip) else {
            return "第 \(dayIndex + 1) 天"
        }
        let calendar = Calendar.current
        let firstDate = JourneyImportApplyService.preview(edited, for: planningTrip, replaceEmptySchedule: targetDay == nil).dates.min() ?? planningTrip.startDate
        let resetsEmpty = targetDay == nil && planningTrip.days.allSatisfy { $0.items.isEmpty && $0.note.isEmpty } && days.contains { $0.date != nil }
        let first = resetsEmpty ? firstDate : min(calendar.startOfDay(for: planningTrip.startDate), firstDate)
        let number = (calendar.dateComponents([.day], from: first, to: date).day ?? dayIndex) + 1
        return "\(date.formatted(.dateTime.month().day().weekday())) · 第 \(number) 天"
    }

    private var planningTrip: Trip {
        guard isCreatingTrip else { return trip }
        return Trip(title: newTripTitle, destination: newTripDestination, startDate: newTripStartDate, endDate: newTripStartDate)
    }

    private func save() {
        if isCreatingTrip {
            trip.title = newTripTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            trip.destination = newTripDestination.trimmingCharacters(in: .whitespacesAndNewlines)
            trip.licensePlate = newTripLicensePlate.formattedLicensePlate
            trip.startDate = newTripStartDate
            trip.endDate = newTripStartDate
            modelContext.insert(trip)
        }
        let editedDraft = ItineraryJourneyDraft(
            days: days,
            rawText: draft.rawText,
            sourceAssetIdentifiers: draft.sourceAssetIdentifiers
        )
        let result = JourneyImportApplyService.append(
            editedDraft,
            to: trip,
            attachSourceImages: attachScreenshots,
            replaceEmptySchedule: targetDay == nil
        )
        for day in result.removedEmptyDays { modelContext.delete(day) }
        for day in result.createdDays { modelContext.insert(day) }
        for item in result.createdItems { modelContext.insert(item) }
        for media in result.createdMedia { modelContext.insert(media) }
        dismiss()
        onCreated?(trip)
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
            TextField("地点名称", text: name).clearableText(name)
            TextField("详细地址（选填）", text: address, axis: .vertical).clearableText(address)
                .lineLimit(1...3)
        }
    }
}
