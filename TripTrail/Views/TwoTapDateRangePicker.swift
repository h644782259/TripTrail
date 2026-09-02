import SwiftUI

enum DateRangePickerDisplayStyle {
    case form
    case compactOnColor
}

enum DateRangeSelectionPhase {
    case start
    case end
    case complete
}

struct DateRangeDraft {
    var startDate: Date?
    var endDate: Date?
    var phase: DateRangeSelectionPhase = .start

    mutating func select(_ date: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        switch phase {
        case .start, .complete:
            startDate = day
            endDate = nil
            phase = .end
        case .end:
            guard let startDate, day >= startDate else { return }
            endDate = day
            phase = .complete
        }
    }

    mutating func reset() {
        startDate = nil
        endDate = nil
        phase = .start
    }
}

enum DateRangeDateService {
    static func applyingDay(
        _ day: Date,
        to originalDate: Date,
        preservingTime: Bool,
        calendar: Calendar = .current
    ) -> Date {
        let normalizedDay = calendar.startOfDay(for: day)
        guard preservingTime else { return normalizedDay }
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: originalDate)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: normalizedDay
        ) ?? normalizedDay
    }
}

struct TwoTapDateRangePicker: View {
    let title: String
    let startTitle: String
    let endTitle: String
    @Binding var startDate: Date
    @Binding var endDate: Date
    let preservesTimeComponents: Bool
    let showsTimeSelection: Bool
    let displayStyle: DateRangePickerDisplayStyle
    let showsEndpointTitles: Bool

    @State private var isPresented = false
    @State private var visibleMonth = Date()
    @State private var draft = DateRangeDraft()
    @State private var draftStartTime = Date()
    @State private var draftEndTime = Date()

    private var calendar: Calendar { .current }

    init(
        title: String,
        startTitle: String,
        endTitle: String,
        startDate: Binding<Date>,
        endDate: Binding<Date>,
        preservesTimeComponents: Bool = false,
        showsTimeSelection: Bool = false,
        displayStyle: DateRangePickerDisplayStyle = .form,
        showsEndpointTitles: Bool = true
    ) {
        self.title = title
        self.startTitle = startTitle
        self.endTitle = endTitle
        _startDate = startDate
        _endDate = endDate
        self.preservesTimeComponents = preservesTimeComponents
        self.showsTimeSelection = showsTimeSelection
        self.displayStyle = displayStyle
        self.showsEndpointTitles = showsEndpointTitles
        _draftStartTime = State(initialValue: startDate.wrappedValue)
        _draftEndTime = State(initialValue: endDate.wrappedValue)
    }

