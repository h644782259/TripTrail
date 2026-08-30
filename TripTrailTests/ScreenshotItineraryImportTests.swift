import XCTest
@testable import TripTrail

final class ScreenshotItineraryImportTests: XCTestCase {
    func testParsesHotelBookingScreenshotText() {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let draft = ScreenshotItineraryImportService.parseRecognizedLines(
            [
                "订单号 104648852627",
                "预订成功",
                "09月25日11:00后可办理入住",
                "在线付 ¥311",
                "取消规则 入住当日14:00前可免费取消",
                "滴水山房花园酒店（上海虹桥机场国家会展中心店）〉",
                "上海长宁区空港一路366号",
                "9月25日 周五 1晚 9月26日 周六",
                "11:00后入住 12:00前离店",
                "特惠舒适大床房（优眠床品）1间",
                "1张1.5米双人床 可住2人"
            ],
            referenceDate: reference
        )

        XCTAssertEqual(draft.category, .hotel)
        XCTAssertEqual(draft.title, "滴水山房花园酒店（上海虹桥机场国家会展中心店）")
        XCTAssertEqual(draft.address, "上海长宁区空港一路366号")
        XCTAssertEqual(draft.orderNumber, "104648852627")
        XCTAssertEqual(draft.cost, 311)
        XCTAssertTrue(draft.reservationInfo.contains("特惠舒适大床房"))
        XCTAssertTrue(draft.reservationInfo.contains("免费取消"))

        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.startTime)
        let end = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.endTime)
        XCTAssertEqual(start.year, 2026)
        XCTAssertEqual(start.month, 9)
        XCTAssertEqual(start.day, 25)
        XCTAssertEqual(start.hour, 11)
        XCTAssertEqual(start.minute, 0)
        XCTAssertEqual(end.year, 2026)
        XCTAssertEqual(end.month, 9)
        XCTAssertEqual(end.day, 26)
        XCTAssertEqual(end.hour, 12)
        XCTAssertEqual(end.minute, 0)
    }

    func testParsesNavigationScreenshotIntoExistingRouteField() {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: 9))!
        let draft = ScreenshotItineraryImportService.parseRecognizedLines(
            [
                "00:50",
                "我的位置",
                "深圳北站（西进站口）",
                "公共交通",
                "粤A**6",
                "打车",
                "深圳北站-西进站口 修改",
                "11分钟",
                "4.4公里",
                "夜间宽敞大路",
                "12分钟",
                "4.9公里",
                "18元起",
                "开始导航"
            ],
            referenceDate: reference
        )

        XCTAssertEqual(draft.category, .transport)
        XCTAssertEqual(draft.title, "深圳北站（西进站口）")
        XCTAssertEqual(draft.address, "深圳北站（西进站口）")
        XCTAssertEqual(draft.transport, .car)
        XCTAssertEqual(draft.distanceText, "4.4 公里 · 11 分钟")
        XCTAssertEqual(draft.travelDurationMinutes, 11)
        XCTAssertEqual(draft.note, "夜间宽敞大路")
        XCTAssertEqual(Int(draft.endTime.timeIntervalSince(draft.startTime) / 60), 11)
    }

    func testParsesUserEnteredHotelTextIntoEditableDraft() throws {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let draft = try ScreenshotItineraryImportService.parseInputText(
            """
            酒店：滴水山房花园酒店
            地址：上海长宁区空港一路366号
            入住：9月25日11:00
            离店：9月26日10:00
            订单号：104648852627
            花费：¥311
            """,
            referenceDate: reference
        )

        XCTAssertEqual(draft.category, .hotel)
        XCTAssertEqual(draft.title, "滴水山房花园酒店")
        XCTAssertEqual(draft.address, "上海长宁区空港一路366号")
        XCTAssertEqual(draft.orderNumber, "104648852627")
        XCTAssertEqual(draft.cost, 311)

        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.startTime)
        let end = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.endTime)
        XCTAssertEqual(start.day, 25)
        XCTAssertEqual(start.hour, 11)
        XCTAssertEqual(end.day, 26)
        XCTAssertEqual(end.hour, 10)
    }

    func testParsesUserEnteredNavigationTextWithoutWhitespaceBeforeDuration() throws {
        let reference = Date(timeIntervalSince1970: 1_788_048_000)
        let draft = try ScreenshotItineraryImportService.parseInputText(
            "目的地：深圳北站（西进站口），驾车11分钟，距离4.4公里",
            referenceDate: reference
        )

        XCTAssertEqual(draft.category, .transport)
        XCTAssertEqual(draft.title, "深圳北站（西进站口）")
        XCTAssertEqual(draft.address, "深圳北站（西进站口）")
        XCTAssertEqual(draft.distanceText, "4.4 公里 · 11 分钟")
    }

    func testParsesSingleArrangementFieldsForSmartPrefill() throws {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let draft = try ScreenshotItineraryImportService.parseInputText(
            """
            地点：四姑娘山双桥沟
            地址：四川省阿坝州小金县四姑娘山镇
            时间：9月25日 09:00-12:30
            门票：150元
            备注：全程可乘观光车
            """,
            referenceDate: reference
        )

        XCTAssertEqual(draft.title, "四姑娘山双桥沟")
        XCTAssertEqual(draft.address, "四川省阿坝州小金县四姑娘山镇")
        XCTAssertEqual(draft.cost, 150)
        XCTAssertEqual(draft.reservationInfo, "门票：150元")
        XCTAssertEqual(draft.note, "全程可乘观光车")

        let start = calendar.dateComponents([.month, .day, .hour, .minute], from: draft.startTime)
        let end = calendar.dateComponents([.month, .day, .hour, .minute], from: draft.endTime)
        XCTAssertEqual(start.month, 9)
        XCTAssertEqual(start.day, 25)
        XCTAssertEqual(start.hour, 9)
        XCTAssertEqual(start.minute, 0)
        XCTAssertEqual(end.month, 9)
        XCTAssertEqual(end.day, 25)
        XCTAssertEqual(end.hour, 12)
        XCTAssertEqual(end.minute, 30)
    }

    func testParsesFiveDayJourneyAndSkipsSupplementaryGuideSections() throws {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let draft = try ScreenshotItineraryImportService.parseJourneyInputText(
            """
            川西小环线5天4晚
            - Day 1: 成都 → 四姑娘山（住四姑娘山镇）
            全程约200公里，耗时约4.5-5小时。沿熊猫大道经映秀，翻越巴朗山。
            - Day 2: 四姑娘山 → 丹巴（住丹巴县）
            上午深度游玩四姑娘山双桥沟，下午驱车前往丹巴。
            - Day 3: 丹巴 → 新都桥（住新都桥镇）
            依次打卡墨石公园的异域地貌、塔公草原的雪山远景。
            - Day 4: 新都桥 → 康定（住康定市）
            可以去鱼子西或格底拉姆看日落，之后经红海子抵达康定。
            - Day 5: 康定 → 成都
            顺路打卡泸定桥，然后返回成都。
            ✨ 必打卡精华景点
            四姑娘山双桥沟、墨石公园、塔公草原。
            🚗 自驾路况与车辆
            全程路况良好。
            """,
            referenceDate: reference
        )

        XCTAssertEqual(draft.days.count, 5)
        XCTAssertEqual(draft.days[0].routeTitle, "成都 → 四姑娘山")
        XCTAssertTrue(draft.days[0].items.contains { $0.title == "成都 → 四姑娘山" })
        XCTAssertTrue(draft.days[0].items.contains { $0.title == "入住四姑娘山镇" })
        XCTAssertTrue(draft.days[2].items.contains { $0.title == "墨石公园" })
        XCTAssertTrue(draft.days[2].items.contains { $0.title == "塔公草原" })
        XCTAssertTrue(draft.days[3].items.contains { $0.title == "鱼子西" })
        XCTAssertTrue(draft.days[3].items.contains { $0.title == "格底拉姆" })
        XCTAssertTrue(draft.days[3].items.contains { $0.title == "红海子" })
        XCTAssertTrue(draft.days[4].items.contains { $0.title == "泸定桥" })
        XCTAssertFalse(draft.days[4].note.contains("自驾路况"))
        XCTAssertEqual(draft.days[0].items.first?.distanceText, "200 公里 · 4.5–5 小时")
    }

    func testJourneyImportCreatesAllDaysForEmptyTripAndAppendsAfterExistingDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let draft = try ScreenshotItineraryImportService.parseJourneyInputText(
            """
            Day 1: 成都 → 四姑娘山
            Day 2: 四姑娘山 → 丹巴
            Day 3: 丹巴 → 新都桥
            Day 4: 新都桥 → 康定
            Day 5: 康定 → 成都
            """,
            referenceDate: start
        )

        let emptyTrip = Trip(title: "川西", destination: "川西", startDate: start, endDate: start)
        let created = JourneyImportApplyService.append(
            draft,
            to: emptyTrip,
            attachSourceImages: false,
            calendar: calendar
        )
        XCTAssertEqual(created.count, 5)
        XCTAssertEqual(emptyTrip.sortedDays.count, 5)
        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: emptyTrip.endDate).day, 4)

        let existingTrip = Trip(title: "川西", destination: "川西", startDate: start, endDate: start)
        for offset in 0..<3 {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            existingTrip.days.append(TripDay(date: date, title: "", sortOrder: offset, trip: existingTrip))
        }
        let appended = JourneyImportApplyService.append(
            draft,
            to: existingTrip,
            attachSourceImages: false,
            calendar: calendar
        )
        XCTAssertEqual(appended.count, 5)
        XCTAssertEqual(existingTrip.sortedDays.count, 8)
        XCTAssertEqual(appended.first?.sortOrder, 3)
        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: appended.first!.date).day, 3)
        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: appended.last!.date).day, 7)
    }
}
