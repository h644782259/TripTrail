import XCTest
import UIKit
@testable import TripTrail

final class ZhipuVisionItineraryServiceTests: XCTestCase {
    override func tearDown() {
        ZhipuVisionURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testLargeModelDefaultsFollowAPIKeyAvailability() {
        XCTAssertFalse(
            EnhancedRecognitionSettings.resolvedIsEnabled(
                storedPreference: nil,
                hasAPIKey: false
            )
        )
        XCTAssertTrue(
            EnhancedRecognitionSettings.resolvedIsEnabled(
                storedPreference: nil,
                hasAPIKey: true
            )
        )
        XCTAssertFalse(
            EnhancedRecognitionSettings.resolvedIsEnabled(
                storedPreference: false,
                hasAPIKey: true
            )
        )
    }

#if targetEnvironment(simulator)
    func testAPIKeyStoreCanSaveAndReloadInSimulator() throws {
        let apiKey = "unit-test-\(UUID().uuidString)"
        defer { try? ZhipuAPIKeyStore.delete() }

        try ZhipuAPIKeyStore.save(apiKey)

        XCTAssertTrue(ZhipuAPIKeyStore.hasAPIKey)
        XCTAssertEqual(ZhipuAPIKeyStore.load(), apiKey)

        try ZhipuAPIKeyStore.delete()
        XCTAssertFalse(ZhipuAPIKeyStore.hasAPIKey)
    }
#endif

    func testDecodesMultiImageJourneyJSONIntoDatedArrangements() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let content = """
        ```json
        {
          "days": [
            {
              "date": "2026-09-28",
              "routeTitle": "前往深圳",
              "note": "",
              "items": [{
                "title": "春秋航空 9C8917",
                "category": "transport",
                "startAt": "2026-09-28 06:40",
                "endAt": "2026-09-28 08:55",
                "address": "",
                "transport": "flight",
                "origin": "上海 虹桥T1",
                "destination": "深圳 宝安T3",
                "distanceText": "2小时15分",
                "reservationInfo": "航班：9C8917",
                "cost": 0,
                "note": "",
                "sourceText": "上海-深圳 06:40 08:55 虹桥T1 宝安T3"
              }]
            },
            {
              "date": "2026-09-25",
              "routeTitle": "前往上海",
              "note": "",
              "items": [{
                "title": "春秋航空 9C8932",
                "category": "transport",
                "startAt": "2026-09-25 21:15",
                "endAt": "2026-09-25 23:40",
                "address": "",
                "transport": "flight",
                "origin": "广州 白云T3",
                "destination": "上海 虹桥T1",
                "distanceText": "2小时25分",
                "reservationInfo": "航班：9C8932",
                "cost": "0",
                "note": "",
                "sourceText": "广州-上海 21:15 23:40 白云T3 虹桥T1"
              }, {
                "title": "滴水山房花园酒店（上海虹桥机场国家会展中心店）",
                "category": "hotel",
                "startAt": "2026-09-25 14:00",
                "endAt": "2026-09-26 12:00",
                "address": "上海长宁区空港一路366号",
                "transport": "car",
                "origin": "",
                "destination": "",
                "distanceText": "",
                "reservationInfo": "特惠舒适大床房",
                "cost": 0,
                "note": "",
                "sourceText": "09月25日入住 09月26日离店"
              }]
            },
            {
              "date": "2026-09-27",
              "routeTitle": "入住上海",
              "note": "",
              "items": [{
                "title": "滴水山房花园酒店（上海虹桥机场国家会展中心店）",
                "category": "hotel",
                "startAt": null,
                "endAt": null,
                "address": "上海长宁区空港一路366号",
                "transport": "car",
                "origin": "",
                "destination": "",
                "distanceText": "",
                "reservationInfo": "",
                "cost": 0,
                "note": "",
                "sourceText": "09月27日 09月28日 入住时间 离店时间"
              }]
            }
          ]
        }
        ```
        """

        let draft = try ZhipuVisionItineraryService.decodeJourneyContent(
            content,
            referenceDate: reference,
            sourceAssetIdentifiers: ["first", "second"]
        )

        XCTAssertEqual(draft.days.compactMap(\.date).map { calendar.component(.day, from: $0) }, [25, 27, 28])
        XCTAssertEqual(draft.sourceAssetIdentifiers, ["first", "second"])

        let firstDay = draft.days[0]
        XCTAssertEqual(firstDay.items.count, 2)
        let outboundFlight = try XCTUnwrap(firstDay.items.first(where: { $0.transport == .flight }))
        XCTAssertEqual(outboundFlight.title, "春秋航空 9C8932")
        XCTAssertEqual(outboundFlight.locationMode, .route)
        XCTAssertEqual(outboundFlight.originName, "广州 白云T3")
        XCTAssertEqual(outboundFlight.destinationName, "上海 虹桥T1")
        XCTAssertEqual(outboundFlight.address, "")
        XCTAssertEqual(calendar.component(.hour, from: outboundFlight.startTime), 21)
        XCTAssertEqual(calendar.component(.minute, from: outboundFlight.startTime), 15)
        XCTAssertEqual(calendar.component(.hour, from: outboundFlight.endTime), 23)
        XCTAssertFalse(outboundFlight.note.contains("上海 虹桥T1"))

        let firstHotel = try XCTUnwrap(firstDay.items.first(where: { $0.category == .hotel }))
        XCTAssertEqual(firstHotel.address, "上海长宁区空港一路366号")
        XCTAssertEqual(calendar.component(.day, from: firstHotel.endTime), 26)
        XCTAssertEqual(calendar.component(.hour, from: firstHotel.endTime), 12)

        let secondHotel = try XCTUnwrap(draft.days[1].items.first)
        XCTAssertEqual(calendar.component(.hour, from: secondHotel.startTime), 14)
        XCTAssertEqual(calendar.component(.day, from: secondHotel.endTime), 28)
        XCTAssertEqual(calendar.component(.hour, from: secondHotel.endTime), 12)

        let returnFlight = try XCTUnwrap(draft.days[2].items.first)
        XCTAssertEqual(returnFlight.title, "春秋航空 9C8917")
        XCTAssertEqual(returnFlight.originName, "上海 虹桥T1")
        XCTAssertEqual(returnFlight.destinationName, "深圳 宝安T3")
        XCTAssertEqual(calendar.component(.hour, from: returnFlight.startTime), 6)
        XCTAssertEqual(calendar.component(.minute, from: returnFlight.endTime), 55)
    }

