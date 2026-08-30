import Foundation
import MapKit

struct ResolvedPlace: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    init(name: String, address: String, wgs84Coordinate: CLLocationCoordinate2D) {
        let converted = CoordinateConverter.wgs84ToGCJ02(wgs84Coordinate)
        self.name = name
        self.address = address
        self.latitude = converted.latitude
        self.longitude = converted.longitude
        self.id = "\(name)-\(converted.latitude)-\(converted.longitude)"
    }
}

@MainActor
enum PlaceSearchService {
    static func search(_ query: String) async throws -> [ResolvedPlace] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = keyword
        request.resultTypes = [.pointOfInterest, .address]
        let response = try await MKLocalSearch(request: request).start()

        var seen = Set<String>()
        return response.mapItems.compactMap { item in
            let coordinate = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (name?.isEmpty == false ? name : item.placemark.name) ?? keyword
            let address = formattedAddress(item.placemark)
            let place = ResolvedPlace(name: resolvedName, address: address, wgs84Coordinate: coordinate)
            let key = "\(place.name)-\(String(format: "%.5f", place.latitude))-\(String(format: "%.5f", place.longitude))"
            guard seen.insert(key).inserted else { return nil }
            return place
        }
        .prefix(12)
        .map { $0 }
    }

    private static func formattedAddress(_ placemark: MKPlacemark) -> String {
        let parts = [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.subThoroughfare
        ]
        var unique: [String] = []
        for part in parts.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) where !part.isEmpty {
            if unique.last != part { unique.append(part) }
        }
        return unique.isEmpty ? (placemark.title ?? placemark.name ?? "") : unique.joined()
    }
}

enum CoordinateConverter {
    /// 高德在中国大陆使用 GCJ-02；MapKit 搜索结果按 WGS-84 语义转换后再交给高德 URI。
    static func wgs84ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        guard isInMainlandChina(latitude: latitude, longitude: longitude) else { return coordinate }

        let a = 6_378_245.0
        let eccentricitySquared = 0.00669342162296594323
        var latitudeDelta = transformLatitude(x: longitude - 105, y: latitude - 35)
        var longitudeDelta = transformLongitude(x: longitude - 105, y: latitude - 35)
        let radianLatitude = latitude / 180 * .pi
        var magic = sin(radianLatitude)
        magic = 1 - eccentricitySquared * magic * magic
        let squareRootMagic = sqrt(magic)
        latitudeDelta = latitudeDelta * 180 / ((a * (1 - eccentricitySquared)) / (magic * squareRootMagic) * .pi)
        longitudeDelta = longitudeDelta * 180 / (a / squareRootMagic * cos(radianLatitude) * .pi)
        return CLLocationCoordinate2D(latitude: latitude + latitudeDelta, longitude: longitude + longitudeDelta)
    }

    static func isInMainlandChina(latitude: Double, longitude: Double) -> Bool {
        longitude >= 72.004 && longitude <= 137.8347 && latitude >= 0.8293 && latitude <= 55.8271
    }

    private static func transformLatitude(x: Double, y: Double) -> Double {
        var value = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        value += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        value += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        value += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        return value
    }

    private static func transformLongitude(x: Double, y: Double) -> Double {
        var value = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        value += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        value += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        value += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3
        return value
    }
}
