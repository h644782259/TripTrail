import XCTest
@testable import TripTrail

@MainActor
final class AmapServiceTests: XCTestCase {
    func testTransportValuesMatchAmapURI() {
        XCTAssertEqual(TransportMode.car.amapValue, "car")
        XCTAssertEqual(TransportMode.walk.amapValue, "walk")
        XCTAssertEqual(TransportMode.ride.amapValue, "ride")
        XCTAssertEqual(TransportMode.bus.amapValue, "bus")
    }

    func testSingleDestinationUsesAmapRoutePlanningWithResolvedDestination() throws {
        let stop = AmapStop(
            name: "杭州东站",
            address: "天城路1号",
            latitude: 30.292003,
            longitude: 120.21212
        )
        let url = try XCTUnwrap(AmapService.navigationURL(to: stop, mode: .walk))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try XCTUnwrap(components.queryItems)
        let pairs: [(String, String)] = try items.map { item in
            (item.name, try XCTUnwrap(item.value))
        }
        let query = Dictionary(uniqueKeysWithValues: pairs)
        XCTAssertEqual(components.scheme, "iosamap")
        XCTAssertEqual(components.host, "path")
        XCTAssertEqual(query["dname"], "杭州东站")
        XCTAssertEqual(query["dlat"], "30.292003")
        XCTAssertEqual(query["dlon"], "120.21212")
        XCTAssertEqual(query["dev"], "1")
        XCTAssertEqual(query["t"], "2")
        XCTAssertNil(query["poiname"])
        XCTAssertNil(query["style"])
    }

    func testNavigationRequiresCoordinatesToAvoidAmapDestinationCandidatePage() {
        let stop = AmapStop(name: "西湖", address: "杭州")
        XCTAssertNil(AmapService.navigationURL(to: stop, mode: .walk))
    }

    func testNavigationFallsBackToAddressOnlyWhenCurrentTextIsEmpty() throws {
        let stop = AmapStop(
            name: "  \n",
            address: "  杭州市西湖区北山街  ",
            latitude: 30.2525,
            longitude: 120.1495
        )
        let url = try XCTUnwrap(AmapService.navigationURL(to: stop, mode: .car))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(components.queryItems).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        XCTAssertEqual(query["dname"], "杭州市西湖区北山街")
    }

    func testNavigationRejectsInvalidCoordinate() {
        let stop = AmapStop(name: "西湖", address: "杭州", latitude: 130, longitude: 120.15)
        XCTAssertNil(AmapService.navigationURL(to: stop, mode: .car))
    }

    func testBestMatchPrefersCurrentTextExactName() throws {
        let places = [
            ResolvedPlace(name: "杭州东站东停车场（入口）", address: "东宁路", latitude: 30.29, longitude: 120.22),
            ResolvedPlace(name: "杭州东站", address: "天城路1号", latitude: 30.292, longitude: 120.212)
        ]

        let match = try XCTUnwrap(AmapService.bestMatch(for: " 杭州东站 ", in: places))
        XCTAssertEqual(match.name, "杭州东站")
        XCTAssertEqual(match.latitude, 30.292)
    }

    func testRoutePlanningKeepsTransportMode() throws {
        let stop = AmapStop(name: "西湖", address: "杭州", latitude: 30.25, longitude: 120.15)
        let expected: [(TransportMode, String)] = [(.car, "0"), (.bus, "1"), (.walk, "2"), (.ride, "3")]

        for (mode, type) in expected {
            let url = try XCTUnwrap(AmapService.navigationURL(to: stop, mode: mode))
            let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems).compactMap { item in
                item.value.map { (item.name, $0) }
            })
            XCTAssertEqual(query["t"], type)
        }
    }

    func testMultiStopRouteUsesOfficialAmapWaypointParametersInOrder() throws {
        let stops = [
            AmapStop(name: "上海虹桥国际机场 T2", address: "", latitude: 31.1979, longitude: 121.3269),
            AmapStop(name: "武康大楼", address: "", latitude: 31.2014, longitude: 121.4372),
            AmapStop(name: "外滩", address: "", latitude: 31.2401, longitude: 121.4908),
            AmapStop(name: "东方明珠", address: "", latitude: 31.2397, longitude: 121.4998)
        ]

        let url = try XCTUnwrap(AmapService.routeURL(stops: stops, mode: .car))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(components.queryItems).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(components.scheme, "iosamap")
        XCTAssertEqual(components.host, "path")
        XCTAssertEqual(query["sname"], "上海虹桥国际机场 T2")
        XCTAssertEqual(query["dname"], "东方明珠")
        XCTAssertEqual(query["vian"], "2")
        XCTAssertEqual(query["vianames"], "武康大楼|外滩")
        XCTAssertEqual(query["vialons"], "121.4372|121.4908")
        XCTAssertEqual(query["vialats"], "31.2014|31.2401")
        XCTAssertEqual(query["dev"], "1")
        XCTAssertEqual(query["t"], "0")
    }

    func testMultiStopRouteRequiresAtLeastTwoResolvedPlaces() {
        let stop = AmapStop(name: "外滩", address: "", latitude: 31.24, longitude: 121.49)
        XCTAssertNil(AmapService.routeURL(stops: [stop], mode: .car))
        XCTAssertNil(
            AmapService.routeURL(
                stops: [stop, AmapStop(name: "东方明珠", address: "")],
                mode: .car
            )
        )
    }

    func testOpenResultMessagesDistinguishInvalidPlaceFromMissingApp() {
        XCTAssertEqual(
            AmapOpenResult.placeNotFound.message(destinationName: "错误地点"),
            "没有找到“错误地点”，请检查地点名称后再试。"
        )
        XCTAssertEqual(
            AmapOpenResult.placeSearchFailed.message(destinationName: "错误地点"),
            "地点查询失败，请检查网络后重试。"
        )
        XCTAssertNotEqual(
            AmapOpenResult.placeNotFound.message(destinationName: "错误地点"),
            AmapOpenResult.appUnavailable.message(destinationName: "错误地点")
        )
    }

    func testXiaohongshuSearchURLKeepsChineseKeyword() throws {
        let url = try XCTUnwrap(
            PlaceDiscoveryService.nativeSearchURL(for: .xiaohongshu, keyword: "外滩 上海市黄浦区")
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "xhsdiscover")
        XCTAssertEqual(components.host, "search")
        XCTAssertEqual(components.path, "/result")
        XCTAssertEqual(components.queryItems?.first?.value, "外滩 上海市黄浦区")
    }

    func testDouyinSearchURLKeepsChineseKeyword() throws {
        let url = try XCTUnwrap(
            PlaceDiscoveryService.nativeSearchURL(for: .douyin, keyword: "外滩 上海市黄浦区")
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "snssdk1128")
        XCTAssertEqual(components.host, "search")
        XCTAssertEqual(components.queryItems?.first?.value, "外滩 上海市黄浦区")
    }

    func testDiscoveryWebFallbackURLs() throws {
        let xiaohongshuURL = try XCTUnwrap(
            PlaceDiscoveryService.webSearchURL(for: .xiaohongshu, keyword: "西湖 杭州")
        )
        let douyinURL = try XCTUnwrap(
            PlaceDiscoveryService.webSearchURL(for: .douyin, keyword: "西湖 杭州")
        )
        XCTAssertEqual(xiaohongshuURL.host, "www.xiaohongshu.com")
        XCTAssertEqual(douyinURL.host, "www.douyin.com")
        XCTAssertTrue(douyinURL.path.contains("西湖 杭州"))
    }
}