    var body: some View {
        Button(action: openPicker) {
            switch displayStyle {
            case .form:
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(title)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 10) {
                        endpoint(title: startTitle, date: startDate)
                        Divider().frame(height: 34)
                        endpoint(title: endTitle, date: endDate)
                    }
                }
                .contentShape(Rectangle())
            case .compactOnColor:
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                    Text("\(dateText(startDate)) — \(dateText(endDate))")
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(startTitle) \(valueText(startDate))，\(endTitle) \(valueText(endDate))")
        .accessibilityHint("打开同一个日历，第一次选择开始日期，第二次选择结束日期")
        .sheet(isPresented: $isPresented) {
            pickerSheet
                .presentationDetents(showsTimeSelection ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func endpoint(title: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsEndpointTitles {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(valueText(date))
                .font(.subheadline.bold())
                .foregroundStyle(Color.tripInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pickerSheet: some View {
        TripNavigationStack {
            VStack(spacing: 14) {
                monthHeader
                weekdayHeader
                calendarGrid
                if showsTimeSelection {
                    timeRangeEditor
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .background(Color.tripCanvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { commitDraft() }
                        .disabled(draft.phase != .complete || !isDraftDateTimeRangeValid)
                }
            }
        }
    }

    private var timeRangeEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if !isDraftDateTimeRangeValid, draft.phase == .complete {
                Text("结束不能早于开始")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TimeRangeWheelSelector(
                startTitle: startTitle,
                endTitle: endTitle,
                startTime: $draftStartTime,
                endTime: $draftEndTime
            )
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private var monthHeader: some View {
        HStack {
            Button {
                moveVisibleMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 40, height: 34)
            }
            .accessibilityLabel("上个月")

            Spacer()
            Text(visibleMonth.formatted(.dateTime.year().month(.wide)))
                .font(.headline)
            Spacer()

            Button {
                moveVisibleMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 40, height: 34)
            }
            .accessibilityLabel("下个月")
        }
        .foregroundStyle(Color.tripInk)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: calendarColumns, spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: calendarColumns, spacing: 5) {
            ForEach(0..<calendarCellCount, id: \.self) { index in
                if let date = dateForCell(index) {
                    dayButton(date)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private func dayButton(_ date: Date) -> some View {
        let day = calendar.startOfDay(for: date)
        let isStart = draft.startDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isEnd = draft.endDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isInRange = draft.startDate.map { start in
            guard let end = draft.endDate else { return false }
            return day >= start && day <= end
        } ?? false
        let isDisabled = draft.phase == .end && draft.startDate.map { day < $0 } == true

        return Button {
            draft.select(day, calendar: calendar)
        } label: {
            Text(String(calendar.component(.day, from: day)))
                .font(.subheadline.weight(isStart || isEnd ? .bold : .regular))
                .foregroundStyle(isStart || isEnd ? .white : (isDisabled ? Color.secondary.opacity(0.35) : Color.primary))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background {
                    if isStart || isEnd {
                        Circle().fill(Color.tripLake)
                    } else if isInRange {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.tripLake.opacity(0.14))
                    }
                }
                .overlay {
                    if calendar.isDateInToday(day), !isStart, !isEnd {
                        Circle().stroke(Color.tripLake.opacity(0.7), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(day.formatted(.dateTime.year().month().day().weekday(.wide)))
        .accessibilityValue(isStart ? "开始日期" : (isEnd ? "结束日期" : (isInRange ? "范围内" : "")))
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstIndex = max(0, calendar.firstWeekday - 1)
        return (0..<7).map { symbols[(firstIndex + $0) % symbols.count] }
    }

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: visibleMonth)?.start
            ?? calendar.startOfDay(for: visibleMonth)
    }

    private var leadingBlankCount: Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
    }

    private var calendarCellCount: Int {
        let used = leadingBlankCount + daysInMonth
        return ((used + 6) / 7) * 7
    }

    private func dateForCell(_ index: Int) -> Date? {
        let dayIndex = index - leadingBlankCount
        guard dayIndex >= 0, dayIndex < daysInMonth else { return nil }
        return calendar.date(byAdding: .day, value: dayIndex, to: monthStart)
    }

    private func openPicker() {
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = max(normalizedStart, calendar.startOfDay(for: endDate))
        draft = DateRangeDraft(startDate: normalizedStart, endDate: normalizedEnd, phase: .complete)
        draftStartTime = startDate
        draftEndTime = endDate
        visibleMonth = calendar.dateInterval(of: .month, for: normalizedStart)?.start ?? normalizedStart
        isPresented = true
    }

    private func moveVisibleMonth(by value: Int) {
        visibleMonth = calendar.date(byAdding: .month, value: value, to: monthStart) ?? visibleMonth
    }

    private func commitDraft() {
        guard let selectedStart = draft.startDate, let selectedEnd = draft.endDate else { return }
        let startTimeSource = showsTimeSelection ? draftStartTime : startDate
        let endTimeSource = showsTimeSelection ? draftEndTime : endDate
        startDate = DateRangeDateService.applyingDay(
            selectedStart,
            to: startTimeSource,
            preservingTime: preservesTimeComponents || showsTimeSelection,
            calendar: calendar
        )
        endDate = DateRangeDateService.applyingDay(
            selectedEnd,
            to: endTimeSource,
            preservingTime: preservesTimeComponents || showsTimeSelection,
            calendar: calendar
        )
        isPresented = false
    }

    private var isDraftDateTimeRangeValid: Bool {
        guard showsTimeSelection else { return true }
        guard let selectedStart = draft.startDate, let selectedEnd = draft.endDate else { return false }
        let start = DateRangeDateService.applyingDay(
            selectedStart,
            to: draftStartTime,
            preservingTime: true,
            calendar: calendar
        )
        let end = DateRangeDateService.applyingDay(
            selectedEnd,
            to: draftEndTime,
            preservingTime: true,
            calendar: calendar
        )
        return end >= start
    }

    private func valueText(_ date: Date) -> String {
        if showsTimeSelection {
            return date.formatted(.dateTime.month().day().hour().minute())
        }
        return dateText(date)
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.month().day())
    }
}
