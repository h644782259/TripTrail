import Charts
import SwiftData
import SwiftUI

struct TripStatisticsView: View {
    @Query private var trips: [Trip]
    @State private var selectedTripID: UUID?

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
        Menu {
            ForEach(orderedTrips) { trip in
                Button {
                    selectedTripID = trip.id
                } label: {
                    if trip.id == currentTrip.id {
                        Label(trip.title, systemImage: "checkmark")
                    } else {
                        Text(trip.title)
                    }
                }
            }
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
                Image(systemName: "chevron.up.chevron.down")
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
