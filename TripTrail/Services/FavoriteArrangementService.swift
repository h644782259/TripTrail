import Foundation

enum FavoriteArrangementService {
    static func filtered(
        _ favorites: [ItineraryItem],
        searchText: String,
        category: PlaceCategory?
    ) -> [ItineraryItem] {
        let keyword = normalized(searchText)
        return favorites
            .filter(\.isFavorite)
            .filter { category == nil || $0.category == category }
            .filter { favorite in
                guard !keyword.isEmpty else { return true }
                return [
                    favorite.title,
                    favorite.note,
                    city(for: favorite),
                    favorite.locationSummary,
                    favorite.placeAddress,
                    favorite.originAddress,
                    favorite.destinationAddress,
                    favorite.reservationInfo,
                    favorite.category.rawValue
                ]
                .map(normalized)
                .contains { $0.contains(keyword) }
            }
            .sorted { lhs, rhs in
                if lhs.favoriteCreatedAt != rhs.favoriteCreatedAt {
                    return lhs.favoriteCreatedAt > rhs.favoriteCreatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    @discardableResult
    static func importFavorites(
        _ favorites: [ItineraryItem],
        into day: TripDay,
        calendar: Calendar = .current
    ) -> [ItineraryItem] {
        var nextStart = day.suggestedStartTime(calendar: calendar)
        let initialSortOrder = (day.items.map(\.sortOrder).max() ?? -1) + 1

        let existing = Set(day.items.compactMap(\.sourceFavoriteID))
        return favorites.filter { !existing.contains($0.id) }.enumerated().map { index, favorite in
            let duration = max(favorite.playDurationMinutes, 60)
            let end = calendar.date(byAdding: .minute, value: duration, to: nextStart)
                ?? nextStart.addingTimeInterval(TimeInterval(duration * 60))
            let item = ItineraryItem(
                title: favorite.title,
                category: favorite.category,
                startTime: nextStart,
                endTime: end,
                sortOrder: initialSortOrder + index
            )
            item.transport = favorite.transport
            item.attractionTypeRaw = favorite.attractionTypeRaw
            item.address = favorite.address
            item.note = favorite.note
            item.locationModeRaw = favorite.locationModeRaw
            item.placeName = favorite.placeName
            item.placeAddress = favorite.placeAddress
            item.originName = favorite.originName
            item.originAddress = favorite.originAddress
            item.destinationName = favorite.destinationName
            item.destinationAddress = favorite.destinationAddress
            item.playDurationMinutes = duration
            item.reservationInfo = favorite.reservationInfo
            item.favoriteCity = favorite.favoriteCity
            item.vouchers = favorite.vouchers
            item.isTimePending = favorite.isTimePending
            item.cost = favorite.cost
            item.executionStatus = .notStarted
            item.isAutomaticCompletionOverridden = false
            item.isFavorite = false
            item.sourceFavoriteID = favorite.id
            item.day = day

            for (mediaIndex, source) in favorite.media.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
                let copy = MediaReference(
                    localIdentifier: source.localIdentifier,
                    kind: source.kind,
                    sortOrder: mediaIndex
                )
                copy.caption = source.caption
                copy.itineraryItem = item
                item.media.append(copy)
            }

            day.items.append(item)
            if !item.isTimePending { nextStart = end }
            return item
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
    }
}


extension FavoriteArrangementService {
    static func city(for favorite: ItineraryItem) -> String {
        let explicit = favorite.favoriteCity.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return normalizedCity(explicit) }
        let addresses = favorite.locationTargets.map(\.address)
        for raw in addresses {
            let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            for city in ["北京", "上海", "天津", "重庆", "香港", "澳门"] where address.hasPrefix(city) { return city }
            for pattern in ["(?:省|自治区)([\\p{Han}]{2,8}?)市", "^([\\p{Han}]{2,8}?)市"] {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)),
                      let range = Range(match.range(at: 1), in: address) else { continue }
                return String(address[range])
            }
        }
        return "未设置城市"
    }

    private static func normalizedCity(_ city: String) -> String {
        city.hasSuffix("市") ? String(city.dropLast()) : city
    }
}