    func testDecodesJSONAfterThinkingBlockAndBuildsSingleItemDraft() throws {
        let reference = Date(timeIntervalSince1970: 1_788_710_400)
        let content = """
        <think>这里是不应进入 JSON 解析的思考内容。</think>
        {"days":[{"date":"2026-09-05","routeTitle":"","note":"","items":[{"title":"东方明珠","category":"attraction","startAt":"2026-09-05 09:00","endAt":"2026-09-05 11:00","address":"上海市浦东新区世纪大道1号","transport":"walk","origin":"","destination":"","distanceText":"","reservationInfo":"","cost":0,"note":"","sourceText":"东方明珠 09:00-11:00"}]}]}
        """

        let journey = try ZhipuVisionItineraryService.decodeJourneyContent(content, referenceDate: reference)
        let item = try XCTUnwrap(ZhipuVisionItineraryService.singleItemDraft(from: journey))

        XCTAssertEqual(item.title, "东方明珠")
        XCTAssertEqual(item.category, .attraction)
        XCTAssertEqual(item.transport, .walk)
        XCTAssertEqual(item.travelDurationMinutes, 120)
        XCTAssertEqual(item.address, "上海市浦东新区世纪大道1号")
    }

    func testV2JourneyKeepsDayNumbersRelativeWhenSourceHasNoDates() throws {
        let reference = Date(timeIntervalSince1970: 1_788_710_400)
        let days = (1...6).map { day in
            """
            {"dayNumber":\(day),"date":null,"title":"第\(day)天","note":"","items":[{"title":"游览地点\(day)","category":"attraction","startAt":null,"endAt":null,"locationMode":"单地点","placeName":"地点\(day)","placeAddress":"","transport":"car","origin":"","destination":"","distanceText":"","reservationInfo":"","cost":0,"note":"","sourceText":"Day\(day) 地点\(day)"}]}
            """
        }.joined(separator: ",")
        let content = """
        {"schemaVersion":2,"kind":"itinerary_journey","days":[\(days)]}
        """

        let draft = try ZhipuVisionItineraryService.decodeJourneyContent(
            content,
            referenceDate: reference
        )

        XCTAssertEqual(draft.days.count, 6)
        XCTAssertEqual(draft.days.map(\.sourceDayNumber), [1, 2, 3, 4, 5, 6])
        XCTAssertTrue(draft.days.allSatisfy { $0.date == nil })
        XCTAssertEqual(draft.days[4].routeTitle, "第5天")
        XCTAssertEqual(draft.days[5].items[0].placeName, "地点6")
    }

