import SwiftUI

enum TimeRangePickerDisplayStyle {
    case form
    case capsule
}

struct UnifiedTimeRangePicker: View {
    let title: String
    let startTitle: String
    let endTitle: String
    @Binding var startTime: Date
    @Binding var endTime: Date
    let displayStyle: TimeRangePickerDisplayStyle
    let separator: String

    @State private var isPresented = false
    @State private var draftStartTime: Date
    @State private var draftEndTime: Date

    init(
        title: String = "调整时间",
        startTitle: String = "开始",
        endTitle: String = "结束",
        startTime: Binding<Date>,
        endTime: Binding<Date>,
        displayStyle: TimeRangePickerDisplayStyle = .form,
        separator: String = "–"
    ) {
        self.title = title
        self.startTitle = startTitle
        self.endTitle = endTitle
        _startTime = startTime
        _endTime = endTime
        self.displayStyle = displayStyle
        self.separator = separator
        _draftStartTime = State(initialValue: startTime.wrappedValue)
        _draftEndTime = State(initialValue: endTime.wrappedValue)
    }

    var body: some View {
        Button(action: openPicker) {
            switch displayStyle {
            case .form:
                HStack(spacing: 10) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(rangeText(startTime: startTime, endTime: endTime))
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .foregroundStyle(Color.tripInk)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            case .capsule:
                Text(rangeText(startTime: startTime, endTime: endTime))
                    .font(.caption.bold())
                    .monospacedDigit()
                    .padding(.horizontal, 11)
                    .frame(minHeight: 34)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(startTitle) \(startTime.timeText)，\(endTitle) \(endTime.timeText)")
        .accessibilityHint("打开时间选择器")
        .sheet(isPresented: $isPresented) {
            editor
                .presentationDetents([.height(370)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.tripCanvas)
        }
    }

    private var editor: some View {
        VStack(spacing: 14) {
            HStack {
                Text(title)
                    .font(.title3.bold())
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.bold())
                        .frame(width: 36, height: 36)
                        .background(Color.secondary.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消")
            }

            TimeRangeWheelSelector(
                startTitle: startTitle,
                endTitle: endTitle,
                startTime: $draftStartTime,
                endTime: $draftEndTime,
                separator: separator
            )
            .padding(.horizontal, 4)

            if !isValid {
                Label("结束时间不能早于开始时间", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button {
                    isPresented = false
                } label: {
                    Text("取消").frame(maxWidth: .infinity)
                }
                    .buttonStyle(.bordered)
                Button {
                    commit()
                } label: {
                    Text("确定").frame(maxWidth: .infinity)
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var isValid: Bool {
        draftEndTime >= draftStartTime
    }

    private func openPicker() {
        draftStartTime = startTime
        draftEndTime = endTime
        isPresented = true
    }

    private func commit() {
        guard isValid else { return }
        startTime = draftStartTime
        endTime = draftEndTime
        isPresented = false
    }

    private func rangeText(startTime: Date, endTime: Date) -> String {
        "\(startTime.timeText)\(separator)\(endTime.timeText)"
    }
}

struct TimeRangeWheelSelector: View {
    let startTitle: String
    let endTitle: String
    @Binding var startTime: Date
    @Binding var endTime: Date
    var separator: String? = nil

    private var calendar: Calendar { .current }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            endpoint(title: startTitle, selection: $startTime)
            if let separator {
                Text(separator)
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else {
                Divider()
                    .frame(height: 168)
                    .padding(.horizontal, 2)
            }
            endpoint(title: endTitle, selection: $endTime)
        }
        .frame(maxWidth: .infinity)
    }

    private func endpoint(title: String, selection: Binding<Date>) -> some View {
        VStack(spacing: 4) {
            Text("\(title)时间")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.tripInk)

            HStack(spacing: 0) {
                componentPicker(
                    title: "\(title)小时",
                    values: Array(0..<24),
                    selection: componentBinding(.hour, date: selection)
                )
                Text(":")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                componentPicker(
                    title: "\(title)分钟",
                    values: Array(0..<60),
                    selection: componentBinding(.minute, date: selection)
                )
            }
            .frame(height: 150)
            .clipped()
            .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private func componentPicker(
        title: String,
        values: [Int],
        selection: Binding<Int>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { value in
                Text(String(format: "%02d", value))
                    .monospacedDigit()
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(width: 58, height: 150)
        .clipped()
    }

    private func componentBinding(_ component: Calendar.Component, date: Binding<Date>) -> Binding<Int> {
        Binding(
            get: { calendar.component(component, from: date.wrappedValue) },
            set: { newValue in
                let current = date.wrappedValue
                var components = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: current
                )
                switch component {
                case .hour:
                    components.hour = newValue
                case .minute:
                    components.minute = newValue
                default:
                    return
                }
                components.second = 0
                date.wrappedValue = calendar.date(from: components) ?? current
            }
        )
    }
}
