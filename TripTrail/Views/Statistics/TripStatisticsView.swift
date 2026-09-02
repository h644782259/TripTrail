import Charts
import SwiftData
import SwiftUI

struct TripStatisticsView: View {
    @Query private var trips: [Trip]
    @State private var selectedTripID: UUID?
    @State private var showsTripPicker = false

    private var orderedTrips: [Trip] {
        TripTimelineOrdering.sorted(trips)
    }

    private var selectedTrip: Trip? {
        orderedTrips.first { $0.id == selectedTripID } ?? orderedTrips.first
    }

    var body: some View {
        Group {
            if let selectedTrip {
                statisticsContent(for: selectedTrip)
            } else {
                ContentUnavailableView(
                    "还没有可统计的旅程",
                    systemImage: "chart.bar.xaxis",
                    description: Text("创建旅程并记录花费后，这里会按天展示。")
                )
            }
        }
        .background(Color.tripCanvas.ignoresSafeArea())
        .navigationTitle("统计")
        .sheet(isPresented: $showsTripPicker) {
            StatisticsTripPicker(
                trips: orderedTrips,
                selectedTripID: selectedTripID
            ) { trip in
                selectedTripID = trip.id
                showsTripPicker = false
            }
        }
        .onAppear(perform: selectDefaultTripIfNeeded)
        .onChange(of: orderedTrips.map(\.id)) { _, _ in
            selectDefaultTripIfNeeded()
        }
    }

    private func statisticsContent(for trip: Trip) -> some View {
        let summary = TripExpenseSummary.make(for: trip)

        return ScrollView {
            VStack(spacing: 16) {
                tripSelector(currentTrip: trip)
                totalCard(trip: trip, summary: summary)
                dailyChartCard(summary: summary)
            }
            .padding()
            .padding(.bottom, 24)
        }
    }

    private func tripSelector(currentTrip: Trip) -> some View {
        Button {
            showsTripPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .foregroundStyle(Color.tripLake)
                    .frame(width: 34, height: 34)
                    .background(Color.tripLake.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                Text(currentTrip.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.tripSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.tripMist.opacity(0.4), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择旅程，当前为\(currentTrip.title)")
    }

    private func totalCard(trip: Trip, summary: TripExpenseSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("旅程总花费", systemImage: "yensign.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text("\(summary.dailyExpenses.count) 天")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.14), in: Capsule())
            }

            Text(summary.totalAmount, format: .currency(code: "CNY"))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.72)
                .lineLimit(1)

            Text(trip.startDate.formatted(.dateTime.year().month().day()) + " – " + trip.endDate.formatted(.dateTime.month().day()))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.tripInk, Color.tripLake],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: Color.tripInk.opacity(0.12), radius: 16, y: 8)
    }

    private func dailyChartCard(summary: TripExpenseSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("每日花费")
                .font(.headline)

            if summary.dailyExpenses.isEmpty {
                ContentUnavailableView("还没有旅程日期", systemImage: "calendar.badge.exclamationmark")
                    .frame(height: 220)
            } else {
                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        expenseChart(summary.dailyExpenses)
                            .frame(
                                width: max(proxy.size.width, CGFloat(summary.dailyExpenses.count) * 64),
                                height: 230
                            )
                    }
                }
                .frame(height: 230)
            }
        }
        .padding(18)
        .background(Color.tripSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.tripMist.opacity(0.38), lineWidth: 0.8)
        }
        .shadow(color: Color.tripInk.opacity(0.055), radius: 14, y: 6)
    }

    private func expenseChart(_ expenses: [DailyTripExpense]) -> some View {
        let maximumAmount = expenses.map(\.amount).max() ?? 0
        let upperBound = max(maximumAmount * 1.22, 100)

        return Chart(expenses) { expense in
            BarMark(
                x: .value("日期", expense.date, unit: .day),
                y: .value("金额", expense.amount)
            )
            .foregroundStyle(Color.tripLake.gradient)
            .cornerRadius(7)
            .annotation(position: .top, spacing: 5) {
                if expense.amount > 0 {
                    Text(expense.amount, format: .number.precision(.fractionLength(0...1)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartYScale(domain: 0...upperBound)
        .chartXAxis {
            AxisMarks(values: expenses.map(\.date)) { _ in
                AxisValueLabel(format: .dateTime.month().day())
                AxisTick()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.22))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text("¥\(amount, format: .number.precision(.fractionLength(0)))")
                    }
                }
            }
        }
    }

    private func selectDefaultTripIfNeeded() {
        guard !orderedTrips.isEmpty else {
            selectedTripID = nil
            return
        }
        if !orderedTrips.contains(where: { $0.id == selectedTripID }) {
            selectedTripID = orderedTrips.first?.id
        }
    }
}

private struct StatisticsTripPicker: View {
    @Environment(\.dismiss) private var dismiss
    let trips: [Trip]
    let selectedTripID: UUID?
    let onSelect: (Trip) -> Void
    @State private var searchText = ""

    private var filteredTrips: [Trip] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return trips }
        return trips.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.destination.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        TripNavigationStack {
            Group {
                if filteredTrips.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        tripSection(title: "进行中", phase: .current)
                        tripSection(title: "即将出发", phase: .upcoming)
                        tripSection(title: "已结束", phase: .history)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("选择旅程")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索旅程名称或目的地")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func tripSection(title: String, phase: TripTimelinePhase) -> some View {
        let matchingTrips = filteredTrips.filter { TripTimelineOrdering.phase(for: $0) == phase }
        if !matchingTrips.isEmpty {
            Section(title) {
                ForEach(matchingTrips) { trip in
                    Button {
                        onSelect(trip)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: phaseSymbol(phase))
                                .foregroundStyle(phaseColor(phase))
                                .frame(width: 32, height: 32)
                                .background(phaseColor(phase).opacity(0.11), in: RoundedRectangle(cornerRadius: 9))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(trip.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    if !trip.destination.isEmpty {
                                        Text(trip.destination).lineLimit(1)
                                        Text("·")
                                    }
                                    Text(trip.startDate.compactDayText + " — " + trip.endDate.compactDayText)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)
                            if trip.id == selectedTripID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.tripLake)
                                    .accessibilityLabel("当前选择")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择\(trip.title)")
                }
            }
        }
    }

    private func phaseSymbol(_ phase: TripTimelinePhase) -> String {
        switch phase {
        case .current: "figure.walk.motion"
        case .upcoming: "calendar"
        case .history: "checkmark"
        }
    }

    private func phaseColor(_ phase: TripTimelinePhase) -> Color {
        switch phase {
        case .current: .tripSage
        case .upcoming: .tripLake
        case .history: .secondary
        }
    }
}
