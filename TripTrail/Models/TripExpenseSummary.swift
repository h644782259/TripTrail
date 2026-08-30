import Foundation

struct DailyTripExpense: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let amount: Double
}

struct TripExpenseSummary: Equatable {
    let dailyExpenses: [DailyTripExpense]
    let totalAmount: Double

    static func make(
        for trip: Trip,
        calendar: Calendar = .current
    ) -> TripExpenseSummary {
        var amountByDate: [Date: Double] = [:]

        for day in trip.sortedDays {
            let date = calendar.startOfDay(for: day.date)
            amountByDate[date, default: 0] += day.items.reduce(0) { partialResult, item in
                partialResult + item.cost
            }
        }

        let dailyExpenses = amountByDate
            .map { DailyTripExpense(date: $0.key, amount: $0.value) }
            .sorted { $0.date < $1.date }

        return TripExpenseSummary(
            dailyExpenses: dailyExpenses,
            totalAmount: dailyExpenses.reduce(0) { $0 + $1.amount }
        )
    }
}
