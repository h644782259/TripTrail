import Foundation
import MapKit

struct ResolvedPlace: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String

    init(name: String, address: String) {
        self.name = name
        self.address = address
        self.id = "\(name)-\(address)"
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
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (name?.isEmpty == false ? name : item.placemark.name) ?? keyword
            let address = formattedAddress(item.placemark)
            let place = ResolvedPlace(name: resolvedName, address: address)
            let key = place.id
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
