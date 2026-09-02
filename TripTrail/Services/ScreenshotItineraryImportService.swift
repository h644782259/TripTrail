import Foundation
import UIKit
import Vision

struct ItineraryScreenshotDraft: Identifiable {
    let id = UUID()
    var recognitionNotice: String? = nil
    var title: String
    var category: PlaceCategory
    var startTime: Date
    var endTime: Date
    var address: String
    var locationMode: ArrangementLocationMode = .single
    var placeName: String = ""
    var placeAddress: String = ""
    var originName: String = ""
    var originAddress: String = ""
    var destinationName: String = ""
    var destinationAddress: String = ""
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
    var recognitionNotice: String? = nil
    var days: [ItineraryJourneyDayDraft]
    let rawText: String
    let sourceAssetIdentifiers: [String]
}

protocol SmartRecognitionNotifyingDraft {
    var recognitionNotice: String? { get set }
}

extension ItineraryScreenshotDraft: SmartRecognitionNotifyingDraft {}
extension ItineraryJourneyDraft: SmartRecognitionNotifyingDraft {}

struct ItineraryJourneyDayDraft: Identifiable {
    let id = UUID()
    var sourceDayNumber: Int
    var date: Date? = nil
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
    var locationMode: ArrangementLocationMode = .single
    var placeName: String = ""
    var placeAddress: String = ""
    var originName: String = ""
    var originAddress: String = ""
    var destinationName: String = ""
    var destinationAddress: String = ""
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
                for observation in observations {
                    guard let value = observation.topCandidates(1).first?.string else { continue }
                    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if shouldIgnoreScreenStatusBarText(normalized, boundingBox: observation.boundingBox) {
                        continue
                    }
                    if !normalized.isEmpty { lines.append(normalized) }
                }
                groups.append(lines)
            }
            return groups
        }.value

        return try parseJourneyRecognizedLineGroups(
            lineGroups,
            referenceDate: referenceDate,
            sourceAssetIdentifiers: sourceAssetIdentifiers
        )
    }

    static func parseJourneyRecognizedLineGroups(
        _ lineGroups: [[String]],
        referenceDate: Date,
        sourceAssetIdentifiers: [String] = []
    ) throws -> ItineraryJourneyDraft {
        let cleanedLineGroups = lineGroups.map { lines in
            lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }.filter { !$0.isEmpty }
        let groupTexts = cleanedLineGroups
            .map { $0.joined(separator: "\n") }
            .filter { !$0.isEmpty }
        guard !groupTexts.isEmpty else { throw ScreenshotItineraryImportError.noText }

        let recognizedText = groupTexts.joined(separator: "\n")
        if let structuredDraft = structuredBookingJourneyDraft(
            from: cleanedLineGroups,
            recognizedText: recognizedText,
            referenceDate: referenceDate,
            sourceAssetIdentifiers: sourceAssetIdentifiers
        ) {
            return structuredDraft
        }
        let combinedDraft = try parseJourneyText(
            recognizedText,
            referenceDate: referenceDate,
            sourceAssetIdentifiers: sourceAssetIdentifiers
        )
        guard combinedDraft.days.count == 1, groupTexts.count > 1 else { return combinedDraft }

        // OCR 有时会漏掉其中一张图的“第 N 天”标题。多图各自都呈现独立日期/天数时，
        // 保留图片边界逐图解析，避免合并文本后整段退化成一天。
        let groupsWithDaySignal = groupTexts.filter { hasJourneyDaySignal(in: $0) }
        guard groupsWithDaySignal.count >= 2 else { return combinedDraft }

        let calendar = Calendar.current
        var inferredDays: [ItineraryJourneyDayDraft] = []
        for groupText in groupTexts {
            let groupReferenceDate = calendar.date(
                byAdding: .day,
                value: inferredDays.count,
                to: referenceDate
            ) ?? referenceDate
            let groupDraft = try parseJourneyText(
                groupText,
                referenceDate: groupReferenceDate,
                sourceAssetIdentifiers: []
            )
            for var day in groupDraft.days {
                day.sourceDayNumber = inferredDays.count + 1
                inferredDays.append(day)
            }
        }

        guard inferredDays.count > 1 else { return combinedDraft }
        return ItineraryJourneyDraft(
            days: inferredDays,
            rawText: normalizedJourneyText(recognizedText),
            sourceAssetIdentifiers: sourceAssetIdentifiers
        )
    }

    private struct StructuredJourneyEntry {
        let date: Date
        let item: ItineraryJourneyItemDraft
    }

    private static func structuredBookingJourneyDraft(
        from lineGroups: [[String]],
        recognizedText: String,
        referenceDate: Date,
        sourceAssetIdentifiers: [String]
    ) -> ItineraryJourneyDraft? {
        var entries: [StructuredJourneyEntry] = []
        for lines in lineGroups {
            if let flight = structuredFlightEntry(in: lines, referenceDate: referenceDate) {
                entries.append(flight)
            }
            if let hotel = structuredHotelEntry(in: lines, referenceDate: referenceDate) {
                entries.append(hotel)
            }
        }
        guard !entries.isEmpty else { return nil }

        var uniqueEntries: [StructuredJourneyEntry] = []
        for entry in entries {
            let isDuplicate = uniqueEntries.contains { existing in
                existing.item.category == entry.item.category
                    && existing.item.title == entry.item.title
                    && abs(existing.item.startTime.timeIntervalSince(entry.item.startTime)) < 60
                    && abs(existing.item.endTime.timeIntervalSince(entry.item.endTime)) < 60
            }
            if !isDuplicate { uniqueEntries.append(entry) }
        }

        let calendar = Calendar.current
        let sortedEntries = uniqueEntries.sorted {
            if calendar.isDate($0.date, inSameDayAs: $1.date) {
                return $0.item.startTime < $1.item.startTime
            }
            return $0.date < $1.date
        }
        var grouped: [(date: Date, items: [ItineraryJourneyItemDraft])] = []
        for entry in sortedEntries {
            if let lastIndex = grouped.indices.last,
               calendar.isDate(grouped[lastIndex].date, inSameDayAs: entry.date) {
                grouped[lastIndex].items.append(entry.item)
            } else {
                grouped.append((calendar.startOfDay(for: entry.date), [entry.item]))
            }
        }

        let days = grouped.enumerated().map { index, value in
            ItineraryJourneyDayDraft(
                sourceDayNumber: index + 1,
                date: value.date,
                routeTitle: value.items.map(\.title).joined(separator: " · "),
                note: "",
                items: value.items
            )
        }
        return ItineraryJourneyDraft(
            days: days,
            rawText: normalizedJourneyText(recognizedText),
            sourceAssetIdentifiers: sourceAssetIdentifiers
        )
    }

    private static func structuredFlightEntry(
        in lines: [String],
        referenceDate: Date
    ) -> StructuredJourneyEntry? {
        guard let flightIndex = lines.firstIndex(where: { line in
            firstCapture(in: line, pattern: #"(9C\s*[0-9]{4})"#) != nil
                || line.contains("航班号")
        }) else { return nil }

        let segmentEnd = lines.indices.first(where: {
            $0 > flightIndex && isHotelSectionMarker(lines[$0])
        }) ?? lines.endIndex
        let segment = Array(lines[flightIndex..<segmentEnd])
        let segmentText = segment.joined(separator: "\n")

        let route = lines.compactMap { line -> (String, String)? in
            guard let groups = captures(
                in: line,
                pattern: #"(?:^|\s)([\p{Han}]{2,8})\s*[-－–—→]\s*([\p{Han}]{2,8})(?:\s|$)"#
            ).first,
                  groups.count == 2 else { return nil }
            return (groups[0], groups[1])
        }.first

        let terminals = segment
            .map(normalizedFlightTerminal)
            .filter(isFlightTerminalLine)
        let originTerminal = terminals.first ?? route?.0 ?? ""
        guard !originTerminal.isEmpty else { return nil }
        let destinationTerminal = terminals.dropFirst().first ?? route?.1 ?? ""
        let origin = combinedFlightPlace(city: route?.0, terminal: originTerminal)
        let destination = combinedFlightPlace(city: route?.1, terminal: destinationTerminal)

        var seenTimes = Set<String>()
        let times = validTimes(in: segmentText).filter { value in
            seenTimes.insert("\(value.0):\(value.1)").inserted
        }
        guard times.count >= 2 else { return nil }

        let headerDate = lines.prefix(flightIndex + 1).reversed().compactMap { line -> Date? in
            guard line.contains("前往") || line.contains("飞往") || line.contains("周") || line.contains("星期") else {
                return nil
            }
            return recognizedDates(in: line, referenceDate: referenceDate).first
        }.first
        let date = headerDate
            ?? recognizedDates(in: segmentText, referenceDate: referenceDate).first
            ?? Calendar.current.startOfDay(for: referenceDate)
        let startMinutes = times[0].0 * 60 + times[0].1
        let endMinutes = times[1].0 * 60 + times[1].1
        let start = journeyDate(date, minutes: startMinutes)
        let endDay = endMinutes <= startMinutes
            ? (Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date)
            : date
        let end = journeyDate(endDay, minutes: endMinutes)
        let flightNumber = firstCapture(in: segmentText, pattern: #"(9C\s*[0-9]{4})"#)?
            .replacingOccurrences(of: " ", with: "") ?? ""
        let duration = segment.first(where: { $0.contains("小时") || $0.contains("分钟") }) ?? ""

        return StructuredJourneyEntry(
            date: Calendar.current.startOfDay(for: start),
            item: ItineraryJourneyItemDraft(
                title: destination.isEmpty ? "从\(origin)出发" : "\(origin) → \(destination)",
                category: .transport,
                startTime: start,
                endTime: end,
                address: "",
                locationMode: .route,
                originName: origin,
                destinationName: destination,
                transport: .flight,
                distanceText: duration,
                reservationInfo: flightNumber.isEmpty ? "" : "航班：\(flightNumber)",
                cost: 0,
                note: ""
            )
        )
    }

    private static func structuredHotelEntry(
        in lines: [String],
        referenceDate: Date
    ) -> StructuredJourneyEntry? {
        guard let markerIndex = lines.firstIndex(where: isHotelSectionMarker) else { return nil }
        let nextJourneyIndex = lines.indices.first(where: { index in
            guard index > markerIndex else { return false }
            let line = lines[index]
            return (line.contains("前往") || line.contains("飞往"))
                && !recognizedDates(in: line, referenceDate: referenceDate).isEmpty
        }) ?? lines.endIndex
        let segment = Array(lines[markerIndex..<nextJourneyIndex])
        guard !segment.isEmpty else { return nil }

        var titleParts: [String] = []
        for line in segment.dropFirst() {
            if line.contains("预订成功") { continue }
            if !recognizedDates(in: line, referenceDate: referenceDate).isEmpty
                || line.contains("入住时间")
                || line.contains("离店时间")
                || (line.contains("房") && (line.contains("床") || line.contains("晚") || line.contains("间"))) {
                if !titleParts.isEmpty { break }
                continue
            }
            if titleParts.isEmpty {
                if line.contains("酒店") || line.contains("民宿") || line.contains("客栈") {
                    titleParts.append(line)
                }
            } else {
                titleParts.append(line)
            }
        }
        let title = titleParts.joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: " ：:•·<>〉"))
        guard !title.isEmpty else { return nil }

        let segmentText = segment.joined(separator: "\n")
        let dates = inferDates(
            from: segmentText,
            referenceDate: referenceDate,
            category: .hotel,
            travelDurationMinutes: 0
        )
        let address = segment.first(where: { line in
            let hasRoad = ["路", "街", "巷", "道", "号", "弄"].contains(where: line.contains)
            let hasRegion = ["省", "市", "区", "县", "镇"].contains(where: line.contains)
            return hasRoad && hasRegion
        })?.trimmingCharacters(in: CharacterSet(charactersIn: " ◎•·")) ?? ""
        let room = segment.first(where: {
            $0.contains("房") && ($0.contains("床") || $0.contains("晚") || $0.contains("间"))
        }) ?? ""

        return StructuredJourneyEntry(
            date: Calendar.current.startOfDay(for: dates.start),
            item: ItineraryJourneyItemDraft(
                title: "入住\(title)",
                category: .hotel,
                startTime: dates.start,
                endTime: dates.end,
                address: address,
                locationMode: .single,
                placeName: title,
                placeAddress: address,
                transport: .car,
                distanceText: "",
                reservationInfo: room,
                cost: 0,
                note: ""
            )
        )
    }

    private static func isHotelSectionMarker(_ value: String) -> Bool {
        value.contains("酒店") && value.count <= 6
    }

    private static func normalizedFlightTerminal(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"\s+T\s*([0-9A-Z]+)$"#,
                with: "T$1",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " •·<>〉"))
    }

    private static func isFlightTerminalLine(_ value: String) -> Bool {
        firstCapture(
            in: value,
            pattern: #"^([\p{Han}A-Za-z·（）()\s-]{1,30}(?:T[0-9A-Z]+|航站楼))$"#
        ) != nil
    }

    private static func combinedFlightPlace(city: String?, terminal: String) -> String {
        guard let city, !city.isEmpty, !terminal.contains(city) else { return terminal }
        return "\(city) \(terminal)"
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

        let daySections = journeyDaySections(in: normalizedText, referenceDate: referenceDate)
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
            let fallbackDate = calendar.date(byAdding: .day, value: index, to: referenceDate) ?? referenceDate
            let dayDate = section.date ?? fallbackDate
            var draft = journeyDayDraft(
                sourceDayNumber: section.number,
                header: section.header,
                body: section.body,
                dayDate: dayDate
            )
            draft.date = section.date
            return draft
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
                for observation in observations {
                    guard let value = observation.topCandidates(1).first?.string else { continue }
                    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if shouldIgnoreScreenStatusBarText(normalized, boundingBox: observation.boundingBox) {
                        continue
                    }
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

    static func shouldIgnoreScreenStatusBarText(_ text: String, boundingBox: CGRect) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard boundingBox.minX < 0.30,
              boundingBox.maxY > 0.88,
              let regex = try? NSRegularExpression(pattern: #"^[0-9]{1,2}[:：][0-9]{2}$"#),
              regex.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized)
              ) != nil
        else { return false }

        let parts = normalized.split { $0 == ":" || $0 == "：" }
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else { return false }
        return (0...23).contains(hour) && (0...59).contains(minute)
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
        let explicitOrigin = inferExplicitValue(
            from: cleanedLines,
            labels: ["起始位置", "出发地", "始发地", "起点"]
        ).map(cleanFlightPlace)
        let explicitDestination = inferExplicitValue(
            from: cleanedLines,
            labels: ["目的地", "到达地", "终点"]
        ).map(cleanFlightPlace)
        let hasExplicitRoute = explicitOrigin != nil && explicitDestination != nil
        let inferredCategory = inferCategory(from: rawText)
        let category: PlaceCategory = hasExplicitRoute ? .transport : inferredCategory
        let transport = inferTransport(from: rawText)
        let transportOrigin = transport == .flight
            ? inferFlightOrigin(from: cleanedLines)
            : (hasExplicitRoute ? explicitOrigin : nil)
        let transportDestination = transport == .flight
            ? inferFlightDestination(from: cleanedLines)
            : (hasExplicitRoute ? explicitDestination : nil)
        let navigationDestination = category == .transport && transport != .flight
            ? inferNavigationDestination(from: cleanedLines)
            : nil
        let explicitTitle = inferExplicitValue(
            from: cleanedLines,
            labels: ["地点", "事项", "名称", "景点", "餐厅", "酒店", "住宿", "目的地"]
        )
        let naturalPlace = explicitJourneyPlaces(in: rawText).first?.name
        let inferredPlace = navigationDestination
            ?? explicitTitle
            ?? naturalPlace
            ?? inferTitle(from: cleanedLines, category: category)
        let title: String
        if let transportOrigin, let transportDestination, !transportDestination.isEmpty {
            title = "\(transportOrigin) → \(transportDestination)"
        } else {
            title = arrangementTitle(for: inferredPlace, category: category)
        }
        let address = inferAddress(from: cleanedLines)
        let locationMode: ArrangementLocationMode = transportOrigin == nil && transportDestination == nil
            ? .single
            : .route
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
            locationMode: locationMode,
            placeName: locationMode == .single ? inferredPlace : "",
            placeAddress: locationMode == .single ? address : "",
            originName: transportOrigin ?? "",
            destinationName: transportDestination ?? "",
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
        in text: String,
        referenceDate: Date
    ) -> [(number: Int, header: String, body: String, date: Date?)] {
        let explicitPattern = #"(?im)^[ \t]*[-•·]?[ \t]*(?:(?:D[ \t]*A[ \t]*Y|D)[ \t]*([0-9]{1,2})|第[ \t]*([0-9]{1,2}|[一二三四五六七八九十两]{1,3})[ \t]*[天日])[ \t]*[:：|｜—-]?[ \t]*([^\n]*)"#
        let explicitMatches = journeyDayMatches(in: text, pattern: explicitPattern)
        let explicitSections = journeySections(in: text, matches: explicitMatches) { index, match in
            let numberText = capture(in: text, match: match, indexes: [1, 2])
            let number = numberText.flatMap(journeyDayNumber) ?? index + 1
            let header = capture(in: text, match: match, indexes: [3]) ?? ""
            return (number, cleanJourneyHeader(header), nil)
        }

        let datePattern = #"(?im)^[ \t]*[-•·]?[ \t]*(?:(?:20[0-9]{2})[ \t]*[年./-][ \t]*)?([0-9]{1,2})[ \t]*[月./-][ \t]*([0-9]{1,2})[ \t]*(?:日|号)?[ \t]*(?:(?:周|星期)[ \t]*[一二三四五六日天])?[ \t]*[:：|｜—-]?[ \t]*([^\n]*)$"#
        let dateMatches = journeyDayMatches(in: text, pattern: datePattern).filter { match in
            guard let lineRange = Range(match.range, in: text) else { return false }
            let line = String(text[lineRange])
            let dateCount = captures(
                in: line,
                pattern: #"(?:(?:20[0-9]{2})年)?[0-9]{1,2}月[0-9]{1,2}[日号]?"#
            ).count
            let bookingWords = ["入住", "离店", "退房", "订单", "预订", "晚"]
            return dateCount <= 1 && !bookingWords.contains(where: line.contains)
        }
        let dateSections = journeySections(in: text, matches: dateMatches) { index, match in
            let header = capture(in: text, match: match, indexes: [3]) ?? ""
            let matchedLine = Range(match.range, in: text).map { String(text[$0]) } ?? ""
            let date = recognizedDates(in: matchedLine, referenceDate: referenceDate).first
            return (index + 1, cleanJourneyHeader(header), date)
        }
        if explicitSections.count >= 2 { return explicitSections }
        if dateSections.count >= 2 || explicitSections.isEmpty { return dateSections }
        return explicitSections
    }

    private static func journeyDayMatches(in text: String, pattern: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fullRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: fullRange)
    }

    private static func journeySections(
        in text: String,
        matches: [NSTextCheckingResult],
        marker: (Int, NSTextCheckingResult) -> (number: Int, header: String, date: Date?)
    ) -> [(number: Int, header: String, body: String, date: Date?)] {
        guard !matches.isEmpty else { return [] }
        let fullRange = NSRange(text.startIndex..., in: text)
        return matches.enumerated().compactMap { index, match in
            let bodyStart = match.range.location + match.range.length
            let bodyEnd = index + 1 < matches.count ? matches[index + 1].range.location : fullRange.length
            guard bodyStart <= bodyEnd,
                  let bodyRange = Range(NSRange(location: bodyStart, length: bodyEnd - bodyStart), in: text) else {
                return nil
            }
            let body = truncateSupplementaryJourneyContent(String(text[bodyRange]))
            let value = marker(index, match)
            return (value.number, value.header, body, value.date)
        }
    }

    private static func capture(
        in text: String,
        match: NSTextCheckingResult,
        indexes: [Int]
    ) -> String? {
        for index in indexes where index < match.numberOfRanges {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { continue }
            let value = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func journeyDayNumber(_ value: String) -> Int? {
        if let number = Int(value) { return number }
        let digits: [Character: Int] = [
            "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
            "六": 6, "七": 7, "八": 8, "九": 9, "两": 2
        ]
        if value == "十" { return 10 }
        if value.hasPrefix("十"), let last = value.last.flatMap({ digits[$0] }) { return 10 + last }
        if value.hasSuffix("十"), let first = value.first.flatMap({ digits[$0] }) { return first * 10 }
        if let tenIndex = value.firstIndex(of: "十"),
           let first = value.first.flatMap({ digits[$0] }),
           let last = value.last.flatMap({ digits[$0] }),
           tenIndex != value.startIndex,
           tenIndex != value.index(before: value.endIndex) {
            return first * 10 + last
        }
        return value.count == 1 ? value.first.flatMap { digits[$0] } : nil
    }

    private static func cleanJourneyHeader(_ value: String) -> String {
        cleanJourneyText(value)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-—:：|｜ ·"))
    }

    private static func hasJourneyDaySignal(in text: String) -> Bool {
        if !journeyDaySections(in: normalizedJourneyText(text), referenceDate: Date()).isEmpty { return true }
        let dayPattern = #"(?i)(?:D\s*A\s*Y|D)\s*[0-9]{1,2}|第\s*(?:[0-9]{1,2}|[一二三四五六七八九十两]{1,3})\s*[天日]"#
        let datePattern = #"(?:(?:20[0-9]{2})年)?[0-9]{1,2}月[0-9]{1,2}[日号]?"#
        return !journeyDayMatches(in: text, pattern: dayPattern).isEmpty
            || !journeyDayMatches(in: text, pattern: datePattern).isEmpty
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
                    address: "",
                    locationMode: .route,
                    originName: endpoints.first ?? "",
                    destinationName: endpoints.last ?? "",
                    transport: .car,
                    distanceText: metrics.text,
                    reservationInfo: "",
                    cost: 0,
                    note: ""
                )
            )
            cursorMinutes += max(60, metrics.durationMinutes) + 30
        }

        let timedItems = timedJourneyItems(in: body, dayDate: dayDate)
        items.append(contentsOf: timedItems)

        var excludedPlaces = Set(endpoints + [stay])
        for item in timedItems {
            excludedPlaces.formUnion([
                item.placeName,
                item.originName,
                item.destinationName
            ].filter { !$0.isEmpty })
        }
        if timedItems.isEmpty {
            for place in explicitJourneyPlaces(in: body) where !excludedPlaces.contains(place.name) {
                let category = inferJourneyPlaceCategory(place.name)
                let recognizedDates = validTimes(in: place.note).count >= 2
                    ? inferDates(
                        from: place.note,
                        referenceDate: dayDate,
                        category: category,
                        travelDurationMinutes: 0
                    )
                    : nil
                let start = recognizedDates?.start
                    ?? journeyDate(dayDate, minutes: min(cursorMinutes, 20 * 60))
                let end: Date
                if let recognizedDates {
                    end = recognizedDates.end
                } else {
                    end = Calendar.current.date(byAdding: .minute, value: 90, to: start) ?? start
                }
                items.append(
                    ItineraryJourneyItemDraft(
                        title: arrangementTitle(for: place.name, category: category),
                        category: category,
                        startTime: start,
                        endTime: end,
                        address: "",
                        locationMode: .single,
                        placeName: place.name,
                        transport: .car,
                        distanceText: "",
                        reservationInfo: "",
                        cost: 0,
                        note: place.note
                    )
                )
                let endMinutes = Calendar.current.component(.hour, from: end) * 60
                    + Calendar.current.component(.minute, from: end)
                cursorMinutes = max(cursorMinutes + 120, endMinutes + 30)
            }
        }

        if !stay.isEmpty {
            let start = journeyDate(dayDate, minutes: 19 * 60)
            let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: dayDate) ?? dayDate
            let end = journeyDate(nextDay, minutes: 8 * 60)
            items.append(
                ItineraryJourneyItemDraft(
                    title: "入住\(stay)",
                    category: .hotel,
                    startTime: start,
                    endTime: end,
                    address: "",
                    locationMode: .single,
                    placeName: stay,
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
            locationMode: draft.locationMode,
            placeName: draft.placeName,
            placeAddress: draft.placeAddress,
            originName: draft.originName,
            originAddress: draft.originAddress,
            destinationName: draft.destinationName,
            destinationAddress: draft.destinationAddress,
            transport: draft.transport,
            distanceText: draft.distanceText,
            reservationInfo: draft.reservationInfo,
            cost: draft.cost,
            note: draft.note
        )
    }

    private static func explicitJourneyPlaces(in text: String) -> [(name: String, note: String)] {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: "，。；！\n"))
        let pattern = #"(?:依次打卡|顺路打卡|深度游玩|游玩|游览|参观|打卡|翻越|前往|可以去|去|经由|经)\s*([^，。；！\n]{2,50})"#
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

    private static func timedJourneyItems(
        in text: String,
        dayDate: Date
    ) -> [ItineraryJourneyItemDraft] {
        let lines = text.components(separatedBy: .newlines)

        var blocks: [[String]] = []
        var current: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if firstTimeRange(in: trimmed) != nil {
                if !current.isEmpty { blocks.append(current) }
                current = [trimmed]
            } else if !current.isEmpty {
                current.append(trimmed)
            }
        }
        if !current.isEmpty { blocks.append(current) }

        // A single block is handled well by the existing fallback. This path is
        // specifically for one day containing multiple independently timed plans.
        guard blocks.count >= 2 else { return [] }
        return blocks.map {
            journeyItem(from: parseRecognizedLines($0, referenceDate: dayDate))
        }
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
        if text.contains("景区") || text.contains("公园") || text.contains("博物馆") ||
            text.contains("游览") || text.contains("参观") || text.contains("门票") || text.contains("入园") {
            return .attraction
        }
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

    private static func inferFlightOrigin(from lines: [String]) -> String? {
        if let explicitOrigin = inferExplicitValue(
            from: lines,
            labels: ["起始位置", "出发地", "始发地", "起点"]
        ) {
            return cleanFlightPlace(explicitOrigin)
        }

        for line in lines {
            let route = line
                .replacingOccurrences(of: "➡️", with: "→")
                .replacingOccurrences(of: "->", with: "→")
            if route.contains("→"), let origin = route.components(separatedBy: "→").first {
                let cleaned = cleanFlightPlace(origin)
                if isFlightPlaceLine(cleaned) { return cleaned }
            }

            let cleaned = cleanFlightPlace(line)
            if isFlightPlaceLine(cleaned) { return cleaned }
        }
        return nil
    }

    private static func inferFlightDestination(from lines: [String]) -> String? {
        if let explicitDestination = inferExplicitValue(
            from: lines,
            labels: ["目的地", "到达地", "终点"]
        ) {
            return cleanFlightPlace(explicitDestination)
        }

        for line in lines {
            let route = line
                .replacingOccurrences(of: "➡️", with: "→")
                .replacingOccurrences(of: "->", with: "→")
            if route.contains("→"), let destination = route.components(separatedBy: "→").last {
                let cleaned = cleanFlightPlace(destination)
                if isFlightPlaceLine(cleaned) { return cleaned }
            }
        }

        let places = lines.map(cleanFlightPlace).filter(isFlightPlaceLine)
        return places.dropFirst().first
    }

    private static func arrangementTitle(for placeName: String, category: PlaceCategory) -> String {
        let place = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else { return "待补充的安排" }
        if place.contains("→") || place.hasPrefix("入住") || place.hasPrefix("游览") {
            return place
        }
        switch category {
        case .attraction: return "游览\(place)"
        case .restaurant: return "在\(place)用餐"
        case .hotel: return "入住\(place)"
        case .transport: return "前往\(place)"
        case .shopping, .special, .note, .other: return "前往\(place)"
        }
    }

    private static func cleanFlightPlace(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " •·<>〉-—"))
    }

    private static func isFlightPlaceLine(_ value: String) -> Bool {
        guard value.count >= 3, value.count <= 40 else { return false }
        let ignored = ["航空", "航班", "计划", "预计", "机票", "行程助手", "航站楼变更"]
        guard !ignored.contains(where: value.contains) else { return false }
        if value.contains("机场") { return true }
        return firstCapture(
            in: value,
            pattern: #"^([\p{Han}A-Za-z·（）()\s-]{2,30}(?:T\s*[0-9A-Z]+|航站楼))$"#
        ) != nil
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
        var uniqueDates: [Date] = []
        for date in recognizedDates(in: text, referenceDate: referenceDate) {
            if !uniqueDates.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
                uniqueDates.append(date)
            }
        }

        let defaultStartDay = uniqueDates.first ?? calendar.startOfDay(for: referenceDate)
        let defaultEndDay = uniqueDates.dropFirst().first
            ?? (category == .hotel ? calendar.date(byAdding: .day, value: 1, to: defaultStartDay)! : defaultStartDay)
        let timeRange = firstTimeRange(in: text)
        let rawTimes = validTimes(in: text)
        var seenTimes = Set<String>()
        let uniqueTimes = rawTimes.filter { time in
            seenTimes.insert("\(time.0):\(time.1)").inserted
        }
        // 航班等页面会先显示计划时间，再以“预计 MM/dd HH:mm”重复同一时间。
        // 有两个以上不同时间时按去重后的顺序取起止；若两个日期恰好同一时刻，则保留重复时间。
        let orderedTimes = uniqueTimes.count >= 2 ? uniqueTimes : rawTimes
        let checkInTime = time(before: "入住", in: text)
            ?? time(after: "入住", in: text)
            ?? timeRange?.start
            ?? orderedTimes.first
            ?? (category == .hotel ? (14, 0) : (9, 0))
        let checkOutTime = time(before: "离店", in: text)
            ?? time(after: "离店", in: text)
            ?? timeRange?.end
            ?? orderedTimes.dropFirst().first
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
        validTimes(in: text).first
    }

    private static func validTimes(in text: String) -> [(Int, Int)] {
        captures(in: text, pattern: "(\\d{1,2})[:：](\\d{2})").compactMap { groups in
            guard groups.count == 2,
                  let hour = Int(groups[0]),
                  let minute = Int(groups[1]),
                  (0...23).contains(hour),
                  (0...59).contains(minute)
            else { return nil }
            return (hour, minute)
        }
    }

    private static func recognizedDates(in text: String, referenceDate: Date) -> [Date] {
        let patterns = [
            "(?:(\\d{4})年)?(\\d{1,2})月(\\d{1,2})(?:日|号)?",
            "(?<!\\d)(?:(\\d{4})[./-])?(\\d{1,2})[./-](\\d{1,2})(?!\\d)"
        ]
        var components: [(location: Int, year: Int?, month: Int, day: Int)] = []
        let fullRange = NSRange(text.startIndex..., in: text)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: fullRange) {
                func capturedInt(_ index: Int) -> Int? {
                    guard index < match.numberOfRanges,
                          match.range(at: index).location != NSNotFound,
                          let range = Range(match.range(at: index), in: text)
                    else { return nil }
                    return Int(text[range])
                }
                guard let month = capturedInt(2),
                      let day = capturedInt(3),
                      (1...12).contains(month),
                      (1...31).contains(day)
                else { continue }
                components.append((match.range.location, capturedInt(1), month, day))
            }
        }

        let calendar = Calendar.current
        let referenceYear = calendar.component(.year, from: referenceDate)
        return components.sorted { $0.location < $1.location }.compactMap { value in
            let years = value.year.map { [$0] } ?? [referenceYear - 1, referenceYear, referenceYear + 1]
            return years.compactMap {
                calendar.date(from: DateComponents(year: $0, month: value.month, day: value.day))
            }.min {
                abs($0.timeIntervalSince(referenceDate)) < abs($1.timeIntervalSince(referenceDate))
            }
        }
    }

    private static func firstTimeRange(in text: String) -> (start: (Int, Int), end: (Int, Int))? {
        let patterns = [
            "(\\d{1,2})[:：](\\d{2})\\s*[-－–—~～至到]\\s*(\\d{1,2})[:：](\\d{2})",
            "(?:开始|起始|出发)(?:时间)?[^\\d\\n]{0,8}(\\d{1,2})[:：](\\d{2})[^\\n]{0,24}?(?:结束|终止|到达)(?:时间)?[^\\d\\n]{0,8}(\\d{1,2})[:：](\\d{2})",
            "(\\d{1,2})[:：](\\d{2})[^\\d\\n]{0,12}(?:开始|起始|出发)[^\\n]{0,24}?(\\d{1,2})[:：](\\d{2})[^\\d\\n]{0,8}(?:结束|终止|到达)"
        ]
        guard let groups = patterns.lazy.compactMap({ captures(in: text, pattern: $0).first }).first,
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

struct JourneyImportPreview {
    let dates: [Date]
    let existingDayCount: Int
    let emptyDayCount: Int

    var totalDayCount: Int { dates.count }
    var newDayCount: Int { max(0, totalDayCount - existingDayCount) }
}

struct JourneyImportApplyResult {
    let affectedDays: [TripDay]
    let createdDays: [TripDay]
    let createdItems: [ItineraryItem]
    let createdMedia: [MediaReference]
}

enum JourneyImportApplyService {
    private struct PlannedDay {
        let date: Date
        let drafts: [ItineraryJourneyDayDraft]
    }

    static func preview(
        _ draft: ItineraryJourneyDraft,
        for trip: Trip,
        calendar: Calendar = .current
    ) -> JourneyImportPreview {
        let plan = plannedDays(for: draft, in: trip, calendar: calendar)
        let tripStart = calendar.startOfDay(for: trip.startDate)
        let existingDates = trip.sortedDays.indices.map { index in
            calendar.date(byAdding: .day, value: index, to: tripStart) ?? tripStart
        }
        return JourneyImportPreview(
            dates: plan.map(\.date),
            existingDayCount: plan.filter { planned in
                existingDates.contains { calendar.isDate($0, inSameDayAs: planned.date) }
            }.count,
            emptyDayCount: plan.filter(\.drafts.isEmpty).count
        )
    }

    static func append(
        _ draft: ItineraryJourneyDraft,
        to trip: Trip,
        attachSourceImages: Bool,
        calendar: Calendar = .current
    ) -> JourneyImportApplyResult {
        JourneyHierarchyService.normalizeTripDaySchedule(trip, calendar: calendar)
        let plan = plannedDays(for: draft, in: trip, calendar: calendar)
        guard !plan.isEmpty else {
            return JourneyImportApplyResult(
                affectedDays: [],
                createdDays: [],
                createdItems: [],
                createdMedia: []
            )
        }

        let existingDays = trip.sortedDays
        var daysByDate: [Date: TripDay] = [:]
        for day in existingDays {
            let date = calendar.startOfDay(for: day.date)
            if daysByDate[date] == nil { daysByDate[date] = day }
        }
        var nextDaySortOrder = (existingDays.map(\.sortOrder).max() ?? -1) + 1

        var affectedDays: [TripDay] = []
        var createdDays: [TripDay] = []
        var createdItems: [ItineraryItem] = []
        var firstImportedItem: ItineraryItem?
        for plannedDay in plan {
            let day: TripDay
            if let existingDay = daysByDate[plannedDay.date] {
                day = existingDay
            } else {
                day = TripDay(
                    date: plannedDay.date,
                    title: "",
                    sortOrder: nextDaySortOrder,
                    trip: trip
                )
                nextDaySortOrder += 1
                trip.days.append(day)
                daysByDate[plannedDay.date] = day
                createdDays.append(day)
            }

            var nextItemSortOrder = (day.items.map(\.sortOrder).max() ?? -1) + 1
            for dayDraft in plannedDay.drafts {
                day.note = mergedDayNote(
                    existing: day.note,
                    additions: [dayDraft.routeTitle, dayDraft.note]
                )

                for itemDraft in dayDraft.items where itemDraft.isIncluded {
                    let cleanTitle = itemDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanTitle.isEmpty else { continue }
                    let times = rebasedTimes(
                        start: itemDraft.startTime,
                        end: itemDraft.endTime,
                        onto: plannedDay.date,
                        calendar: calendar
                    )
                    let item = ItineraryItem(
                        title: cleanTitle,
                        category: itemDraft.category,
                        startTime: times.start,
                        endTime: times.end,
                        sortOrder: nextItemSortOrder
                    )
                    nextItemSortOrder += 1
                    item.locationMode = itemDraft.locationMode
                    item.placeName = JourneyLocationText.entityName(
                        from: itemDraft.placeName,
                        arrangementTitle: cleanTitle
                    )
                    item.placeAddress = itemDraft.placeAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    item.originName = JourneyLocationText.entityName(
                        from: itemDraft.originName,
                        arrangementTitle: cleanTitle,
                        role: .origin
                    )
                    item.originAddress = itemDraft.originAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    item.destinationName = JourneyLocationText.entityName(
                        from: itemDraft.destinationName,
                        arrangementTitle: cleanTitle,
                        role: .destination
                    )
                    item.destinationAddress = itemDraft.destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    if item.locationMode == .single, item.placeName.isEmpty {
                        item.placeName = JourneyLocationText.entityName(
                            from: cleanTitle,
                            arrangementTitle: cleanTitle
                        )
                        item.placeAddress = itemDraft.address.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    item.address = item.locationMode == .single ? item.placeAddress : item.destinationAddress
                    item.transport = itemDraft.transport
                    item.distanceText = itemDraft.distanceText.trimmingCharacters(in: .whitespacesAndNewlines)
                    item.reservationInfo = itemDraft.reservationInfo.trimmingCharacters(in: .whitespacesAndNewlines)
                    item.cost = itemDraft.cost
                    item.note = itemDraft.note.trimmingCharacters(in: .whitespacesAndNewlines)
                    item.playDurationMinutes = max(0, Int(times.end.timeIntervalSince(times.start) / 60))
                    item.day = day
                    day.items.append(item)
                    createdItems.append(item)
                    if firstImportedItem == nil { firstImportedItem = item }
                }
            }
            affectedDays.append(day)
        }

        var createdMedia: [MediaReference] = []
        if attachSourceImages, let firstImportedItem {
            for (index, identifier) in draft.sourceAssetIdentifiers.enumerated() {
                let reference = MediaReference(localIdentifier: identifier, kind: .image, sortOrder: index)
                reference.itineraryItem = firstImportedItem
                firstImportedItem.media.append(reference)
                createdMedia.append(reference)
            }
        }

        let chronologicalDays = trip.days.sorted {
            let lhsDate = calendar.startOfDay(for: $0.date)
            let rhsDate = calendar.startOfDay(for: $1.date)
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return $0.sortOrder < $1.sortOrder
        }
        for (index, day) in chronologicalDays.enumerated() { day.sortOrder = index }

        if let firstPlannedDate = plan.map(\.date).min(),
           let lastPlannedDate = plan.map(\.date).max() {
            if existingDays.isEmpty {
                trip.startDate = firstPlannedDate
                trip.endDate = lastPlannedDate
            } else {
                if firstPlannedDate < calendar.startOfDay(for: trip.startDate) {
                    trip.startDate = firstPlannedDate
                }
                if lastPlannedDate > calendar.startOfDay(for: trip.endDate) {
                    trip.endDate = lastPlannedDate
                }
            }
        }
        JourneyHierarchyService.normalizeTripDaySchedule(trip, calendar: calendar)
        return JourneyImportApplyResult(
            affectedDays: affectedDays,
            createdDays: createdDays,
            createdItems: createdItems,
            createdMedia: createdMedia
        )
    }

    private static func plannedDays(
        for draft: ItineraryJourneyDraft,
        in trip: Trip,
        calendar: Calendar
    ) -> [PlannedDay] {
        guard !draft.days.isEmpty else { return [] }

        let fallbackFirstDate: Date
        if !trip.sortedDays.isEmpty {
            let tripStart = calendar.startOfDay(for: trip.startDate)
            fallbackFirstDate = calendar.date(
                byAdding: .day,
                value: trip.sortedDays.count,
                to: tripStart
            ) ?? tripStart
        } else {
            fallbackFirstDate = calendar.startOfDay(for: trip.startDate)
        }

        let sourceDayNumbers = draft.days.map(\.sourceDayNumber)
        let firstSourceDayNumber = sourceDayNumbers.min() ?? 1
        let explicitAnchor = draft.days.compactMap { day -> (number: Int, date: Date)? in
            guard let date = day.date else { return nil }
            return (day.sourceDayNumber, calendar.startOfDay(for: date))
        }.first

        var draftsByDate: [Date: [ItineraryJourneyDayDraft]] = [:]
        for (index, dayDraft) in draft.days.enumerated() {
            let date: Date
            if let explicitDate = dayDraft.date {
                date = calendar.startOfDay(for: explicitDate)
            } else if let explicitAnchor {
                date = calendar.date(
                    byAdding: .day,
                    value: dayDraft.sourceDayNumber - explicitAnchor.number,
                    to: explicitAnchor.date
                ) ?? explicitAnchor.date
            } else {
                let sourceOffset = dayDraft.sourceDayNumber - firstSourceDayNumber
                let offset = sourceOffset >= 0 ? sourceOffset : index
                date = calendar.date(byAdding: .day, value: offset, to: fallbackFirstDate)
                    ?? fallbackFirstDate
            }
            draftsByDate[date, default: []].append(dayDraft)
        }

        guard let firstDate = draftsByDate.keys.min(),
              let lastDate = draftsByDate.keys.max()
        else { return [] }
        let dayCount = max(
            1,
            (calendar.dateComponents([.day], from: firstDate, to: lastDate).day ?? 0) + 1
        )
        return (0..<dayCount).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: firstDate) ?? firstDate
            return PlannedDay(date: date, drafts: draftsByDate[date] ?? [])
        }
    }

    private static func mergedDayNote(existing: String, additions: [String]) -> String {
        var parts: [String] = []
        for value in [existing] + additions {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, !parts.contains(clean) else { continue }
            parts.append(clean)
        }
        return parts.joined(separator: "\n")
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
