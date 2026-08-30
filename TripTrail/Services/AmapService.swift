import Foundation
import UIKit

struct AmapStop: Equatable {
    let name: String
    let address: String
}

@MainActor
enum AmapService {
    private static let source = "TripTrail"

    static func openPlace(
        name: String,
        address: String,
        mode: TransportMode = .car
    ) async -> Bool {
        let stop = AmapStop(name: name, address: address)
        guard let url = navigationURL(to: stop, mode: mode) else { return false }
        return await openNative(url)
    }

    static func openNextPlace(_ stop: AmapStop, mode: TransportMode) async -> Bool {
        guard let url = navigationURL(to: stop, mode: mode) else { return false }
        return await openNative(url)
    }

    static func navigationURL(to stop: AmapStop, mode: TransportMode) -> URL? {
        let destinationName = [stop.name, stop.address]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !destinationName.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "iosamap"
        components.host = "path"
        let queryItems = [
            URLQueryItem(name: "sourceApplication", value: source),
            URLQueryItem(name: "dname", value: destinationName),
            URLQueryItem(name: "t", value: routeType(for: mode))
        ]
        components.queryItems = queryItems
        return components.url
    }

    private static func routeType(for mode: TransportMode) -> String {
        switch mode {
        case .bus: "1"
        case .walk: "2"
        case .ride: "3"
        default: "0"
        }
    }

    private static func openNative(_ url: URL) async -> Bool {
        guard UIApplication.shared.canOpenURL(url) else { return false }
        return await UIApplication.shared.open(url)
    }
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
