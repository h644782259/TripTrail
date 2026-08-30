import Foundation
import UIKit
import Vision

struct ItineraryScreenshotDraft: Identifiable {
    let id = UUID()
    var title: String
    var category: PlaceCategory
    var startTime: Date
    var endTime: Date
    var address: String
    var transport: TransportMode
    var distanceText: String
    var travelDurationMinutes: Int
    var reservationInfo: String
    var cost: Double
    var note: String
    var titleCandidates: [String]
    var addressCandidates: [String]
    var startTimeCandidates: [Date]
    var endTimeCandidates: [Date]
    var distanceTextCandidates: [String]
    var costCandidates: [Double]
    let orderNumber: String
    let rawText: String
    let sourceAssetIdentifiers: [String]
}

struct ItineraryJourneyDraft: Identifiable {
    let id = UUID()
    var days: [ItineraryJourneyDayDraft]
    let rawText: String
    let sourceAssetIdentifiers: [String]
}

struct ItineraryJourneyDayDraft: Identifiable {
    let id = UUID()
    var sourceDayNumber: Int
    var routeTitle: String
    var note: String
    var items: [ItineraryJourneyItemDraft]
}

struct ItineraryJourneyItemDraft: Identifiable {
    let id = UUID()
    var isIncluded = true
    var title: String
    var category: PlaceCategory
    var startTime: Date
    var endTime: Date
    var address: String
    var transport: TransportMode
    var distanceText: String
    var reservationInfo: String
    var cost: Double
    var note: String
}

enum ScreenshotItineraryImportError: LocalizedError {
    case unreadableImage
    case noText

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "无法读取这张图片，请尝试重新截图或从系统相簿重新选择。"
        case .noText: "没有识别到可录入的内容，请选择文字更清晰的截图，或输入更完整的文本。"
        }
    }
}

