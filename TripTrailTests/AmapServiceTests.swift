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

    func testSingleDestinationUsesNativeAmapSchemeAndCurrentLocationAsStart() throws {
        let stop = AmapStop(name: "西湖", address: "杭州")
        let url = try XCTUnwrap(AmapService.navigationURL(to: stop, mode: .walk))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try XCTUnwrap(components.queryItems)
        let pairs: [(String, String)] = try items.map { item in
            (item.name, try XCTUnwrap(item.value))
        }
        let query = Dictionary(uniqueKeysWithValues: pairs)
        XCTAssertEqual(components.scheme, "iosamap")
        XCTAssertEqual(components.host, "path")
        XCTAssertEqual(query["dname"], "西湖 杭州")
        XCTAssertEqual(query["t"], "2")
        XCTAssertNil(query["slat"])
        XCTAssertNil(query["slon"])
    }

    func testNavigationUsesPlaceNameAndAddressWithoutCoordinateParameters() throws {
        let stop = AmapStop(name: "西湖", address: "杭州")
        let url = try XCTUnwrap(AmapService.navigationURL(to: stop, mode: .walk))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(components.queryItems).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        XCTAssertEqual(components.scheme, "iosamap")
        XCTAssertEqual(components.host, "path")
        XCTAssertEqual(query["dname"], "西湖 杭州")
        XCTAssertNil(query["dlat"])
        XCTAssertNil(query["dlon"])
        XCTAssertNil(query["dev"])
    }

    func testNativeAmapRouteTypes() throws {
        let stop = AmapStop(name: "西湖", address: "杭州")
        let expected: [(TransportMode, String)] = [(.car, "0"), (.bus, "1"), (.walk, "2"), (.ride, "3")]
        for (mode, type) in expected {
            let url = try XCTUnwrap(AmapService.navigationURL(to: stop, mode: mode))
            let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems).compactMap { item in
                item.value.map { (item.name, $0) }
            })
            XCTAssertEqual(query["t"], type)
        }
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