    func testSendsImageToFreeVisionModelAndDecodesResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ZhipuVisionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let responseContent = #"{"schemaVersion":2,"kind":"itinerary_journey","days":[{"date":"2026-09-25","routeTitle":"前往上海","note":"","items":[{"title":"春秋航空9C8932","category":"transport","startAt":"2026-09-25 21:15","endAt":"2026-09-25 23:40","address":"","transport":"flight","origin":"广州 白云T3","destination":"上海 虹桥T1","distanceText":"2小时25分","reservationInfo":"航班：9C8932","cost":0,"note":"","sourceText":"广州-上海"}]}]}"#
        let envelope: [String: Any] = [
            "choices": [["message": ["content": responseContent]]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: envelope)

        ZhipuVisionURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://open.bigmodel.cn/api/paas/v4/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.timeoutInterval, 90)
            let bodyData = try XCTUnwrap(ZhipuVisionURLProtocol.bodyData(from: request))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, "glm-4.6v-flash")
            XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_object")
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
            XCTAssertEqual(content.count, 2)
            XCTAssertEqual(content.last?["type"] as? String, "image_url")
            let imageURL = try XCTUnwrap(content.last?["image_url"] as? [String: String])
            XCTAssertTrue(imageURL["url"]?.hasPrefix("data:image/jpeg;base64,") == true)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseData)
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let imageData = try XCTUnwrap(image.pngData())
        let reference = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 9, day: 20)
        )!

        let draft = try await ZhipuVisionItineraryService.recognizeJourney(
            imageDatas: [imageData],
            referenceDate: reference,
            sourceAssetIdentifiers: ["asset"],
            apiKey: "test-key",
            session: session
        )

        XCTAssertEqual(draft.days.count, 1)
        XCTAssertEqual(draft.days[0].items[0].title, "春秋航空9C8932")
        XCTAssertEqual(draft.days[0].items[0].originName, "广州 白云T3")
        XCTAssertEqual(draft.days[0].items[0].destinationName, "上海 虹桥T1")
        XCTAssertEqual(draft.days[0].items[0].transport, .flight)
        XCTAssertEqual(draft.sourceAssetIdentifiers, ["asset"])
    }

    func testSendsJourneyTextToFreeTextModelAndDecodesAllDays() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ZhipuVisionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let responseContent = #"{"schemaVersion":2,"kind":"itinerary_journey","days":[{"date":"2026-09-25","routeTitle":"抵达上海","note":"","items":[{"title":"广州 白云T3","category":"transport","startAt":"2026-09-25 21:15","endAt":"2026-09-25 23:40","address":"","transport":"flight","origin":"广州 白云T3","destination":"上海 虹桥T1","distanceText":"2小时25分","reservationInfo":"9C8932","cost":0,"note":"","sourceText":"9/25 21:15-23:40 广州到上海"}]},{"date":"2026-09-26","routeTitle":"上海游览","note":"","items":[{"title":"东方明珠","category":"attraction","startAt":"2026-09-26 09:00","endAt":"2026-09-26 11:00","address":"上海市浦东新区世纪大道1号","transport":"walk","origin":"","destination":"","distanceText":"","reservationInfo":"","cost":0,"note":"","sourceText":"9/26 东方明珠 09:00-11:00"}]}]}"#
        let envelope: [String: Any] = [
            "choices": [["message": ["content": responseContent]]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: envelope)

        ZhipuVisionURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://open.bigmodel.cn/api/paas/v4/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer text-key")
            XCTAssertEqual(request.timeoutInterval, 90)
            let bodyData = try XCTUnwrap(ZhipuVisionURLProtocol.bodyData(from: request))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, "glm-4.7-flash")
            XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_object")
            XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "disabled")
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.first?["content"] as? String)
            XCTAssertTrue(content.contains("9/25 21:15-23:40 广州到上海"))
            XCTAssertTrue(content.contains("必须提取全部 Day 和全部安排"))
            XCTAssertTrue(content.contains("<user_itinerary_text>"))
            XCTAssertTrue(content.contains("itinerary_journey_v2"))
            XCTAssertTrue(content.contains("仅有 DayN 时 date 必须为 null"))
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseData)
        }

        let reference = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 9, day: 20)
        )!
        let draft = try await ZhipuVisionItineraryService.recognizeJourneyText(
            "9/25 21:15-23:40 广州到上海\n9/26 东方明珠 09:00-11:00",
            referenceDate: reference,
            apiKey: "text-key",
            session: session
        )

        XCTAssertEqual(draft.days.count, 2)
        XCTAssertEqual(draft.days[0].items[0].title, "广州 白云T3 → 上海 虹桥T1")
        XCTAssertEqual(draft.days[0].items[0].originName, "广州 白云T3")
        XCTAssertEqual(draft.days[0].items[0].destinationName, "上海 虹桥T1")
        XCTAssertEqual(
            Int(draft.days[0].items[0].endTime.timeIntervalSince(draft.days[0].items[0].startTime) / 60),
            145
        )
        XCTAssertEqual(draft.days[1].items[0].title, "东方明珠")
    }

    func testSingleTextPromptRequestsOnlyOneItem() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ZhipuVisionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let responseContent = #"{"schemaVersion":2,"kind":"itinerary_item","item":{"title":"游览东方明珠","category":"attraction","startAt":"2026-09-26 09:00","endAt":"2026-09-26 11:00","locationMode":"单地点","placeName":"东方明珠","placeAddress":"上海市浦东新区世纪大道1号","transport":"walk","origin":"","destination":"","distanceText":"","reservationInfo":"","cost":0,"note":"","sourceText":"东方明珠 09:00-11:00"}}"#
        let responseData = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": responseContent]]]
        ])

        ZhipuVisionURLProtocol.requestHandler = { request in
            let bodyData = try XCTUnwrap(ZhipuVisionURLProtocol.bodyData(from: request))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.first?["content"] as? String)
            XCTAssertTrue(content.contains("itinerary_item_v2"))
            XCTAssertTrue(content.contains("不要返回 days 数组"))
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseData)
        }

        let item = try await ZhipuVisionItineraryService.recognizeSingleItemText(
            "9月26日 09:00-11:00 东方明珠",
            referenceDate: Date(timeIntervalSince1970: 1_788_710_400),
            apiKey: "text-key",
            purpose: .itinerary,
            session: session
        )

        XCTAssertEqual(item.title, "游览东方明珠")
        XCTAssertEqual(item.placeName, "东方明珠")
        XCTAssertEqual(item.travelDurationMinutes, 120)
    }

    func testFavoriteTextPromptUsesFavoriteProtocolWithoutTimeFields() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ZhipuVisionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let responseContent = #"{"schemaVersion":2,"kind":"favorite_item","item":{"title":"想去羊卓雍措","category":"attraction","locationMode":"单地点","placeName":"羊卓雍措","placeAddress":"","transport":"car","origin":"","destination":"","distanceText":"","cost":100,"note":"2号观景台更出片","sourceText":"羊卓雍措，门票100"}}"#
        let responseData = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": responseContent]]]
        ])

        ZhipuVisionURLProtocol.requestHandler = { request in
            let bodyData = try XCTUnwrap(ZhipuVisionURLProtocol.bodyData(from: request))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.first?["content"] as? String)
            XCTAssertTrue(content.contains("favorite_item_v2"))
            XCTAssertTrue(content.contains("不得生成日期、开始时间、结束时间"))
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseData)
        }

        let item = try await ZhipuVisionItineraryService.recognizeSingleItemText(
            "羊卓雍措，门票100，2号观景台更出片",
            referenceDate: Date(timeIntervalSince1970: 1_788_710_400),
            apiKey: "text-key",
            purpose: .favorite,
            session: session
        )

        XCTAssertEqual(item.placeName, "羊卓雍措")
        XCTAssertEqual(item.cost, 100)
        XCTAssertEqual(item.note, "2号观景台更出片")
    }

    func testJourneyProtocolRejectsMissingExpectedDays() throws {
        let responseContent = #"{"schemaVersion":2,"kind":"itinerary_journey","days":[{"dayNumber":1,"date":null,"title":"第1天","note":"","items":[{"title":"羊卓雍措","category":"attraction","startAt":null,"endAt":null,"locationMode":"单地点","placeName":"羊卓雍措","placeAddress":"","transport":"car","origin":"","destination":"","distanceText":"","reservationInfo":"","cost":0,"note":"","sourceText":"Day1 羊卓雍措"}]}]}"#

        XCTAssertThrowsError(
            try ZhipuVisionItineraryService.decodeJourneyContent(
                responseContent,
                referenceDate: Date(timeIntervalSince1970: 1_788_710_400),
                expectedDayNumbers: Set(1...6),
                validatingProtocol: true
            )
        ) { error in
            guard case ZhipuVisionItineraryError.invalidStructuredResult = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let partialDraft = try ZhipuVisionItineraryService.decodeJourneyContent(
            responseContent,
            referenceDate: Date(timeIntervalSince1970: 1_788_710_400),
            validatingProtocol: true
        )
        XCTAssertThrowsError(
            try SmartItineraryRecognitionService.validatedJourneyDraft(
                partialDraft,
                expectedDayNumbers: Set(1...6)
            )
        )
        XCTAssertEqual(
            SmartItineraryRecognitionService.explicitDayNumbers(
                in: "Day1 拉萨\nDay2 日喀则\nDay3 岗嘎\nDay4 错勤\nDay5 文布村\nDay6 拉萨"
            ),
            Set(1...6)
        )
    }

    func testJourneyTextRejectsIncompleteDaySequenceFromModel() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ZhipuVisionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let responseContent = #"{"schemaVersion":2,"kind":"itinerary_journey","days":[{"dayNumber":1,"date":null,"title":"第1天","note":"","items":[{"title":"羊卓雍措","category":"attraction","startAt":null,"endAt":null,"locationMode":"单地点","placeName":"羊卓雍措","placeAddress":"","transport":"car","origin":"","destination":"","distanceText":"","reservationInfo":"","cost":0,"note":"","sourceText":"Day1 羊卓雍措"}]}]}"#
        let responseData = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": responseContent]]]
        ])
        ZhipuVisionURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseData)
        }

        do {
            _ = try await ZhipuVisionItineraryService.recognizeJourneyText(
                "Day1 拉萨\nDay2 日喀则\nDay3 岗嘎\nDay4 错勤\nDay5 文布村\nDay6 拉萨",
                referenceDate: Date(timeIntervalSince1970: 1_788_710_400),
                apiKey: "text-key",
                session: session
            )
            XCTFail("Incomplete day sequence should be rejected")
        } catch ZhipuVisionItineraryError.invalidStructuredResult {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSingleItemProtocolRejectsWrongModuleKind() throws {
        let responseContent = #"{"schemaVersion":2,"kind":"itinerary_item","item":{"title":"羊卓雍措","category":"attraction","locationMode":"单地点","placeName":"羊卓雍措","placeAddress":"","transport":"car","origin":"","destination":"","distanceText":"","cost":0,"note":"","sourceText":"羊卓雍措"}}"#

        XCTAssertThrowsError(
            try ZhipuVisionItineraryService.decodeSingleItemContent(
                responseContent,
                referenceDate: Date(timeIntervalSince1970: 1_788_710_400),
                expectedKind: "favorite_item",
                validatingProtocol: true
            )
        ) { error in
            guard case ZhipuVisionItineraryError.invalidStructuredResult = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testTimedOutEnhancedRecognitionAnnotatesLocalOCRFallback() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_788_710_400)
        let localDraft = try ScreenshotItineraryImportService.parseInputText(
            "09:00-10:00 东方明珠",
            referenceDate: referenceDate
        )

        let recovered: ItineraryScreenshotDraft = try await SmartItineraryRecognitionService
            .recognizeWithLocalFallback(
                notice: SmartItineraryRecognitionService.FallbackNotice.localOCR,
                enhancedRecognition: {
                    throw URLError(.timedOut)
                },
                localRecognition: {
                    localDraft
                }
            )

        XCTAssertEqual(recovered.title, localDraft.title)
        XCTAssertEqual(
            recovered.recognitionNotice,
            "大模型识别失败或超时，已改用本地 OCR 识别。请在保存前核对结果。 原因：智谱请求超过 90 秒。"
        )
    }
}

private final class ZhipuVisionURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