enum ScreenshotItineraryImportService {
    static func parseInputText(
        _ text: String,
        referenceDate: Date
    ) throws -> ItineraryScreenshotDraft {
        let lines = text
            .components(separatedBy: CharacterSet(charactersIn: "\n\r，,;；。"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw ScreenshotItineraryImportError.noText }
        return parseRecognizedLines(lines, referenceDate: referenceDate)
    }

    static func parseJourneyInputText(
        _ text: String,
        referenceDate: Date
    ) throws -> ItineraryJourneyDraft {
        try parseJourneyText(
            text,
            referenceDate: referenceDate,
            sourceAssetIdentifiers: []
        )
    }

    static func recognizeJourney(
        imageDatas: [Data],
        referenceDate: Date,
        sourceAssetIdentifiers: [String]
    ) async throws -> ItineraryJourneyDraft {
        let cgImages = imageDatas.compactMap { UIImage(data: $0)?.cgImage }
        guard !cgImages.isEmpty else {
            throw ScreenshotItineraryImportError.unreadableImage
        }

        let lineGroups = try await Task.detached(priority: .userInitiated) {
            var groups: [[String]] = []
            for cgImage in cgImages {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                request.usesLanguageCorrection = true
                request.minimumTextHeight = 0.012
                try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
                let observations = (request.results ?? []).sorted { lhs, rhs in
                    if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.012 {
                        return lhs.boundingBox.midY > rhs.boundingBox.midY
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                var lines: [String] = []
                for value in observations.compactMap({ $0.topCandidates(1).first?.string }) {
                    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !normalized.isEmpty { lines.append(normalized) }
                }
                groups.append(lines)
            }
            return groups
        }.value

        let recognizedText = lineGroups
            .filter { !$0.isEmpty }
            .map { $0.joined(separator: "\n") }
            .joined(separator: "\n")
        guard !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScreenshotItineraryImportError.noText
        }
        return try parseJourneyText(
            recognizedText,
            referenceDate: referenceDate,
            sourceAssetIdentifiers: sourceAssetIdentifiers
        )
    }

    static func parseJourneyText(
        _ text: String,
        referenceDate: Date,
        sourceAssetIdentifiers: [String]
    ) throws -> ItineraryJourneyDraft {
        let normalizedText = normalizedJourneyText(text)
        guard !normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScreenshotItineraryImportError.noText
        }

        let daySections = journeyDaySections(in: normalizedText)
        if daySections.isEmpty {
            let single = try parseInputText(normalizedText, referenceDate: referenceDate)
            return ItineraryJourneyDraft(
                days: [
                    ItineraryJourneyDayDraft(
                        sourceDayNumber: 1,
                        routeTitle: single.title,
                        note: single.note,
                        items: [journeyItem(from: single)]
                    )
                ],
                rawText: normalizedText,
                sourceAssetIdentifiers: sourceAssetIdentifiers
            )
        }

        let calendar = Calendar.current
        let days = daySections.enumerated().map { index, section in
            let dayDate = calendar.date(byAdding: .day, value: index, to: referenceDate) ?? referenceDate
            return journeyDayDraft(
                sourceDayNumber: section.number,
                header: section.header,
                body: section.body,
                dayDate: dayDate
            )
        }
        return ItineraryJourneyDraft(
            days: days,
            rawText: normalizedText,
            sourceAssetIdentifiers: sourceAssetIdentifiers
        )
    }

    static func recognize(
        imageDatas: [Data],
        referenceDate: Date,
        sourceAssetIdentifiers: [String]
    ) async throws -> ItineraryScreenshotDraft {
        let cgImages = imageDatas.compactMap { UIImage(data: $0)?.cgImage }
        guard !cgImages.isEmpty else {
            throw ScreenshotItineraryImportError.unreadableImage
        }

        let lineGroups = try await Task.detached(priority: .userInitiated) {
            var groups: [[String]] = []
            for cgImage in cgImages {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                request.usesLanguageCorrection = true
                request.minimumTextHeight = 0.012
                try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
                let observations = (request.results ?? []).sorted { lhs, rhs in
                    if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.012 {
                        return lhs.boundingBox.midY > rhs.boundingBox.midY
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                var lines: [String] = []
                var seen = Set<String>()
                for value in observations.compactMap({ $0.topCandidates(1).first?.string }) {
                    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !normalized.isEmpty && seen.insert(normalized).inserted {
                        lines.append(normalized)
                    }
                }
                groups.append(lines)
            }
            return groups
        }.value

        let lines = uniqueStrings(lineGroups.flatMap { $0 })
        guard !lines.isEmpty else { throw ScreenshotItineraryImportError.noText }
        var mergedDraft = parseRecognizedLines(
            lines,
            referenceDate: referenceDate,
            sourceAssetIdentifiers: sourceAssetIdentifiers
        )
        let individualDrafts = lineGroups
            .filter { !$0.isEmpty }
            .map { parseRecognizedLines($0, referenceDate: referenceDate) }
        mergedDraft.titleCandidates = uniqueStrings(
            [mergedDraft.title] + individualDrafts.map(\.title).filter { $0 != "待补充的安排" }
        )
        mergedDraft.addressCandidates = uniqueStrings(
            [mergedDraft.address] + individualDrafts.map(\.address).filter { !$0.isEmpty }
        )
        mergedDraft.distanceTextCandidates = uniqueStrings(
            [mergedDraft.distanceText] + individualDrafts.map(\.distanceText).filter { !$0.isEmpty }
        )
        mergedDraft.costCandidates = uniqueDoubles(
            [mergedDraft.cost] + individualDrafts.map(\.cost).filter { $0 > 0 }
        )
        let timedDrafts = individualDrafts.filter {
            !$0.distanceText.isEmpty || ($0.rawText.contains("月") && $0.rawText.contains("日")) ||
            $0.rawText.contains("入住") || $0.rawText.contains("离店")
        }
        mergedDraft.startTimeCandidates = uniqueDates([mergedDraft.startTime] + timedDrafts.map(\.startTime))
        mergedDraft.endTimeCandidates = uniqueDates([mergedDraft.endTime] + timedDrafts.map(\.endTime))
        return mergedDraft
    }

    static func parseRecognizedLines(
        _ lines: [String],
        referenceDate: Date,
        sourceAssetIdentifiers: [String] = []
    ) -> ItineraryScreenshotDraft {
        let cleanedLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let rawText = cleanedLines.joined(separator: "\n")
        let category = inferCategory(from: rawText)
        let navigationDestination = category == .transport ? inferNavigationDestination(from: cleanedLines) : nil
        let explicitTitle = inferExplicitValue(
            from: cleanedLines,
            labels: ["地点", "事项", "名称", "景点", "餐厅", "酒店", "住宿", "目的地"]
        )
        let naturalPlace = explicitJourneyPlaces(in: rawText).first?.name
        let title = navigationDestination
            ?? explicitTitle
            ?? naturalPlace
            ?? inferTitle(from: cleanedLines, category: category)
        let address = navigationDestination ?? inferAddress(from: cleanedLines)
        let transport = inferTransport(from: rawText)
        let travelDurationMinutes = Int(firstCapture(in: rawText, pattern: "([0-9]{1,3})\\s*分钟") ?? "") ?? 0
        let routeDistance = firstCapture(in: rawText, pattern: "([0-9]+(?:\\.[0-9]+)?)\\s*公里") ?? ""
        let orderNumber = firstCapture(
            in: rawText,
            pattern: "(?:订单号|订单编号|预订号|预约号)\\s*[:：]?\\s*([A-Za-z0-9-]{6,})"
        ) ?? ""
        let costText = firstCapture(in: rawText, pattern: "[¥￥]\\s*([0-9]+(?:\\.[0-9]{1,2})?)")
            ?? firstCapture(
                in: rawText,
                pattern: "(?:预计花费|费用|花费|价格|票价|门票)\\s*[:：]?\\s*[¥￥]?\\s*([0-9]+(?:\\.[0-9]{1,2})?)"
            )
        let cost = Double(costText ?? "") ?? 0
        let dates = inferDates(
            from: rawText,
            referenceDate: referenceDate,
            category: category,
            travelDurationMinutes: travelDurationMinutes
        )

        var reservationParts: [String] = []
        if !orderNumber.isEmpty { reservationParts.append("订单号：\(orderNumber)") }
        if let room = cleanedLines.first(where: {
            $0.contains("房") && ($0.contains("床") || $0.contains("间")) && !$0.contains("酒店") && !$0.contains("续住")
        }) {
            reservationParts.append("房型：\(room)")
        }
        if let cancellation = cleanedLines.first(where: { $0.contains("取消") && $0.count > 5 }) {
            reservationParts.append("取消规则：\(cancellation)")
        }
        if let reservation = cleanedLines.first(where: {
            ["预约", "门票", "营业时间", "开放时间"].contains(where: $0.hasPrefix)
        }), !reservationParts.contains(reservation) {
            reservationParts.append(reservation)
        }

        let explicitNote = inferExplicitValue(
            from: cleanedLines,
            labels: ["备注", "说明", "提示", "行程说明"]
        )

        return ItineraryScreenshotDraft(
            title: title.isEmpty ? "待补充的安排" : title,
            category: category,
            startTime: dates.start,
            endTime: dates.end,
            address: address,
            transport: transport,
            distanceText: [
                routeDistance.isEmpty ? "" : "\(routeDistance) 公里",
                travelDurationMinutes > 0 ? "\(travelDurationMinutes) 分钟" : ""
            ].filter { !$0.isEmpty }.joined(separator: " · "),
            travelDurationMinutes: travelDurationMinutes,
            reservationInfo: reservationParts.joined(separator: "\n"),
            cost: cost,
            note: explicitNote ?? inferRouteNote(from: cleanedLines),
            titleCandidates: title.isEmpty ? [] : [title],
            addressCandidates: address.isEmpty ? [] : [address],
            startTimeCandidates: [dates.start],
            endTimeCandidates: [dates.end],
            distanceTextCandidates: routeDistance.isEmpty && travelDurationMinutes == 0 ? [] : [[
                routeDistance.isEmpty ? "" : "\(routeDistance) 公里",
                travelDurationMinutes > 0 ? "\(travelDurationMinutes) 分钟" : ""
            ].filter { !$0.isEmpty }.joined(separator: " · ")],
            costCandidates: cost > 0 ? [cost] : [],
            orderNumber: orderNumber,
            rawText: rawText,
            sourceAssetIdentifiers: sourceAssetIdentifiers
        )
    }

    private static func normalizedJourneyText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
    }

    private static func journeyDaySections(
        in text: String
    ) -> [(number: Int, header: String, body: String)] {
        let pattern = #"(?im)^\s*[-•·]?\s*(?:Day\s*([0-9]{1,2})|第\s*([0-9]{1,2})\s*天)\s*[:：]?\s*([^\n]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fullRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: fullRange)
        guard !matches.isEmpty else { return [] }

        return matches.enumerated().compactMap { index, match in
            let numberText = [match.range(at: 1), match.range(at: 2)].compactMap { range -> String? in
                guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
                return String(text[swiftRange])
            }.first
            guard let numberText, let number = Int(numberText) else { return nil }
            let header: String
            if match.range(at: 3).location != NSNotFound,
               let range = Range(match.range(at: 3), in: text) {
                header = cleanJourneyText(String(text[range]))
            } else {
                header = ""
            }

            let bodyStart = match.range.location + match.range.length
            let bodyEnd = index + 1 < matches.count ? matches[index + 1].range.location : fullRange.length
            guard bodyStart <= bodyEnd,
                  let bodyRange = Range(NSRange(location: bodyStart, length: bodyEnd - bodyStart), in: text) else {
                return nil
            }
            let body = truncateSupplementaryJourneyContent(String(text[bodyRange]))
            return (number, header, body)
        }
    }

    private static func truncateSupplementaryJourneyContent(_ text: String) -> String {
        let stopWords = ["必打卡", "精华景点", "自驾路况", "车辆建议", "穿搭", "必备物品", "预算参考", "避坑指南"]
        let lines = text.components(separatedBy: .newlines)
        let kept = lines.prefix { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return true }
            if ["✨", "🚗", "🧥", "💰", "📌"].contains(where: value.hasPrefix) { return false }
            return !stopWords.contains(where: value.contains)
        }
        return cleanJourneyText(kept.joined(separator: "\n"))
    }

    private static func journeyDayDraft(
        sourceDayNumber: Int,
        header: String,
        body: String,
        dayDate: Date
    ) -> ItineraryJourneyDayDraft {
        let stay = firstCapture(
            in: header,
            pattern: #"[（(](?:住|住宿)\s*([^）)]+)[）)]"#
        ).map(cleanJourneyPlace) ?? ""
        let routeTitle = cleanJourneyText(
            header.replacingOccurrences(
                of: #"[（(](?:住|住宿)[^）)]+[）)]"#,
                with: "",
                options: .regularExpression
            )
        )
        let endpoints = routeTitle
            .replacingOccurrences(of: "➡️", with: "→")
            .replacingOccurrences(of: "->", with: "→")
            .components(separatedBy: "→")
            .map(cleanJourneyPlace)
            .filter { !$0.isEmpty }

        var items: [ItineraryJourneyItemDraft] = []
        var cursorMinutes = 9 * 60
        if endpoints.count >= 2 {
            let metrics = journeyRouteMetrics(in: body)
            let start = journeyDate(dayDate, minutes: cursorMinutes)
            let end = Calendar.current.date(
                byAdding: .minute,
                value: max(60, metrics.durationMinutes),
                to: start
            ) ?? start
            items.append(
                ItineraryJourneyItemDraft(
                    title: routeTitle,
                    category: .transport,
                    startTime: start,
                    endTime: end,
                    address: endpoints.last ?? "",
                    transport: .car,
                    distanceText: metrics.text,
                    reservationInfo: "",
                    cost: 0,
                    note: ""
                )
            )
            cursorMinutes += max(60, metrics.durationMinutes) + 30
        }

        let excludedPlaces = Set(endpoints + [stay])
        for place in explicitJourneyPlaces(in: body) where !excludedPlaces.contains(place.name) {
            let start = journeyDate(dayDate, minutes: min(cursorMinutes, 20 * 60))
            let end = Calendar.current.date(byAdding: .minute, value: 90, to: start) ?? start
            items.append(
                ItineraryJourneyItemDraft(
                    title: place.name,
                    category: inferJourneyPlaceCategory(place.name),
                    startTime: start,
                    endTime: end,
                    address: place.name,
                    transport: .car,
                    distanceText: "",
                    reservationInfo: "",
                    cost: 0,
                    note: place.note
                )
            )
            cursorMinutes += 120
        }

        if !stay.isEmpty {
            let start = journeyDate(dayDate, minutes: 19 * 60)
            let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: dayDate) ?? dayDate
            let end = journeyDate(nextDay, minutes: 8 * 60)
            items.append(
                ItineraryJourneyItemDraft(
                    title: stay.contains("酒店") || stay.contains("民宿") || stay.contains("客栈") ? stay : "入住\(stay)",
                    category: .hotel,
                    startTime: start,
                    endTime: end,
                    address: stay,
                    transport: .car,
                    distanceText: "",
                    reservationInfo: "",
                    cost: 0,
                    note: "住宿：\(stay)"
                )
            )
        }

        if items.isEmpty {
            let fallback = parseRecognizedLines(
                [header, body].filter { !$0.isEmpty },
                referenceDate: dayDate
            )
            items = [journeyItem(from: fallback)]
        }

        return ItineraryJourneyDayDraft(
            sourceDayNumber: sourceDayNumber,
            routeTitle: routeTitle,
            note: body,
            items: items
        )
    }

