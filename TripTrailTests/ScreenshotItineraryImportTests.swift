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
        XCTAssertEqual(draft.title, "入住滴水山房花园酒店（上海虹桥机场国家会展中心店）")
        XCTAssertEqual(draft.locationMode, .single)
        XCTAssertEqual(draft.placeName, "滴水山房花园酒店（上海虹桥机场国家会展中心店）")
        XCTAssertEqual(draft.placeAddress, "上海长宁区空港一路366号")
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
        XCTAssertEqual(draft.title, "前往深圳北站（西进站口）")
        XCTAssertEqual(draft.locationMode, .single)
        XCTAssertEqual(draft.placeName, "深圳北站（西进站口）")
        XCTAssertEqual(draft.address, "")
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
        XCTAssertEqual(draft.title, "入住滴水山房花园酒店")
        XCTAssertEqual(draft.placeName, "滴水山房花园酒店")
        XCTAssertEqual(draft.placeAddress, "上海长宁区空港一路366号")
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
        XCTAssertEqual(draft.title, "前往深圳北站（西进站口）")
        XCTAssertEqual(draft.placeName, "深圳北站（西进站口）")
        XCTAssertEqual(draft.address, "")
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

        XCTAssertEqual(draft.title, "游览四姑娘山双桥沟")
        XCTAssertEqual(draft.placeName, "四姑娘山双桥沟")
        XCTAssertEqual(draft.placeAddress, "四川省阿坝州小金县四姑娘山镇")
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
        XCTAssertTrue(draft.days[2].items.contains { $0.placeName == "墨石公园" })
        XCTAssertTrue(draft.days[2].items.contains { $0.placeName == "塔公草原" })
        XCTAssertTrue(draft.days[3].items.contains { $0.placeName == "鱼子西" })
        XCTAssertTrue(draft.days[3].items.contains { $0.placeName == "格底拉姆" })
        XCTAssertTrue(draft.days[3].items.contains { $0.placeName == "红海子" })
        XCTAssertTrue(draft.days[4].items.contains { $0.placeName == "泸定桥" })
        XCTAssertFalse(draft.days[4].note.contains("自驾路况"))
        XCTAssertEqual(draft.days[0].items.first?.distanceText, "200 公里 · 4.5–5 小时")
    }

    func testParsesChineseNumberedAndCompactDayHeadings() throws {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let draft = try ScreenshotItineraryImportService.parseJourneyInputText(
            """
            第一天｜杭州西湖
            09:00 游玩西湖景区
            D2 西溪湿地
            10:00 游玩西溪湿地公园
            D A Y 3：良渚古城
            09:30 游玩良渚古城遗址公园
            """,
            referenceDate: reference
        )

        XCTAssertEqual(draft.days.count, 3)
        XCTAssertEqual(draft.days.map(\.sourceDayNumber), [1, 2, 3])
        XCTAssertEqual(draft.days.map(\.routeTitle), ["杭州西湖", "西溪湿地", "良渚古城"])
    }

    func testParsesStandaloneDatesAsMultipleJourneyDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let draft = try ScreenshotItineraryImportService.parseJourneyInputText(
            """
            9月1日 周二｜杭州西湖
            09:00 游玩西湖景区
            9月2日 周三｜西溪湿地
            10:00 游玩西溪湿地公园
            9月3日 周四｜良渚古城
            09:30 游玩良渚古城遗址公园
            """,
            referenceDate: reference
        )

        XCTAssertEqual(draft.days.count, 3)
        XCTAssertEqual(draft.days.map(\.routeTitle), ["杭州西湖", "西溪湿地", "良渚古城"])
    }

    func testMultiImageOCRKeepsSeparateDaysWhenOneDayHeadingIsPartiallyLost() throws {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let draft = try ScreenshotItineraryImportService.parseJourneyRecognizedLineGroups(
            [
                ["DAY 1 杭州西湖", "09:00 游玩西湖景区"],
                ["9月2日 周三 西溪湿地", "10:00 游玩西溪湿地公园"]
            ],
            referenceDate: reference
        )

        XCTAssertEqual(draft.days.count, 2)
        XCTAssertEqual(draft.days.map(\.sourceDayNumber), [1, 2])
    }

    func testStatusBarClockIsIgnoredOnlyAtTopLeft() {
        XCTAssertTrue(
            ScreenshotItineraryImportService.shouldIgnoreScreenStatusBarText(
                "11:18",
                boundingBox: CGRect(x: 0.05, y: 0.92, width: 0.12, height: 0.05)
            )
        )
        XCTAssertFalse(
            ScreenshotItineraryImportService.shouldIgnoreScreenStatusBarText(
                "11:18",
                boundingBox: CGRect(x: 0.40, y: 0.50, width: 0.12, height: 0.05)
            )
        )
        XCTAssertFalse(
            ScreenshotItineraryImportService.shouldIgnoreScreenStatusBarText(
                "09:00 出发",
                boundingBox: CGRect(x: 0.05, y: 0.92, width: 0.20, height: 0.05)
            )
        )
    }

    func testJourneyArrangementRecognizesBothStartAndEndTimes() throws {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let draft = try ScreenshotItineraryImportService.parseJourneyInputText(
            """
            第一天｜杭州西湖
            09:00-12:30 游玩西湖景区
            14:00 至 16:15 打卡中国茶叶博物馆
            """,
            referenceDate: reference
        )

        XCTAssertEqual(draft.days.count, 1)
        XCTAssertEqual(draft.days[0].items.count, 2)

        let firstStart = calendar.dateComponents([.hour, .minute], from: draft.days[0].items[0].startTime)
        let firstEnd = calendar.dateComponents([.hour, .minute], from: draft.days[0].items[0].endTime)
        XCTAssertEqual(firstStart.hour, 9)
        XCTAssertEqual(firstStart.minute, 0)
        XCTAssertEqual(firstEnd.hour, 12)
        XCTAssertEqual(firstEnd.minute, 30)

        let secondStart = calendar.dateComponents([.hour, .minute], from: draft.days[0].items[1].startTime)
        let secondEnd = calendar.dateComponents([.hour, .minute], from: draft.days[0].items[1].endTime)
        XCTAssertEqual(secondStart.hour, 14)
        XCTAssertEqual(secondStart.minute, 0)
        XCTAssertEqual(secondEnd.hour, 16)
        XCTAssertEqual(secondEnd.minute, 15)
    }

    func testUsesFirstAndSecondDateTimeOccurrencesAsFallbackRange() throws {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let draft = try ScreenshotItineraryImportService.parseInputText(
            """
            地点：西湖景区
            2026年9月25日
            09:10
            2026年9月26日
            12:40
            """,
            referenceDate: reference
        )

        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.startTime)
        let end = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.endTime)
        XCTAssertEqual(start.year, 2026)
        XCTAssertEqual(start.month, 9)
        XCTAssertEqual(start.day, 25)
        XCTAssertEqual(start.hour, 9)
        XCTAssertEqual(start.minute, 10)
        XCTAssertEqual(end.year, 2026)
        XCTAssertEqual(end.month, 9)
        XCTAssertEqual(end.day, 26)
        XCTAssertEqual(end.hour, 12)
        XCTAssertEqual(end.minute, 40)
    }

    func testFlightPlanDeduplicatesRepeatedExpectedDateTimes() throws {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let draft = try ScreenshotItineraryImportService.parseInputText(
            """
            月25日飞往上海
            春秋航空9C8932
            广州 白云T3
            计划
            21:15
            预计 09/25 21:15
            上海 虹桥T1
            计划
            23:40
            预计 09/25 23:40
            """,
            referenceDate: reference
        )

        let start = calendar.dateComponents([.month, .day, .hour, .minute], from: draft.startTime)
        let end = calendar.dateComponents([.month, .day, .hour, .minute], from: draft.endTime)
        XCTAssertEqual(start.month, 9)
        XCTAssertEqual(start.day, 25)
        XCTAssertEqual(start.hour, 21)
        XCTAssertEqual(start.minute, 15)
        XCTAssertEqual(end.month, 9)
        XCTAssertEqual(end.day, 25)
        XCTAssertEqual(end.hour, 23)
        XCTAssertEqual(end.minute, 40)
        XCTAssertEqual(draft.title, "广州 白云T3 → 上海 虹桥T1")
        XCTAssertEqual(draft.locationMode, .route)
        XCTAssertEqual(draft.originName, "广州 白云T3")
        XCTAssertEqual(draft.destinationName, "上海 虹桥T1")
        XCTAssertEqual(draft.address, "")
    }

    func testParsesActualOCRLinesFromBothFlightScreenshots() {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let cases: [(lines: [String], origin: String, destination: String, day: Int, start: (Int, Int), end: (Int, Int))] = [
            (
                [
                    "已送达", "9月28日飞往深圳", "查看订单〉",
                    "行前多一点准备，让旅途更轻松~", "计划", "S春秋航空9C8917",
                    "准点率：97%，请提前2个小时到", "上海 虹桥T1", "深圳 宝安T3",
                    "计划", "计划", "06:40", "08:55",
                    "预计 09/28 06:40", "预计 09/28 08:55"
                ],
                "上海 虹桥T1",
                "深圳 宝安T3",
                28,
                (6, 40),
                (8, 55)
            ),
            (
                [
                    "已送达", "9月25日飞往上海", "查看订单〉",
                    "行前多一点准备，让旅途更轻松~", "计划", "S春秋航空9C8932",
                    "理登机手续。", "广州 白云T3", "上海 虹桥T1",
                    "计划", "计划", "21:15", "23:40",
                    "预计 09/25 21:15", "预计 09/25 23:40"
                ],
                "广州 白云T3",
                "上海 虹桥T1",
                25,
                (21, 15),
                (23, 40)
            )
        ]

        for value in cases {
            let draft = ScreenshotItineraryImportService.parseRecognizedLines(
                value.lines,
                referenceDate: reference
            )
            XCTAssertEqual(draft.title, "\(value.origin) → \(value.destination)")
            XCTAssertEqual(draft.locationMode, .route)
            XCTAssertEqual(draft.originName, value.origin)
            XCTAssertEqual(draft.destinationName, value.destination)
            XCTAssertEqual(draft.address, "")

            let start = calendar.dateComponents([.month, .day, .hour, .minute], from: draft.startTime)
            let end = calendar.dateComponents([.month, .day, .hour, .minute], from: draft.endTime)
            XCTAssertEqual(start.month, 9)
            XCTAssertEqual(start.day, value.day)
            XCTAssertEqual(start.hour, value.start.0)
            XCTAssertEqual(start.minute, value.start.1)
            XCTAssertEqual(end.month, 9)
            XCTAssertEqual(end.day, value.day)
            XCTAssertEqual(end.hour, value.end.0)
            XCTAssertEqual(end.minute, value.end.1)
        }
    }

    func testParsesActualMultiImageTripOCRIntoDatedFlightAndHotelArrangements() throws {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let draft = try ScreenshotItineraryImportService.parseJourneyRecognizedLineGroups(
            [
                [
                    "我的行程", "全部订单", "：酒店", "预订成功〉",
                    "滴水山房花园酒店（上海虹", "桥机场国家会展中心店）",
                    "特惠舒适大床房（优眠床品）•1晚•1间", "09月27日", "09月28日",
                    "入住时间", "离店时间", "◎ 上海长宁区空港一路366号",
                    "•09月28日 周一•前往深圳",
                    "计划|准点率：97%，请提前2个小时到机场办理登机手续。",
                    "S 9C8917 春秋 上海-深圳", "计划起飞", "计划到达",
                    "06:40", "08:55", "虹桥 T1", "2小时15分", "宝安 T3"
                ],
                [
                    "我的行程", "全部订单", "09月25日 周五•前往上海",
                    "计划|准点率：17%，请提前2个小时到机场办理登机手续。",
                    "S 9C8932 春秋 广州-上海", "计划起飞", "计划到达",
                    "21:15", "23:40", "白云 T3", "2小时25分", "虹桥 T1",
                    "日酒店", "预订成功＞", "滴水山房花园酒店（上海虹",
                    "桥机场国家会展中心店）", "特惠舒适大床房（优眠床品）•1晚 1间",
                    "09月25日", "09月26日", "入住时间", "离店时间",
                    "上海长宁区空港一路366号"
                ]
            ],
            referenceDate: reference
        )

        XCTAssertEqual(draft.days.count, 3)
        XCTAssertEqual(
            draft.days.compactMap(\.date).map { calendar.component(.day, from: $0) },
            [25, 27, 28]
        )

        let september25 = draft.days[0]
        XCTAssertEqual(september25.items.count, 2)
        let outboundFlight = try XCTUnwrap(september25.items.first(where: { $0.category == .transport }))
        XCTAssertEqual(outboundFlight.title, "广州 白云T3 → 上海 虹桥T1")
        XCTAssertEqual(outboundFlight.locationMode, .route)
        XCTAssertEqual(outboundFlight.originName, "广州 白云T3")
        XCTAssertEqual(outboundFlight.destinationName, "上海 虹桥T1")
        XCTAssertEqual(calendar.component(.hour, from: outboundFlight.startTime), 21)
        XCTAssertEqual(calendar.component(.minute, from: outboundFlight.startTime), 15)
        XCTAssertEqual(calendar.component(.hour, from: outboundFlight.endTime), 23)
        XCTAssertEqual(calendar.component(.minute, from: outboundFlight.endTime), 40)
        XCTAssertFalse(outboundFlight.note.contains("上海 虹桥T1"))

        let firstHotel = try XCTUnwrap(september25.items.first(where: { $0.category == .hotel }))
        XCTAssertEqual(firstHotel.title, "入住滴水山房花园酒店（上海虹桥机场国家会展中心店）")
        XCTAssertEqual(firstHotel.placeName, "滴水山房花园酒店（上海虹桥机场国家会展中心店）")
        XCTAssertEqual(firstHotel.placeAddress, "上海长宁区空港一路366号")
        XCTAssertEqual(firstHotel.address, "上海长宁区空港一路366号")
        XCTAssertEqual(calendar.component(.day, from: firstHotel.startTime), 25)
        XCTAssertEqual(calendar.component(.hour, from: firstHotel.startTime), 14)
        XCTAssertEqual(calendar.component(.day, from: firstHotel.endTime), 26)
        XCTAssertEqual(calendar.component(.hour, from: firstHotel.endTime), 12)

        let september27Hotel = try XCTUnwrap(draft.days[1].items.first)
        XCTAssertEqual(september27Hotel.category, .hotel)
        XCTAssertEqual(calendar.component(.day, from: september27Hotel.startTime), 27)
        XCTAssertEqual(calendar.component(.day, from: september27Hotel.endTime), 28)

        let returnFlight = try XCTUnwrap(draft.days[2].items.first)
        XCTAssertEqual(returnFlight.category, .transport)
        XCTAssertEqual(returnFlight.title, "上海 虹桥T1 → 深圳 宝安T3")
        XCTAssertEqual(returnFlight.originName, "上海 虹桥T1")
        XCTAssertEqual(returnFlight.destinationName, "深圳 宝安T3")
        XCTAssertEqual(calendar.component(.hour, from: returnFlight.startTime), 6)
        XCTAssertEqual(calendar.component(.minute, from: returnFlight.startTime), 40)
        XCTAssertEqual(calendar.component(.hour, from: returnFlight.endTime), 8)
        XCTAssertEqual(calendar.component(.minute, from: returnFlight.endTime), 55)

        let trip = Trip(title: "上海深圳", destination: "上海、深圳", startDate: reference, endDate: reference)
        let result = JourneyImportApplyService.append(
            draft,
            to: trip,
            attachSourceImages: false,
            calendar: calendar
        )
        XCTAssertEqual(
            result.affectedDays.map { calendar.component(.day, from: $0.date) },
            [25, 26, 27, 28]
        )
        XCTAssertTrue(result.affectedDays[1].items.isEmpty)
        XCTAssertEqual(calendar.component(.day, from: trip.startDate), 25)
        XCTAssertEqual(calendar.component(.day, from: trip.endDate), 28)
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
        XCTAssertEqual(created.createdDays.count, 5)
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
        XCTAssertEqual(appended.createdDays.count, 5)
        XCTAssertEqual(existingTrip.sortedDays.count, 8)
        XCTAssertEqual(appended.createdDays.first?.sortOrder, 3)
        XCTAssertEqual(
            calendar.dateComponents([.day], from: start, to: appended.createdDays.first!.date).day,
            3
        )
        XCTAssertEqual(
            calendar.dateComponents([.day], from: start, to: appended.createdDays.last!.date).day,
            7
        )
    }

    func testJourneyImportRepairsExistingGapBeforeAppending() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        let september2 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2))!
        let draft = try ScreenshotItineraryImportService.parseJourneyInputText(
            "Day 1: 龙井村茶园",
            referenceDate: start
        )
        let trip = Trip(title: "杭州", destination: "杭州", startDate: start, endDate: september2)
        trip.days = [
            TripDay(date: start, title: "第 1 天", sortOrder: 0, trip: trip),
            TripDay(date: september2, title: "第 2 天", sortOrder: 1, trip: trip)
        ]

        let preview = JourneyImportApplyService.preview(draft, for: trip, calendar: calendar)
        let expectedThirdDate = calendar.date(byAdding: .day, value: 2, to: start)!
        XCTAssertEqual(preview.dates, [expectedThirdDate])

        let result = JourneyImportApplyService.append(
            draft,
            to: trip,
            attachSourceImages: false,
            calendar: calendar
        )

        let expectedDates = (0..<3).map { calendar.date(byAdding: .day, value: $0, to: start)! }
        XCTAssertEqual(trip.sortedDays.map(\.date), expectedDates)
        XCTAssertEqual(result.createdDays.map(\.date), [expectedThirdDate])
        XCTAssertEqual(trip.endDate, expectedThirdDate)
    }

    func testParsesMultipleTimedArrangementsOnOneDateWithSingleAndRouteLocations() throws {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6))!
        let draft = try ScreenshotItineraryImportService.parseJourneyInputText(
            """
            9月25日
            09:00–10:30 游览上海世纪公园
            地点：上海世纪公园

            14:00–15:00 前往虹桥机场
            出发地：上海世纪公园
            目的地：上海虹桥国际机场 T2
            """,
            referenceDate: reference
        )

        XCTAssertEqual(draft.days.count, 1)
        let day = try XCTUnwrap(draft.days.first)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(day.date)), 9)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(day.date)), 25)
        XCTAssertEqual(day.items.count, 2, "当天原文：\(day.note.debugDescription)")
        guard day.items.count == 2 else {
            return XCTFail("应将同一天的两个时间区间识别为两段安排")
        }

        let visit = day.items[0]
        XCTAssertEqual(visit.title, "游览上海世纪公园")
        XCTAssertEqual(visit.locationMode, .single)
        XCTAssertEqual(visit.placeName, "上海世纪公园")
        XCTAssertEqual(calendar.component(.hour, from: visit.startTime), 9)
        XCTAssertEqual(calendar.component(.minute, from: visit.endTime), 30)

        let transfer = day.items[1]
        XCTAssertEqual(transfer.title, "上海世纪公园 → 上海虹桥国际机场 T2")
        XCTAssertEqual(transfer.locationMode, .route)
        XCTAssertEqual(transfer.originName, "上海世纪公园")
        XCTAssertEqual(transfer.destinationName, "上海虹桥国际机场 T2")
        XCTAssertEqual(calendar.component(.hour, from: transfer.startTime), 14)
        XCTAssertEqual(calendar.component(.hour, from: transfer.endTime), 15)
    }

    func testJourneyImportMergesIntoExistingDateWithoutReplacingExistingContent() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let trip = Trip(title: "上海", destination: "上海", startDate: date, endDate: date)
        let existingDay = TripDay(date: date, title: "原有日程", sortOrder: 0, trip: trip)
        existingDay.note = "原有备注"
        let existingItem = ItineraryItem(
            title: "原有安排",
            category: .attraction,
            startTime: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)!,
            endTime: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: date)!,
            sortOrder: 0
        )
        existingItem.day = existingDay
        existingDay.items.append(existingItem)
        trip.days.append(existingDay)

        let draftItem = ItineraryJourneyItemDraft(
            title: "识别新安排",
            category: .restaurant,
            startTime: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!,
            endTime: calendar.date(bySettingHour: 13, minute: 0, second: 0, of: date)!,
            address: "",
            placeName: "南京大牌档",
            transport: .walk,
            distanceText: "",
            reservationInfo: "",
            cost: 120,
            note: "识别安排备注"
        )
        let draft = ItineraryJourneyDraft(
            days: [
                ItineraryJourneyDayDraft(
                    sourceDayNumber: 1,
                    date: date,
                    routeTitle: "当天识别摘要",
                    note: "识别当天备注",
                    items: [draftItem]
                )
            ],
            rawText: "",
            sourceAssetIdentifiers: []
        )

        let result = JourneyImportApplyService.append(
            draft,
            to: trip,
            attachSourceImages: false,
            calendar: calendar
        )

        XCTAssertTrue(result.createdDays.isEmpty)
        XCTAssertEqual(result.affectedDays.map(\.id), [existingDay.id])
        XCTAssertEqual(trip.days.count, 1)
        XCTAssertEqual(existingDay.title, "原有日程")
        XCTAssertEqual(existingDay.sortedItems.map(\.title), ["原有安排", "识别新安排"])
        XCTAssertTrue(existingDay.note.contains("原有备注"))
        XCTAssertTrue(existingDay.note.contains("当天识别摘要"))
        XCTAssertTrue(existingDay.note.contains("识别当天备注"))
    }

    func testJourneyImportCreatesEmptyDaysForMissingSourceDayNumbers() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let draft = try ScreenshotItineraryImportService.parseJourneyInputText(
            """
            Day 1: 成都 → 四姑娘山
            Day 3: 丹巴 → 新都桥
            """,
            referenceDate: start
        )
        XCTAssertEqual(draft.days.map(\.sourceDayNumber), [1, 3])

        let trip = Trip(title: "川西", destination: "川西", startDate: start, endDate: start)
        let result = JourneyImportApplyService.append(
            draft,
            to: trip,
            attachSourceImages: false,
            calendar: calendar
        )

        XCTAssertEqual(result.createdDays.count, 3)
        XCTAssertEqual(trip.sortedDays.count, 3)
        XCTAssertFalse(trip.sortedDays[0].items.isEmpty)
        XCTAssertTrue(trip.sortedDays[1].items.isEmpty)
        XCTAssertFalse(trip.sortedDays[2].items.isEmpty)
        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: trip.endDate).day, 2)
    }
}
