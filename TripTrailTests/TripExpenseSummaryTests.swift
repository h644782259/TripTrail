import XCTest
@testable import TripTrail

@MainActor
final class TripExpenseSummaryTests: XCTestCase {
    func testSummaryAggregatesEveryItemByTripDayAndKeepsZeroCostDays() {
        let calendar = Calendar(identifier: .gregorian)
        let firstDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6))!
        let secondDate = calendar.date(byAdding: .day, value: 1, to: firstDate)!
        let trip = Trip(title: "上海", destination: "上海", startDate: firstDate, endDate: secondDate)
        let firstDay = TripDay(date: firstDate, title: "第 1 天", sortOrder: 0, trip: trip)
        let secondDay = TripDay(date: secondDate, title: "第 2 天", sortOrder: 1, trip: trip)
        let firstItem = ItineraryItem(title: "机场", category: .transport, startTime: firstDate, endTime: firstDate, sortOrder: 0)
        let secondItem = ItineraryItem(title: "酒店", category: .hotel, startTime: firstDate, endTime: firstDate, sortOrder: 1)
        firstItem.cost = 86.5
        secondItem.cost = 688
        firstDay.items = [firstItem, secondItem]
        trip.days = [secondDay, firstDay]

        let summary = TripExpenseSummary.make(for: trip, calendar: calendar)

        XCTAssertEqual(summary.dailyExpenses.map(\.date), [firstDate, secondDate])
        XCTAssertEqual(summary.dailyExpenses.map(\.amount), [774.5, 0])
        XCTAssertEqual(summary.totalAmount, 774.5)
    }

    func testSummaryCombinesDuplicateCalendarDates() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6))!
        let trip = Trip(title: "周末", destination: "杭州", startDate: date, endDate: date)
        let morning = TripDay(date: date, title: "上午", sortOrder: 0, trip: trip)
        let evening = TripDay(date: date.addingTimeInterval(18 * 3_600), title: "晚上", sortOrder: 1, trip: trip)
        let breakfast = ItineraryItem(title: "早餐", category: .restaurant, startTime: date, endTime: date, sortOrder: 0)
        let dinner = ItineraryItem(title: "晚餐", category: .restaurant, startTime: date, endTime: date, sortOrder: 0)
        breakfast.cost = 35
        dinner.cost = 120
        morning.items = [breakfast]
        evening.items = [dinner]
        trip.days = [morning, evening]

        let summary = TripExpenseSummary.make(for: trip, calendar: calendar)

        XCTAssertEqual(summary.dailyExpenses.count, 1)
        XCTAssertEqual(summary.dailyExpenses.first?.amount, 155)
        XCTAssertEqual(summary.totalAmount, 155)
    }
}
