import Foundation
import UIKit

struct AmapStop: Equatable {
    let name: String
    let address: String
    let latitude: Double?
    let longitude: Double?

    init(
        name: String,
        address: String,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }

    var hasValidCoordinate: Bool {
        guard let latitude, let longitude else { return false }
        return (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

enum AmapOpenResult: Equatable {
    case opened
    case appUnavailable
    case placeNotFound
    case placeSearchFailed
    case openFailed

    func message(destinationName: String) -> String? {
        let name = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .opened:
            return nil
        case .appUnavailable:
            #if targetEnvironment(simulator)
            return "当前 iPhone 模拟器没有安装高德地图 App。模拟器与手机是独立环境，请在已安装高德地图的真机上测试。"
            #else
            return "未检测到高德地图 App，请确认已安装或更新到最新版本后重试。"
            #endif
        case .placeNotFound:
            return name.isEmpty
                ? "没有找到可用的目的地，请检查地点名称后再试。"
                : "没有找到“\(name)”，请检查地点名称后再试。"
        case .placeSearchFailed:
            return "地点查询失败，请检查网络后重试。"
        case .openFailed:
            return "暂时无法打开高德地图，请稍后重试。"
        }
    }
}

@MainActor
enum AmapService {
    private static let source = "TripTrail"
    private static let nativeAppProbeURL = URL(string: "iosamap://path")!

    static func openPlace(
        name: String,
        address: String,
        mode: TransportMode = .car
    ) async -> AmapOpenResult {
        guard UIApplication.shared.canOpenURL(nativeAppProbeURL) else { return .appUnavailable }
        let stop = AmapStop(name: name, address: address)
        return await openResolvedStop(stop, mode: mode)
    }

    static func openRoute(stops: [AmapStop], mode: TransportMode) async -> AmapOpenResult {
        guard UIApplication.shared.canOpenURL(nativeAppProbeURL) else { return .appUnavailable }
        guard stops.count >= 2 else { return .placeNotFound }

        var resolvedStops: [AmapStop] = []
        for stop in stops {
            switch await resolvedStop(for: stop) {
            case .resolved(let resolvedStop):
                resolvedStops.append(resolvedStop)
            case .notFound:
                return .placeNotFound
            case .searchFailed:
                return .placeSearchFailed
            }
        }

        guard let url = routeURL(stops: resolvedStops, mode: mode) else { return .placeNotFound }
        return await UIApplication.shared.open(url) ? .opened : .openFailed
    }

    static func navigationURL(to stop: AmapStop, mode: TransportMode) -> URL? {
        let placeName = stop.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = stop.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationName = placeName.isEmpty ? address : placeName
        guard !destinationName.isEmpty,
              stop.hasValidCoordinate,
              let latitude = stop.latitude,
              let longitude = stop.longitude
        else { return nil }

        var components = URLComponents()
        components.scheme = "iosamap"
        components.host = "path"
        let queryItems = [
            URLQueryItem(name: "sourceApplication", value: source),
            URLQueryItem(name: "dname", value: destinationName),
            URLQueryItem(name: "dlat", value: String(latitude)),
            URLQueryItem(name: "dlon", value: String(longitude)),
            // 高德 Web 服务返回 GCJ-02 坐标，不再二次偏移。
            URLQueryItem(name: "dev", value: "0"),
            URLQueryItem(name: "t", value: routeType(for: mode))
        ]
        components.queryItems = queryItems
        return components.url
    }

    static func routeURL(stops rawStops: [AmapStop], mode: TransportMode) -> URL? {
        var stops: [AmapStop] = []
        for stop in rawStops {
            if let previous = stops.last, previous.hasValidCoordinate, stop.hasValidCoordinate,
               previous.latitude == stop.latitude, previous.longitude == stop.longitude { continue }
            stops.append(stop)
        }
        guard stops.count >= 2, stops.allSatisfy(\.hasValidCoordinate) else { return nil }
        let start = stops[0]
        let end = stops[stops.count - 1]
        guard
            let startLatitude = start.latitude,
            let startLongitude = start.longitude,
            let endLatitude = end.latitude,
            let endLongitude = end.longitude
        else { return nil }

        let startName = stopDisplayName(start)
        let endName = stopDisplayName(end)
        guard !startName.isEmpty, !endName.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "iosamap"
        components.host = "path"
        components.queryItems = [
            URLQueryItem(name: "sourceApplication", value: source),
            URLQueryItem(name: "sid", value: ""),
            URLQueryItem(name: "slat", value: String(startLatitude)),
            URLQueryItem(name: "slon", value: String(startLongitude)),
            URLQueryItem(name: "sname", value: startName),
            URLQueryItem(name: "did", value: ""),
            URLQueryItem(name: "dlat", value: String(endLatitude)),
            URLQueryItem(name: "dlon", value: String(endLongitude)),
            URLQueryItem(name: "dname", value: endName),
            // 与 Android 对齐，所有点位使用高德 GCJ-02 坐标。
            URLQueryItem(name: "dev", value: "0"),
            URLQueryItem(name: "t", value: routeType(for: mode))
        ]

        let viaStops = Array(stops.dropFirst().dropLast())
        if !viaStops.isEmpty {
            let viaLongitudes = viaStops.compactMap(\.longitude).map { String($0) }.joined(separator: "|")
            let viaLatitudes = viaStops.compactMap(\.latitude).map { String($0) }.joined(separator: "|")
            let viaNames = viaStops.map { stopDisplayName($0).replacingOccurrences(of: "|", with: "｜") }.joined(separator: "|")
            components.queryItems?.append(contentsOf: [
                URLQueryItem(name: "vian", value: String(viaStops.count)),
                URLQueryItem(name: "vialons", value: viaLongitudes),
                URLQueryItem(name: "vialats", value: viaLatitudes),
                URLQueryItem(name: "vianames", value: viaNames)
            ])
        }
        return components.url
    }

    static func bestMatch(for destinationName: String, in places: [ResolvedPlace]) -> ResolvedPlace? {
        let expected = normalizedPlaceName(destinationName)
        guard !expected.isEmpty else { return nil }

        return places.first { normalizedPlaceName($0.name) == expected }
            ?? places.first {
                let candidate = normalizedPlaceName($0.name)
                return candidate.contains(expected) || expected.contains(candidate)
            }
            ?? places.first
    }

    private static func openResolvedStop(_ stop: AmapStop, mode: TransportMode) async -> AmapOpenResult {
        let resolution = await resolvedStop(for: stop)
        let resolvedStop: AmapStop
        switch resolution {
        case .resolved(let stop):
            resolvedStop = stop
        case .notFound:
            return .placeNotFound
        case .searchFailed:
            return .placeSearchFailed
        }

        guard let url = navigationURL(to: resolvedStop, mode: mode) else { return .placeNotFound }
        return await UIApplication.shared.open(url) ? .opened : .openFailed
    }

    private static func resolvedStop(for stop: AmapStop) async -> AmapStopResolution {

        let placeName = stop.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = stop.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationName = placeName.isEmpty ? address : placeName
        guard !destinationName.isEmpty else { return .notFound }

        var seen = Set<String>()
        let queries = [[address, placeName].filter { !$0.isEmpty }.joined(separator: " "), placeName, address]
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        var failed = false
        for query in queries {
            do {
                let places = try await searchAmap(query)
                if let place = bestMatch(for: destinationName, in: places) ?? places.first {
                    return .resolved(AmapStop(name: destinationName, address: place.address,
                                              latitude: place.latitude, longitude: place.longitude))
                }
            } catch { failed = true }
        }
        return failed ? .searchFailed : .notFound
    }

    private static var nextLookup = Date.distantPast
    private static var placeCache: [String: [ResolvedPlace]] = [:]
    private static func searchAmap(_ query: String) async throws -> [ResolvedPlace] {
        if let cached = placeCache[query] { return cached }
        let key = Bundle.main.object(forInfoDictionaryKey: "AmapWebKey") as? String ?? ""
        guard !key.isEmpty, !key.hasPrefix("$(") else { throw CloudSyncError.message("未配置高德地点搜索服务") }
        let delay = nextLookup.timeIntervalSinceNow
        nextLookup = max(Date(), nextLookup).addingTimeInterval(1.1)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        var url = URLComponents(string: "https://restapi.amap.com/v3/place/text")!
        url.queryItems = [.init(name: "key", value: key), .init(name: "keywords", value: query),
                          .init(name: "offset", value: "10"), .init(name: "page", value: "1"),
                          .init(name: "extensions", value: "base"), .init(name: "output", value: "JSON")]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["status"] as? String == "1" else { throw URLError(.badServerResponse) }
            let places = (object["pois"] as? [[String: Any]] ?? []).compactMap { poi -> ResolvedPlace? in
                let coordinate = (poi["location"] as? String ?? "").split(separator: ",")
                guard coordinate.count == 2, let lon = Double(coordinate[0]), let lat = Double(coordinate[1]),
                      (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
                return ResolvedPlace(name: poi["name"] as? String ?? query,
                                     address: poi["address"] as? String ?? "", latitude: lat, longitude: lon)
            }
            if !places.isEmpty { placeCache[query] = places }
            return places
        } catch { throw CloudSyncError.message("高德地点查询失败，请检查网络和服务配置") }
    }

    private static func normalizedPlaceName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private static func stopDisplayName(_ stop: AmapStop) -> String {
        let name = stop.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? stop.address.trimmingCharacters(in: .whitespacesAndNewlines) : name
    }

    private static func routeType(for mode: TransportMode) -> String {
        switch mode {
        case .bus: "1"
        case .walk: "2"
        case .ride: "3"
        default: "0"
        }
    }
}

private enum AmapStopResolution {
    case resolved(AmapStop)
    case notFound
    case searchFailed
}

enum PlaceDiscoveryPlatform {
    case xiaohongshu
    case douyin

    var displayName: String {
        switch self {
        case .xiaohongshu: "小红书"
        case .douyin: "抖音"
        }
    }
}

@MainActor
enum PlaceDiscoveryService {
    static func open(_ platform: PlaceDiscoveryPlatform, name: String, address: String) async -> Bool {
        let keyword = [name, address]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if let nativeURL = nativeSearchURL(for: platform, keyword: keyword),
           await UIApplication.shared.open(nativeURL) {
            return true
        }

        guard let webURL = webSearchURL(for: platform, keyword: keyword) else { return false }
        return await UIApplication.shared.open(webURL)
    }

    static func nativeSearchURL(for platform: PlaceDiscoveryPlatform, keyword: String) -> URL? {
        var components = URLComponents()
        switch platform {
        case .xiaohongshu:
            components.scheme = "xhsdiscover"
            components.host = "search"
            components.path = "/result"
        case .douyin:
            components.scheme = "snssdk1128"
            components.host = "search"
        }
        components.queryItems = [URLQueryItem(name: "keyword", value: keyword)]
        return components.url
    }

    static func webSearchURL(for platform: PlaceDiscoveryPlatform, keyword: String) -> URL? {
        var components: URLComponents?
        switch platform {
        case .xiaohongshu:
            components = URLComponents(string: "https://www.xiaohongshu.com/search_result")
            components?.queryItems = [URLQueryItem(name: "keyword", value: keyword)]
        case .douyin:
            components = URLComponents(string: "https://www.douyin.com")
            components?.path = "/search/\(keyword)"
        }
        return components?.url
    }
}
