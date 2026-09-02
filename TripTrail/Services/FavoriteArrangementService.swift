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
                    favorite.locationSummary,
                    favorite.placeAddress,
                    favorite.originAddress,
                    favorite.destinationAddress,
                    favorite.distanceText,
                    favorite.reservationInfo,
                    favorite.category.rawValue,
                    favorite.transport.rawValue
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

        return favorites.enumerated().map { index, favorite in
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
            item.address = favorite.address
            item.note = favorite.note
            item.locationModeRaw = favorite.locationModeRaw
            item.placeName = favorite.placeName
            item.placeAddress = favorite.placeAddress
            item.originName = favorite.originName
            item.originAddress = favorite.originAddress
            item.destinationName = favorite.destinationName
            item.destinationAddress = favorite.destinationAddress
            item.transportRaw = favorite.transportRaw
            item.distanceText = favorite.distanceText
            item.playDurationMinutes = duration
            item.reservationInfo = favorite.reservationInfo
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
            nextStart = end
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