    private static func journeyItem(from draft: ItineraryScreenshotDraft) -> ItineraryJourneyItemDraft {
        ItineraryJourneyItemDraft(
            title: draft.title,
            category: draft.category,
            startTime: draft.startTime,
            endTime: draft.endTime,
            address: draft.address,
            transport: draft.transport,
            distanceText: draft.distanceText,
            reservationInfo: draft.reservationInfo,
            cost: draft.cost,
            note: draft.note
        )
    }

    private static func explicitJourneyPlaces(in text: String) -> [(name: String, note: String)] {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: "，。；！\n"))
        let pattern = #"(?:依次打卡|顺路打卡|深度游玩|游玩|打卡|翻越|前往|可以去|去|经由|经)\s*([^，。；！\n]{2,50})"#
        var result: [(String, String)] = []
        var seen = Set<String>()

        for sentence in sentences {
            guard let captured = firstCapture(in: sentence, pattern: pattern) else { continue }
            let separated = captured
                .replacingOccurrences(of: "、", with: "|")
                .replacingOccurrences(of: "/", with: "|")
                .replacingOccurrences(of: "或", with: "|")
                .replacingOccurrences(of: "和", with: "|")
            for rawValue in separated.components(separatedBy: "|") {
                var value = rawValue
                for delimiter in ["的", "看", "观赏", "感受", "抵达", "到达", "然后", "之后", "全程", "非常"] {
                    if let range = value.range(of: delimiter) { value = String(value[..<range.lowerBound]) }
                }
                let name = cleanJourneyPlace(value)
                guard isConfidentJourneyPlace(name), seen.insert(name).inserted else { continue }
                result.append((name, String(cleanJourneyText(sentence).prefix(140))))
            }
        }
        return result
    }

    private static func isConfidentJourneyPlace(_ value: String) -> Bool {
        guard value.count >= 2, value.count <= 20 else { return false }
        let ignored = ["自然醒", "日落金山", "观光车", "绝美云海", "高海拔", "低海拔", "高速", "土路"]
        guard !ignored.contains(where: value.contains) else { return false }
        let suffixes = ["山", "沟", "公园", "草原", "桥", "海子", "观景台", "古镇", "景区", "博物馆", "寺", "湖", "镇", "县", "市", "机场", "车站", "寨"]
        return suffixes.contains(where: value.hasSuffix) || value.count <= 8
    }

    private static func inferJourneyPlaceCategory(_ value: String) -> PlaceCategory {
        if ["酒店", "民宿", "客栈", "镇", "县城"].contains(where: value.contains) { return .hotel }
        if ["机场", "车站"].contains(where: value.contains) { return .transport }
        if ["餐厅", "餐馆", "饭店"].contains(where: value.contains) { return .restaurant }
        return .attraction
    }

    private static func journeyRouteMetrics(in text: String) -> (text: String, durationMinutes: Int) {
        let distance = firstCapture(in: text, pattern: #"(?:约)?([0-9]+(?:\.[0-9]+)?)\s*公里"#) ?? ""
        let hourRange = captures(in: text, pattern: #"([0-9]+(?:\.[0-9]+)?)\s*[-–—至]\s*([0-9]+(?:\.[0-9]+)?)\s*小时"#).first
        let singleHour = firstCapture(in: text, pattern: #"([0-9]+(?:\.[0-9]+)?)\s*小时"#)
        let minuteValue = firstCapture(in: text, pattern: #"([0-9]{1,3})\s*分钟"#)

        var durationText = ""
        var durationMinutes = 0
        if let hourRange, hourRange.count == 2,
           let lower = Double(hourRange[0]), let upper = Double(hourRange[1]) {
            durationText = "\(hourRange[0])–\(hourRange[1]) 小时"
            durationMinutes = Int(max(lower, upper) * 60)
        } else if let singleHour, let hours = Double(singleHour) {
            durationText = "\(singleHour) 小时"
            durationMinutes = Int(hours * 60)
        } else if let minuteValue, let minutes = Int(minuteValue) {
            durationText = "\(minuteValue) 分钟"
            durationMinutes = minutes
        }
        let text = [distance.isEmpty ? "" : "\(distance) 公里", durationText]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return (text, durationMinutes)
    }

    private static func journeyDate(_ day: Date, minutes: Int) -> Date {
        Calendar.current.date(
            bySettingHour: min(23, max(0, minutes / 60)),
            minute: min(59, max(0, minutes % 60)),
            second: 0,
            of: day
        ) ?? day
    }

    private static func cleanJourneyPlace(_ value: String) -> String {
        cleanJourneyText(
            value.replacingOccurrences(
                of: #"[（(].*$"#,
                with: "",
                options: .regularExpression
            )
        )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-—→>：:（）() ·"))
    }

    private static func cleanJourneyText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func inferCategory(from text: String) -> PlaceCategory {
        if text.contains("酒店") || text.contains("入住") || text.contains("离店") || text.contains("房型") { return .hotel }
        if text.contains("航班") || text.contains("航空") || text.contains("登机") || text.contains("车次") || text.contains("高铁") ||
            (text.contains("公里") && text.contains("分钟")) || text.contains("开始导航") { return .transport }
        if text.contains("餐厅") || text.contains("餐馆") || text.contains("用餐") { return .restaurant }
        if text.contains("景区") || text.contains("门票") || text.contains("入园") { return .attraction }
        return .special
    }

    private static func inferTitle(from lines: [String], category: PlaceCategory) -> String {
        if category == .hotel {
            for line in lines {
                if let explicitHotel = firstCapture(
                    in: line,
                    pattern: "(?:入住|预订(?:酒店)?|酒店名称)\\s*[:：]?\\s*([^，。；]{2,60}?(?:酒店|民宿|客栈)(?:（[^）]{1,30}）)?)$"
                ) {
                    return explicitHotel
                }
            }
        }

        let keywords: [String]
        switch category {
        case .hotel: keywords = ["酒店", "民宿", "客栈"]
        case .transport: keywords = ["航班", "航空", "车次", "高铁", "火车"]
        case .restaurant: keywords = ["餐厅", "餐馆", "饭店"]
        case .attraction: keywords = ["景区", "公园", "博物馆", "门票"]
        default: keywords = []
        }
        let ignored = ["联系客服", "联系酒店", "酒店设施", "查看房型", "预订成功"]
        let candidate = lines
            .filter { line in keywords.contains(where: line.contains) && !ignored.contains(where: line.contains) }
            .max(by: { $0.count < $1.count })?
            .trimmingCharacters(in: CharacterSet(charactersIn: " >〉")) ?? ""
        return removingFieldLabel(from: candidate, labels: ["酒店名称", "酒店", "住宿", "景点", "餐厅", "地点", "名称"])
    }

    private static func inferAddress(from lines: [String]) -> String {
        if let explicitAddress = inferExplicitValue(
            from: lines,
            labels: ["详细地址", "地址", "位置"]
        ) {
            return explicitAddress
        }
        let candidate = lines.first { line in
            let hasRoad = ["路", "街", "巷", "道", "号", "弄"].contains(where: line.contains)
            let hasRegion = ["省", "市", "区", "县", "镇"].contains(where: line.contains)
            return hasRoad && hasRegion && !line.contains("取消")
        } ?? ""
        return removingFieldLabel(from: candidate, labels: ["详细地址", "地址", "位置"])
    }

    private static func inferNavigationDestination(from lines: [String]) -> String? {
        if let originIndex = lines.firstIndex(where: { $0.contains("我的位置") }), originIndex + 1 < lines.count {
            let next = cleanNavigationPlace(lines[originIndex + 1])
            if !next.isEmpty && !isNavigationControlText(next) { return next }
        }
        return lines
            .map(cleanNavigationPlace)
            .first { line in
                !isNavigationControlText(line) &&
                ["站", "机场", "酒店", "景区", "公园", "商场", "中心"].contains(where: line.contains)
            }
    }

    private static func cleanNavigationPlace(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "修改", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " •·<>〉"))
        return removingFieldLabel(from: cleaned, labels: ["导航到", "到达地点", "目的地", "终点"])
    }

    private static func isNavigationControlText(_ value: String) -> Bool {
        ["公共交通", "打车", "顺风", "开始导航", "发到车机", "偏好", "我的位置"].contains { value.contains($0) }
    }

    private static func inferTransport(from text: String) -> TransportMode {
        if firstCapture(in: text, pattern: "([京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤青藏川宁琼][A-Z][A-Z0-9*]{2,})") != nil || text.contains("开始导航") {
            return .car
        }
        if text.contains("步行") { return .walk }
        if text.contains("骑行") { return .ride }
        if text.contains("公交") || text.contains("公共交通") { return .bus }
        if text.contains("火车") || text.contains("高铁") || text.contains("车次") { return .train }
        if text.contains("航班") || text.contains("航空") { return .flight }
        return .car
    }

    private static func inferRouteNote(from lines: [String]) -> String {
        lines.first {
            ["拥堵", "红绿灯", "等灯", "宽敞", "避开", "收费", "高速"].contains(where: $0.contains)
        } ?? ""
    }

    private static func inferDates(
        from text: String,
        referenceDate: Date,
        category: PlaceCategory,
        travelDurationMinutes: Int
    ) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let referenceYear = calendar.component(.year, from: referenceDate)
        let matches = captures(
            in: text,
            pattern: "(?:(\\d{4})年)?(\\d{1,2})月(\\d{1,2})日"
        )
        var uniqueDates: [Date] = []
        for groups in matches {
            guard groups.count == 3, let month = Int(groups[1]), let day = Int(groups[2]) else { continue }
            let explicitYear = Int(groups[0])
            let years = explicitYear.map { [$0] } ?? [referenceYear - 1, referenceYear, referenceYear + 1]
            let candidates = years.compactMap {
                calendar.date(from: DateComponents(year: $0, month: month, day: day))
            }
            guard let date = candidates.min(by: {
                abs($0.timeIntervalSince(referenceDate)) < abs($1.timeIntervalSince(referenceDate))
            }) else { continue }
            if !uniqueDates.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
                uniqueDates.append(date)
            }
        }

        let defaultStartDay = uniqueDates.first ?? calendar.startOfDay(for: referenceDate)
        let defaultEndDay = uniqueDates.dropFirst().first
            ?? (category == .hotel ? calendar.date(byAdding: .day, value: 1, to: defaultStartDay)! : defaultStartDay)
        let timeRange = firstTimeRange(in: text)
        let checkInTime = time(before: "入住", in: text)
            ?? time(after: "入住", in: text)
            ?? timeRange?.start
            ?? firstTime(in: text)
            ?? (category == .hotel ? (14, 0) : (9, 0))
        let checkOutTime = time(before: "离店", in: text)
            ?? time(after: "离店", in: text)
            ?? timeRange?.end
            ?? (category == .hotel ? (12, 0) : (checkInTime.0 + 1, checkInTime.1))
        let start = calendar.date(bySettingHour: min(checkInTime.0, 23), minute: checkInTime.1, second: 0, of: defaultStartDay) ?? defaultStartDay
        if category == .transport && travelDurationMinutes > 0 {
            return (start, calendar.date(byAdding: .minute, value: travelDurationMinutes, to: start) ?? start)
        }
        var end = calendar.date(bySettingHour: min(checkOutTime.0, 23), minute: checkOutTime.1, second: 0, of: defaultEndDay) ?? defaultEndDay
        if end <= start { end = calendar.date(byAdding: .hour, value: category == .hotel ? 24 : 1, to: start) ?? start }
        return (start, end)
    }

    private static func time(before keyword: String, in text: String) -> (Int, Int)? {
        let escapedKeyword = NSRegularExpression.escapedPattern(for: keyword)
        let values = captures(
            in: text,
            pattern: "(\\d{1,2})[:：](\\d{2})[^\\d\\n]{0,8}\(escapedKeyword)"
        )
        guard let groups = values.last,
              groups.count == 2,
              let hour = Int(groups[0]),
              let minute = Int(groups[1]) else { return nil }
        return (hour, minute)
    }

    private static func time(after keyword: String, in text: String) -> (Int, Int)? {
        let escapedKeyword = NSRegularExpression.escapedPattern(for: keyword)
        guard let groups = captures(
            in: text,
            pattern: "\(escapedKeyword)[^\\n]{0,24}?(\\d{1,2})[:：](\\d{2})"
        ).first,
              groups.count == 2,
              let hour = Int(groups[0]),
              let minute = Int(groups[1]) else { return nil }
        return (hour, minute)
    }

    private static func firstTime(in text: String) -> (Int, Int)? {
        guard let groups = captures(in: text, pattern: "(\\d{1,2})[:：](\\d{2})").first,
              groups.count == 2,
              let hour = Int(groups[0]),
              let minute = Int(groups[1]) else { return nil }
        return (hour, minute)
    }

    private static func firstTimeRange(in text: String) -> (start: (Int, Int), end: (Int, Int))? {
        guard let groups = captures(
            in: text,
            pattern: "(\\d{1,2})[:：](\\d{2})\\s*[-–—~～至到]\\s*(\\d{1,2})[:：](\\d{2})"
        ).first,
              groups.count == 4,
              let startHour = Int(groups[0]),
              let startMinute = Int(groups[1]),
              let endHour = Int(groups[2]),
              let endMinute = Int(groups[3]),
              (0...23).contains(startHour),
              (0...59).contains(startMinute),
              (0...23).contains(endHour),
              (0...59).contains(endMinute) else { return nil }
        return ((startHour, startMinute), (endHour, endMinute))
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        captures(in: text, pattern: pattern).first?.first
    }

    private static func removingFieldLabel(from value: String, labels: [String]) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for label in labels where result.hasPrefix(label) {
            result.removeFirst(label.count)
            result = result.trimmingCharacters(in: CharacterSet(charactersIn: " :："))
            break
        }
        return result
    }

    private static func inferExplicitValue(from lines: [String], labels: [String]) -> String? {
        for line in lines {
            for label in labels where line.hasPrefix(label) {
                let suffix = line.dropFirst(label.count)
                guard let marker = suffix.first, marker == ":" || marker == "：" else { continue }
                let value = suffix.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private static func captures(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).map { index in
                let captureRange = match.range(at: index)
                guard captureRange.location != NSNotFound, let swiftRange = Range(captureRange, in: text) else { return "" }
                return String(text[swiftRange])
            }
        }
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func uniqueDoubles(_ values: [Double]) -> [Double] {
        var result: [Double] = []
        for value in values where value > 0 && !result.contains(where: { abs($0 - value) < 0.001 }) {
            result.append(value)
        }
        return result
    }

    private static func uniqueDates(_ values: [Date]) -> [Date] {
        var result: [Date] = []
        for value in values where !result.contains(where: { abs($0.timeIntervalSince(value)) < 60 }) {
            result.append(value)
        }
        return result
    }
}

enum JourneyImportApplyService {
    static func append(
        _ draft: ItineraryJourneyDraft,
        to trip: Trip,
        attachSourceImages: Bool,
        calendar: Calendar = .current
    ) -> [TripDay] {
        guard !draft.days.isEmpty else { return [] }

        let existingDays = trip.sortedDays
        let firstDate: Date
        if let lastDate = existingDays.last?.date {
            firstDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDate)) ?? lastDate
        } else {
            firstDate = calendar.startOfDay(for: trip.startDate)
        }
        let firstSortOrder = (existingDays.map(\.sortOrder).max() ?? -1) + 1

        var createdDays: [TripDay] = []
        var firstCreatedItem: ItineraryItem?
        for (dayOffset, dayDraft) in draft.days.enumerated() {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDate) ?? firstDate
            let day = TripDay(date: date, title: "", sortOrder: firstSortOrder + dayOffset, trip: trip)
            day.note = [dayDraft.routeTitle, dayDraft.note]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")

            for itemDraft in dayDraft.items where itemDraft.isIncluded {
                let cleanTitle = itemDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanTitle.isEmpty else { continue }
                let times = rebasedTimes(
                    start: itemDraft.startTime,
                    end: itemDraft.endTime,
                    onto: date,
                    calendar: calendar
                )
                let item = ItineraryItem(
                    title: cleanTitle,
                    category: itemDraft.category,
                    startTime: times.start,
                    endTime: times.end,
                    sortOrder: day.items.count
                )
                item.address = itemDraft.address.trimmingCharacters(in: .whitespacesAndNewlines)
                item.transport = itemDraft.transport
                item.distanceText = itemDraft.distanceText.trimmingCharacters(in: .whitespacesAndNewlines)
                item.reservationInfo = itemDraft.reservationInfo.trimmingCharacters(in: .whitespacesAndNewlines)
                item.cost = itemDraft.cost
                item.note = itemDraft.note.trimmingCharacters(in: .whitespacesAndNewlines)
                item.playDurationMinutes = max(0, Int(times.end.timeIntervalSince(times.start) / 60))
                item.day = day
                day.items.append(item)
                if firstCreatedItem == nil { firstCreatedItem = item }
            }

            trip.days.append(day)
            createdDays.append(day)
        }

        if attachSourceImages, let firstCreatedItem {
            for (index, identifier) in draft.sourceAssetIdentifiers.enumerated() {
                let reference = MediaReference(localIdentifier: identifier, kind: .image, sortOrder: index)
                reference.itineraryItem = firstCreatedItem
                firstCreatedItem.media.append(reference)
            }
        }

        if let lastDate = createdDays.last?.date {
            if existingDays.isEmpty {
                trip.startDate = firstDate
                trip.endDate = lastDate
            } else if lastDate > trip.endDate {
                trip.endDate = lastDate
            }
        }
        return createdDays
    }

    private static func rebasedTimes(
        start: Date,
        end: Date,
        onto day: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let startParts = calendar.dateComponents([.hour, .minute], from: start)
        let startValue = calendar.date(
            bySettingHour: startParts.hour ?? 9,
            minute: startParts.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
        let originalStartDay = calendar.startOfDay(for: start)
        let originalEndDay = calendar.startOfDay(for: end)
        let dayOffset = max(0, calendar.dateComponents([.day], from: originalStartDay, to: originalEndDay).day ?? 0)
        let rebasedEndDay = calendar.date(byAdding: .day, value: dayOffset, to: day) ?? day
        let endParts = calendar.dateComponents([.hour, .minute], from: end)
        var endValue = calendar.date(
            bySettingHour: endParts.hour ?? 10,
            minute: endParts.minute ?? 0,
            second: 0,
            of: rebasedEndDay
        ) ?? rebasedEndDay
        if endValue <= startValue {
            endValue = calendar.date(byAdding: .hour, value: 1, to: startValue) ?? startValue
        }
        return (startValue, endValue)
    }
}
