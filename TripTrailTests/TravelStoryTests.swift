import SwiftData
import XCTest
@testable import TripTrail

@MainActor
final class TravelStoryTests: XCTestCase {
    func testDebugRouteSamplesAreAddedOnceWithOriginAndDestination() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16)))
        let trip = Trip(
            title: "厦门海风旧游（测试）",
            destination: "厦门",
            startDate: date,
            endDate: date
        )
        trip.id = try XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000000003"))
        let day = TripDay(date: date, title: "鼓浪屿一日", sortOrder: 0, trip: trip)
        day.id = try XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000000030"))
        trip.days = [day]

        XCTAssertTrue(DebugSampleDataService.ensureRouteSamples(in: [trip], calendar: calendar))
        XCTAssertFalse(DebugSampleDataService.ensureRouteSamples(in: [trip], calendar: calendar))

        let routes = day.sortedItems.filter { $0.locationMode == .route }
        XCTAssertEqual(routes.count, 3)
        XCTAssertEqual(routes.map(\.originName), ["厦门站", "三丘田码头", "菽庄花园"])
        XCTAssertEqual(routes.map(\.destinationName), ["厦门邮轮中心厦鼓码头", "菽庄花园", "厦门站"])
        XCTAssertTrue(routes.allSatisfy { $0.executionStatus == .completed })
    }

    func testFavoriteFilteringSearchesArrangementFieldsAndCategory() {
        let first = ItineraryItem(
            title: "西湖日落",
            category: .attraction,
            startTime: Date(),
            endTime: Date(),
            sortOrder: 0
        )
        first.isFavorite = true
        first.placeName = "曲院风荷"
        first.note = "想在傍晚去"

        let second = ItineraryItem(
            title: "楼外楼",
            category: .restaurant,
            startTime: Date(),
            endTime: Date(),
            sortOrder: 0
        )
        second.isFavorite = true
        second.placeName = "孤山路"

        let scheduled = ItineraryItem(
            title: "已排入旅程",
            category: .attraction,
            startTime: Date(),
            endTime: Date(),
            sortOrder: 0
        )

        XCTAssertEqual(
            FavoriteArrangementService.filtered(
                [first, second, scheduled],
                searchText: "曲院",
                category: nil
            ).map(\.id),
            [first.id]
        )
        XCTAssertEqual(
            FavoriteArrangementService.filtered(
                [first, second, scheduled],
                searchText: "",
                category: .restaurant
            ).map(\.id),
            [second.id]
        )
    }

    func testFootprintBrowsingSearchesNestedPlacesAndGroupsFilteredResultsByYear() throws {
        let calendar = Calendar(identifier: .gregorian)
        let hangzhouDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 29)))
        let xiamenDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 7, day: 16)))

        let hangzhou = TravelStory(
            title: "杭州湖畔慢游",
            destination: "杭州",
            startDate: hangzhouDate,
            endDate: hangzhouDate,
            summary: "沿着湖边慢慢走"
        )
        let hangzhouDay = StoryDay(date: hangzhouDate, title: "西湖环线", sortOrder: 0, story: hangzhou)
        let bridge = StoryEntry(title: "晨间散步", category: .attraction, sortOrder: 0)
        bridge.placeName = "断桥残雪"
        bridge.story = hangzhou
        bridge.storyDay = hangzhouDay
        let media = MediaReference(localIdentifier: "photo-1", kind: .image)
        media.storyEntry = bridge
        bridge.media = [media]
        hangzhouDay.entries = [bridge]
        hangzhou.days = [hangzhouDay]
        hangzhou.entries = [bridge]

        let xiamen = TravelStory(
            title: "厦门海风手记",
            destination: "厦门",
            startDate: xiamenDate,
            endDate: xiamenDate,
            summary: "纯文字足迹"
        )

        XCTAssertEqual(
            FootprintBrowseService.filtered(
                [xiamen, hangzhou],
                searchText: "断桥",
                year: nil,
                calendar: calendar
            ).map(\.id),
            [hangzhou.id]
        )
        XCTAssertEqual(
            FootprintBrowseService.filtered(
                [xiamen, hangzhou],
                searchText: "",
                year: 2026,
                calendar: calendar
            ).map(\.id),
            [hangzhou.id]
        )
        XCTAssertEqual(
            FootprintBrowseService.groupedByYear([xiamen, hangzhou], calendar: calendar).map(\.year),
            [2026, 2025]
        )
    }

    func testImportingMultipleFavoritesCopiesFieldsAndSchedulesSequentially() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9))!
        let day = TripDay(date: date, title: "第一天", sortOrder: 0)

        let first = ItineraryItem(
            title: "拙政园",
            category: .attraction,
            startTime: date,
            endTime: date,
            sortOrder: 0
        )
        first.isFavorite = true
        first.placeName = "拙政园"
        first.placeAddress = "东北街178号"
        first.playDurationMinutes = 90
        first.cost = 80

        let second = ItineraryItem(
            title: "平江路",
            category: .attraction,
            startTime: date,
            endTime: date,
            sortOrder: 0
        )
        second.isFavorite = true
        second.placeName = "平江路"
        second.playDurationMinutes = 60

        let imported = FavoriteArrangementService.importFavorites(
            [first, second],
            into: day,
            calendar: calendar
        )

        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(imported[0].sourceFavoriteID, first.id)
        XCTAssertEqual(imported[0].placeAddress, "东北街178号")
        XCTAssertEqual(imported[0].cost, 80)
        XCTAssertFalse(imported[0].isFavorite)
        XCTAssertEqual(imported[0].startTime, date)
        XCTAssertEqual(imported[0].endTime, date.addingTimeInterval(90 * 60))
        XCTAssertEqual(imported[1].startTime, imported[0].endTime)
        XCTAssertEqual(day.sortedItems.map(\.title), ["拙政园", "平江路"])
    }

    func testPlaceCategoriesHideRemovedOptionsAndMapLegacyValuesToOther() {
        XCTAssertTrue(PlaceCategory.allCases.contains(.other))
        XCTAssertFalse(PlaceCategory.allCases.contains(.shopping))
        XCTAssertFalse(PlaceCategory.allCases.contains(.note))
        XCTAssertEqual(PlaceCategory.resolved(rawValue: "购物"), .other)
        XCTAssertEqual(PlaceCategory.resolved(rawValue: "待办"), .other)

        let item = ItineraryItem(
            title: "旧数据",
            category: .attraction,
            startTime: Date(),
            endTime: Date(),
            sortOrder: 0
        )
        item.categoryRaw = "购物"
        XCTAssertEqual(item.category, .other)
    }

    func testDeletingTripCascadesToDaysItemsAndMedia() throws {
        let schema = Schema([
            Trip.self,
            TripDay.self,
            ItineraryItem.self,
            MediaReference.self,
            TravelStory.self,
            StoryDay.self,
            StoryEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let now = Date()
        let trip = Trip(title: "待删除行程", destination: "杭州", startDate: now, endDate: now)
        let day = TripDay(date: now, title: "第一天", sortOrder: 0, trip: trip)
        let item = ItineraryItem(title: "西湖", category: .attraction, startTime: now, endTime: now, sortOrder: 0)
        let media = MediaReference(localIdentifier: "trip-photo-id", kind: .image)

        item.day = day
        item.media.append(media)
        media.itineraryItem = item
        day.items.append(item)
        trip.days.append(day)
        context.insert(trip)
        try context.save()

        context.delete(trip)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<Trip>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TripDay>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ItineraryItem>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MediaReference>()).isEmpty)
    }

    func testHierarchyDeletionCopyUsesOneConfirmationPattern() {
        XCTAssertEqual(HierarchyDeletionCopy.confirmationButtonTitle, "确认删除")
        XCTAssertEqual(HierarchyDeletionCopy.cancelButtonTitle, "取消")
        XCTAssertEqual(HierarchyDeletionCopy.tripTitle, "删除旅程？")
        XCTAssertEqual(HierarchyDeletionCopy.tripDayTitle, "删除当天？")
        XCTAssertEqual(HierarchyDeletionCopy.itineraryItemTitle, "删除安排？")
        XCTAssertEqual(HierarchyDeletionCopy.storyTitle, "删除足迹？")
        XCTAssertEqual(HierarchyDeletionCopy.storyDayTitle, "删除当天？")
        XCTAssertEqual(HierarchyDeletionCopy.storyEntryTitle, "删除这条记录？")
        XCTAssertTrue(HierarchyDeletionCopy.tripMessage(title: "杭州").contains("每日安排"))
        XCTAssertTrue(HierarchyDeletionCopy.storyMessage(title: "杭州").contains("原旅程不会受到影响"))
    }

    func testDeletingStoryCascadesToDaysEntriesAndMedia() throws {
        let schema = Schema([
            Trip.self,
            TripDay.self,
            ItineraryItem.self,
            MediaReference.self,
            TravelStory.self,
            StoryDay.self,
            StoryEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let story = TravelStory(title: "待删除足迹", destination: "杭州", startDate: Date(), endDate: Date(), summary: "")
        let day = StoryDay(date: Date(), title: "第一天", sortOrder: 0, story: story)
        let entry = StoryEntry(title: "西湖", category: .attraction, sortOrder: 0)
        let media = MediaReference(localIdentifier: "photo-id", kind: .image)

        entry.story = story
        entry.storyDay = day
        entry.media.append(media)
        media.storyEntry = entry
        day.entries.append(entry)
        story.days.append(day)
        story.entries.append(entry)
        context.insert(story)
        try context.save()

        context.delete(story)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<TravelStory>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StoryDay>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StoryEntry>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MediaReference>()).isEmpty)
    }

    func testDeletingOneStoryPhotoKeepsOtherMediaAndRenumbersOrder() throws {
        let schema = Schema([
            Trip.self,
            TripDay.self,
            ItineraryItem.self,
            MediaReference.self,
            TravelStory.self,
            StoryDay.self,
            StoryEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let entry = StoryEntry(title: "断桥晨光", category: .attraction, sortOrder: 0)
        let first = MediaReference(localIdentifier: "first-photo", kind: .image, sortOrder: 0)
        let second = MediaReference(localIdentifier: "second-video", kind: .video, sortOrder: 7)

        first.storyEntry = entry
        second.storyEntry = entry
        entry.media = [second, first]
        context.insert(entry)
        try context.save()

        StoryMediaDeletionService.remove(first, from: entry, in: context)
        try context.save()

        XCTAssertEqual(entry.sortedMedia.map(\.localIdentifier), ["second-video"])
        XCTAssertEqual(entry.sortedMedia.first?.sortOrder, 0)
        let storedMedia = try context.fetch(FetchDescriptor<MediaReference>())
        XCTAssertEqual(storedMedia.map(\.localIdentifier), ["second-video"])
    }

    func testNewItineraryItemStartsWhenPreviousItemEnds() {
        let calendar = Calendar(identifier: .gregorian)
        let dayDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        let day = TripDay(date: dayDate, title: "第一天", sortOrder: 0)
        let firstStart = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: dayDate)!
        let firstEnd = calendar.date(bySettingHour: 11, minute: 15, second: 0, of: dayDate)!
        let secondEnd = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: dayDate)!
        let firstItem = ItineraryItem(title: "第一段", category: .attraction, startTime: firstStart, endTime: firstEnd, sortOrder: 0)
        let secondItem = ItineraryItem(title: "第二段", category: .restaurant, startTime: firstEnd, endTime: secondEnd, sortOrder: 1)

        day.items = [secondItem, firstItem]

        XCTAssertEqual(day.suggestedStartTime(calendar: calendar), secondEnd)
    }

    func testFirstItineraryItemDefaultsToNineAM() {
        let calendar = Calendar(identifier: .gregorian)
        let dayDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        let day = TripDay(date: dayDate, title: "第一天", sortOrder: 0)
        let expected = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayDate)!

        XCTAssertEqual(day.suggestedStartTime(calendar: calendar), expected)
    }

    func testElapsedArrangementsCompleteAndPastDayCollapses() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let day = TripDay(date: yesterday, title: "昨天", sortOrder: 0)
        let first = ItineraryItem(title: "景点", category: .attraction, startTime: yesterday, endTime: yesterday, sortOrder: 0)
        let second = ItineraryItem(title: "晚餐", category: .restaurant, startTime: yesterday, endTime: yesterday, sortOrder: 1)
        second.isCompleted = true
        day.items = [first, second]

        XCTAssertTrue(day.completeElapsedItems(relativeTo: today))
        XCTAssertTrue(day.items.allSatisfy(\.isCompleted))
        XCTAssertTrue(day.shouldAutomaticallyCollapse(relativeTo: today, calendar: calendar))
    }

    func testOnlyArrangementsWhoseEndTimeHasPassedAreAutomaticallyCompleted() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
        let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today)!
        let morningEnd = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        let afternoonEnd = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: today)!
        let day = TripDay(date: today, title: "今天", sortOrder: 0)
        let elapsed = ItineraryItem(title: "上午安排", category: .note, startTime: today, endTime: morningEnd, sortOrder: 0)
        let upcoming = ItineraryItem(title: "下午安排", category: .note, startTime: today, endTime: afternoonEnd, sortOrder: 1)
        day.items = [elapsed, upcoming]

        XCTAssertTrue(day.completeElapsedItems(relativeTo: now))
        XCTAssertTrue(elapsed.isCompleted)
        XCTAssertFalse(upcoming.isCompleted)
        XCTAssertFalse(day.shouldAutomaticallyCollapse(relativeTo: now, calendar: calendar))
    }

    func testLegacyManualOverrideNoLongerBlocksTimeBasedStatus() {
        let now = Date()
        let item = ItineraryItem(
            title: "已结束安排",
            category: .note,
            startTime: now.addingTimeInterval(-7_200),
            endTime: now.addingTimeInterval(-3_600),
            sortOrder: 0
        )

        item.executionStatus = .notStarted
        item.isAutomaticCompletionOverridden = true

        XCTAssertTrue(item.completeIfElapsed(relativeTo: now))
        XCTAssertTrue(item.isCompleted)
        XCTAssertFalse(item.isAutomaticCompletionOverridden)
    }

    func testExecutionStatusAutomaticallyAdvancesThroughAllThreeStages() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let item = ItineraryItem(
            title: "游览世纪公园",
            category: .attraction,
            startTime: start,
            endTime: start.addingTimeInterval(3_600),
            sortOrder: 0
        )

        XCTAssertEqual(item.executionStatus, .notStarted)
        XCTAssertFalse(item.completeIfElapsed(relativeTo: start.addingTimeInterval(-1)))
        XCTAssertTrue(item.completeIfElapsed(relativeTo: start.addingTimeInterval(60)))
        XCTAssertEqual(item.executionStatus, .inProgress)
        XCTAssertTrue(item.completeIfElapsed(relativeTo: start.addingTimeInterval(3_601)))
        XCTAssertEqual(item.executionStatus, .completed)
        XCTAssertTrue(item.isCompleted)
    }

    func testAutomaticExecutionStatusMovesBackWhenScheduleMovesIntoFuture() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let item = ItineraryItem(
            title: "游览世纪公园",
            category: .attraction,
            startTime: start,
            endTime: start.addingTimeInterval(3_600),
            sortOrder: 0
        )

        XCTAssertTrue(item.completeIfElapsed(relativeTo: start.addingTimeInterval(7_200)))
        XCTAssertEqual(item.executionStatus, .completed)
        XCTAssertTrue(item.completeIfElapsed(relativeTo: start.addingTimeInterval(-1)))
        XCTAssertEqual(item.executionStatus, .notStarted)
        XCTAssertFalse(item.isCompleted)
    }

    func testLocationTargetsSeparateArrangementCopyFromMapEntities() throws {
        let date = Date()
        let single = ItineraryItem(
            title: "外滩夜景",
            category: .attraction,
            startTime: date,
            endTime: date,
            sortOrder: 0
        )
        single.locationMode = .single
        single.placeName = "外滩夜景"
        single.placeAddress = "上海市黄浦区中山东一路"

        XCTAssertEqual(try XCTUnwrap(single.primaryNavigationTarget).displayName, "外滩")
        XCTAssertEqual(single.locationSummary, "外滩")
        XCTAssertEqual(
            JourneyLocationText.entityName(from: "外滩夜景", arrangementTitle: "拍摄外滩夜景"),
            "外滩"
        )
        XCTAssertEqual(
            JourneyLocationText.entityName(from: "虹桥机场集合", arrangementTitle: "等待同行人集合"),
            "虹桥机场"
        )
        XCTAssertEqual(
            JourneyLocationText.entityName(from: "高铁抵达杭州东站", arrangementTitle: "高铁抵达杭州东站"),
            "杭州东站"
        )
        XCTAssertEqual(
            JourneyLocationText.entityName(from: "断桥晨光", arrangementTitle: "断桥晨光"),
            "断桥"
        )

        let route = ItineraryItem(
            title: "广州 → 上海",
            category: .transport,
            startTime: date,
            endTime: date,
            sortOrder: 1
        )
        route.locationMode = .route
        route.originName = "广州 白云T3出发"
        route.destinationName = "上海 虹桥T1到达"

        XCTAssertEqual(route.nextNavigationTarget?.displayName, "广州 白云T3")
        XCTAssertEqual(route.primaryNavigationTarget?.displayName, "上海 虹桥T1")
        XCTAssertEqual(route.locationSummary, "广州 白云T3 → 上海 虹桥T1")
    }

    func testRoutePlanningOrdersByTimeFlattensRoutesAndDeduplicatesConnections() {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let day = TripDay(date: date, title: "全天", sortOrder: 0)
        let later = ItineraryItem(
            title: "外滩夜景",
            category: .attraction,
            startTime: date.addingTimeInterval(7_200),
            endTime: date.addingTimeInterval(10_800),
            sortOrder: 0
        )
        later.locationMode = .single
        later.placeName = "外滩"
        let earlier = ItineraryItem(
            title: "虹桥机场 → 外滩",
            category: .transport,
            startTime: date,
            endTime: date.addingTimeInterval(3_600),
            sortOrder: 1
        )
        earlier.locationMode = .route
        earlier.originName = "上海虹桥国际机场 T2"
        earlier.destinationName = "外滩"
        day.items = [later, earlier]

        let points = ItineraryRoutePlanning.points(in: [day])

        XCTAssertEqual(points.map(\.target.displayName), ["上海虹桥国际机场 T2", "外滩"])
        XCTAssertEqual(points.map(\.arrangementTitle), ["虹桥机场 → 外滩", "虹桥机场 → 外滩"])
    }

    func testCompletedDayCollapsesButEmptyDayStaysExpanded() {
        let date = Date()
        let completedDay = TripDay(date: date, title: "完成", sortOrder: 0)
        let completedItem = ItineraryItem(title: "完成项", category: .note, startTime: date, endTime: date, sortOrder: 0)
        completedItem.isCompleted = true
        completedDay.items = [completedItem]
        let emptyDay = TripDay(date: date, title: "空白", sortOrder: 1)

        XCTAssertTrue(completedDay.shouldAutomaticallyCollapse(relativeTo: date))
        XCTAssertFalse(emptyDay.shouldAutomaticallyCollapse(relativeTo: date))
    }

    func testNextUnfinishedItemFollowsTripOrder() {
        let day = TripDay(date: Date(), title: "第一天", sortOrder: 0)
        let first = ItineraryItem(title: "已完成", category: .attraction, startTime: Date(), endTime: Date(), sortOrder: 0)
        let next = ItineraryItem(title: "下一个地点", category: .attraction, startTime: Date(), endTime: Date(), sortOrder: 1)
        first.isCompleted = true
        day.items = [next, first]

        let trip = Trip(title: "行程", destination: "杭州", startDate: Date(), endDate: Date())
        trip.days = [day]

        XCTAssertEqual(trip.nextUnfinishedItem?.id, next.id)
    }

    func testChangingTripStartShiftsEndDateDaysAndItemTimesTogether() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let oldStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
        let oldEnd = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let newStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let firstDay = TripDay(date: oldStart, title: "第 1 天", sortOrder: 0)
        let secondDate = calendar.date(byAdding: .day, value: 1, to: oldStart)!
        let secondDay = TripDay(date: secondDate, title: "第 2 天", sortOrder: 1)
        let itemStart = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: secondDate)!
        let itemEnd = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: secondDate)!
        let item = ItineraryItem(
            title: "园林",
            category: .attraction,
            startTime: itemStart,
            endTime: itemEnd,
            sortOrder: 0
        )
        secondDay.items = [item]
        let trip = Trip(title: "苏州三日游", destination: "苏州", startDate: oldStart, endDate: oldEnd)
        trip.days = [secondDay, firstDay]

        let shiftedEnd = JourneyHierarchyService.shiftedDate(
            oldEnd,
            whenTripStartMovesFrom: oldStart,
            to: newStart,
            calendar: calendar
        )
        JourneyHierarchyService.shiftTripScheduleDates(
            trip,
            from: oldStart,
            to: newStart,
            calendar: calendar
        )

        XCTAssertEqual(shiftedEnd, calendar.date(from: DateComponents(year: 2026, month: 9, day: 7)))
        XCTAssertEqual(trip.sortedDays.map { calendar.component(.day, from: $0.date) }, [5, 6])
        XCTAssertEqual(calendar.component(.day, from: item.startTime), 6)
        XCTAssertEqual(calendar.component(.hour, from: item.startTime), 9)
        XCTAssertEqual(calendar.component(.minute, from: item.startTime), 30)
        XCTAssertEqual(item.endTime.timeIntervalSince(item.startTime), itemEnd.timeIntervalSince(itemStart))
    }

    func testTwoTapDateRangeSelectsStartThenEndAndRejectsEarlierEnd() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let existingStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
        let existingEnd = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let newStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let invalidEnd = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4))!
        let newEnd = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        var draft = DateRangeDraft(startDate: existingStart, endDate: existingEnd)

        draft.select(newStart, calendar: calendar)
        XCTAssertEqual(draft.startDate, newStart)
        XCTAssertNil(draft.endDate)
        XCTAssertEqual(draft.phase, .end)

        draft.select(invalidEnd, calendar: calendar)
        XCTAssertNil(draft.endDate)
        XCTAssertEqual(draft.phase, .end)

        draft.select(newEnd, calendar: calendar)
        XCTAssertEqual(draft.endDate, newEnd)
        XCTAssertEqual(draft.phase, .complete)

        draft.reset()
        XCTAssertNil(draft.startDate)
        XCTAssertNil(draft.endDate)
        XCTAssertEqual(draft.phase, .start)
    }

    func testApplyingRangeDayCanPreserveExistingTimeOfDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let original = calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 30,
            hour: 9,
            minute: 35
        ))!
        let selectedDay = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!

        let result = DateRangeDateService.applyingDay(
            selectedDay,
            to: original,
            preservingTime: true,
            calendar: calendar
        )

        XCTAssertEqual(calendar.component(.day, from: result), 5)
        XCTAssertEqual(calendar.component(.hour, from: result), 9)
        XCTAssertEqual(calendar.component(.minute, from: result), 35)
    }

    func testUpdatingTripDateRangeAlignsExistingDaysAndItemTimesToNewStart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let displayedStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))!
        let staleDayDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
        let newStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let newEnd = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        let itemStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: staleDayDate)!
        let item = ItineraryItem(
            title: "园林",
            category: .attraction,
            startTime: itemStart,
            endTime: itemStart.addingTimeInterval(3_600),
            sortOrder: 0
        )
        let day = TripDay(date: staleDayDate, title: "第 1 天", sortOrder: 0)
        day.items = [item]
        let trip = Trip(
            title: "苏州",
            destination: "苏州",
            startDate: displayedStart,
            endDate: displayedStart
        )
        trip.days = [day]

        JourneyHierarchyService.updateTripDateRange(
            trip,
            startDate: newStart,
            endDate: newEnd,
            calendar: calendar
        )

        XCTAssertEqual(trip.startDate, newStart)
        XCTAssertEqual(trip.endDate, newStart)
        XCTAssertEqual(day.date, newStart)
        XCTAssertEqual(calendar.component(.day, from: item.startTime), 5)
        XCTAssertEqual(calendar.component(.hour, from: item.startTime), 9)
    }

    func testUpdatingTripDateRangeImmediatelyRefreshesAutomaticExecutionStatus() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let pastStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let futureStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8))!
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 12))!
        let itemStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: pastStart)!
        let item = ItineraryItem(
            title: "康定至泸定桥",
            category: .transport,
            startTime: itemStart,
            endTime: itemStart.addingTimeInterval(3_600),
            sortOrder: 0
        )
        let day = TripDay(date: pastStart, title: "第 1 天", sortOrder: 0)
        day.items = [item]
        let trip = Trip(
            title: "川西旅程",
            destination: "川西",
            startDate: pastStart,
            endDate: pastStart
        )
        trip.days = [day]

        XCTAssertTrue(item.completeIfElapsed(relativeTo: referenceDate))
        XCTAssertEqual(item.executionStatus, .completed)

        JourneyHierarchyService.updateTripDateRange(
            trip,
            startDate: futureStart,
            endDate: futureStart,
            calendar: calendar,
            relativeTo: referenceDate
        )

        XCTAssertEqual(day.date, futureStart)
        XCTAssertEqual(calendar.component(.day, from: item.startTime), 8)
        XCTAssertEqual(item.executionStatus, .notStarted)
        XCTAssertFalse(item.isCompleted)
    }

    func testNormalizeTripDayScheduleRepairsDateGapsAndRebasesItemTimes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let august25 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        let august26 = calendar.date(byAdding: .day, value: 1, to: august25)!
        let september2 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2))!
        let expectedThirdDate = calendar.date(byAdding: .day, value: 2, to: august25)!
        let itemStart = calendar.date(bySettingHour: 21, minute: 39, second: 0, of: september2)!
        let item = ItineraryItem(
            title: "湖畔自由漫步",
            category: .attraction,
            startTime: itemStart,
            endTime: itemStart.addingTimeInterval(5_400),
            sortOrder: 0
        )
        let firstDay = TripDay(date: august25, title: "第 1 天", sortOrder: 0)
        let secondDay = TripDay(date: august26, title: "西湖一日", sortOrder: 1)
        let thirdDay = TripDay(date: september2, title: "第 3 天", sortOrder: 2)
        thirdDay.items = [item]
        let trip = Trip(
            title: "杭州",
            destination: "杭州",
            startDate: august25,
            endDate: september2
        )
        trip.days = [thirdDay, firstDay, secondDay]

        XCTAssertTrue(JourneyHierarchyService.normalizeTripDaySchedule(trip, calendar: calendar))
        XCTAssertEqual(trip.sortedDays.map(\.date), [august25, august26, expectedThirdDate])
        XCTAssertEqual(trip.sortedDays.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(trip.endDate, expectedThirdDate)
        XCTAssertEqual(calendar.component(.day, from: item.startTime), 27)
        XCTAssertEqual(calendar.component(.hour, from: item.startTime), 21)
        XCTAssertEqual(calendar.component(.minute, from: item.startTime), 39)
        XCTAssertEqual(item.endTime.timeIntervalSince(item.startTime), 5_400)
        XCTAssertFalse(JourneyHierarchyService.normalizeTripDaySchedule(trip, calendar: calendar))
    }

    func testNormalizeTripDayScheduleClosesGapAfterDeletingMiddleDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        let secondDate = calendar.date(byAdding: .day, value: 1, to: start)!
        let thirdDate = calendar.date(byAdding: .day, value: 2, to: start)!
        let firstDay = TripDay(date: start, title: "第 1 天", sortOrder: 0)
        let secondDay = TripDay(date: secondDate, title: "第 2 天", sortOrder: 1)
        let thirdDay = TripDay(date: thirdDate, title: "第 3 天", sortOrder: 2)
        let itemStart = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: thirdDate)!
        let item = ItineraryItem(
            title: "龙井村",
            category: .attraction,
            startTime: itemStart,
            endTime: itemStart.addingTimeInterval(3_600),
            sortOrder: 0
        )
        thirdDay.items = [item]
        let trip = Trip(title: "杭州", destination: "杭州", startDate: start, endDate: thirdDate)
        trip.days = [firstDay, secondDay, thirdDay]

        trip.days.removeAll { $0.id == secondDay.id }
        JourneyHierarchyService.normalizeTripDaySchedule(trip, calendar: calendar)

        XCTAssertEqual(trip.sortedDays.map(\.id), [firstDay.id, thirdDay.id])
        XCTAssertEqual(trip.sortedDays.map(\.date), [start, secondDate])
        XCTAssertEqual(trip.sortedDays.map(\.title), ["第 1 天", "第 2 天"])
        XCTAssertEqual(trip.endDate, secondDate)
        XCTAssertTrue(calendar.isDate(item.startTime, inSameDayAs: secondDate))
        XCTAssertEqual(calendar.component(.hour, from: item.startTime), 14)
    }

    func testTripTimelineOrderingPrioritizesCurrentThenUpcomingThenHistory() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today)!
        }

        let olderHistory = Trip(title: "较早历史", destination: "", startDate: day(-20), endDate: day(-18))
        let recentHistory = Trip(title: "最近历史", destination: "", startDate: day(-5), endDate: day(-3))
        let laterUpcoming = Trip(title: "稍后出发", destination: "", startDate: day(10), endDate: day(12))
        let nextUpcoming = Trip(title: "马上出发", destination: "", startDate: day(2), endDate: day(4))
        let current = Trip(title: "正在进行", destination: "", startDate: day(-1), endDate: day(1))

        let result = TripTimelineOrdering.sorted(
            [olderHistory, laterUpcoming, recentHistory, nextUpcoming, current],
            relativeTo: today,
            calendar: calendar
        )

        XCTAssertEqual(result.map(\.title), ["正在进行", "马上出发", "稍后出发", "最近历史", "较早历史"])
        XCTAssertEqual(TripTimelineOrdering.featured(in: result, relativeTo: today, calendar: calendar)?.title, "正在进行")
    }

    func testTripTimelineOrderingUsesNearestUpcomingWhenThereIsNoCurrentTrip() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
        let history = Trip(
            title: "历史行程",
            destination: "",
            startDate: calendar.date(byAdding: .day, value: -4, to: today)!,
            endDate: calendar.date(byAdding: .day, value: -2, to: today)!
        )
        let next = Trip(
            title: "下一个行程",
            destination: "",
            startDate: calendar.date(byAdding: .day, value: 1, to: today)!,
            endDate: calendar.date(byAdding: .day, value: 2, to: today)!
        )

        XCTAssertEqual(
            TripTimelineOrdering.featured(in: [history, next], relativeTo: today, calendar: calendar)?.title,
            "下一个行程"
        )
    }

    func testTripDayDisplayItemsPlacesCompletedItemsLastAndPreservesGroupOrder() {
        let date = Date()
        let day = TripDay(date: date, title: "第一天", sortOrder: 0)
        let completedFirst = ItineraryItem(title: "已完成早餐", category: .restaurant, startTime: date, endTime: date, sortOrder: 0)
        completedFirst.isCompleted = true
        let unfinishedFirst = ItineraryItem(title: "未完成景点", category: .attraction, startTime: date, endTime: date, sortOrder: 1)
        let completedSecond = ItineraryItem(title: "已完成午餐", category: .restaurant, startTime: date, endTime: date, sortOrder: 2)
        completedSecond.isCompleted = true
        let unfinishedSecond = ItineraryItem(title: "未完成散步", category: .note, startTime: date, endTime: date, sortOrder: 3)
        day.items = [completedSecond, unfinishedSecond, completedFirst, unfinishedFirst]

        XCTAssertEqual(
            day.displayItems.map(\.title),
            ["未完成景点", "未完成散步", "已完成早餐", "已完成午餐"]
        )
        XCTAssertEqual(day.sortedItems.map(\.title), ["已完成早餐", "未完成景点", "已完成午餐", "未完成散步"])
    }

    func testTripCalendarProgressUsesInclusiveTravelDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4))!
        let trip = Trip(title: "七日行程", destination: "杭州", startDate: start, endDate: end)

        let current = TripCalendarProgress.make(
            for: trip,
            relativeTo: calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!,
            calendar: calendar
        )
        XCTAssertEqual(current, TripCalendarProgress(currentDay: 2, totalDays: 7, phase: .current))
        XCTAssertEqual(current.fraction, 2.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(current.statusText, "第 2 天")

        let upcoming = TripCalendarProgress.make(
            for: trip,
            relativeTo: calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!,
            calendar: calendar
        )
        XCTAssertEqual(upcoming, TripCalendarProgress(currentDay: 0, totalDays: 7, phase: .upcoming))

        let history = TripCalendarProgress.make(
            for: trip,
            relativeTo: calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!,
            calendar: calendar
        )
        XCTAssertEqual(history, TripCalendarProgress(currentDay: 7, totalDays: 7, phase: .history))
    }

    func testMoveTripDayScheduleBeforeFirstKeepsTripStartAndReassignsConsecutiveDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        let secondDate = calendar.date(byAdding: .day, value: 1, to: firstDate)!
        let thirdDate = calendar.date(byAdding: .day, value: 2, to: firstDate)!
        let firstDay = TripDay(date: firstDate, title: "抵达杭州", sortOrder: 0)
        let secondDay = TripDay(date: secondDate, title: "第 2 天", sortOrder: 1)
        let thirdDay = TripDay(date: thirdDate, title: "茶园与返程", sortOrder: 2)
        let itemStart = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: thirdDate)!
        let item = ItineraryItem(
            title: "龙井村茶园",
            category: .attraction,
            startTime: itemStart,
            endTime: itemStart.addingTimeInterval(7_200),
            sortOrder: 0
        )
        thirdDay.items = [item]

        XCTAssertTrue(
            JourneyHierarchyService.moveTripDaySchedule(
                id: thirdDay.id,
                to: firstDay.id,
                in: [secondDay, thirdDay, firstDay],
                calendar: calendar
            )
        )

        let reordered = JourneyHierarchyService.sortedDays([firstDay, secondDay, thirdDay])
        XCTAssertEqual(reordered.map(\.title), ["茶园与返程", "抵达杭州", "第 3 天"])
        XCTAssertEqual(reordered.map(\.date), [firstDate, secondDate, thirdDate])
        XCTAssertEqual(reordered.map(\.sortOrder), [0, 1, 2])
        XCTAssertTrue(calendar.isDate(item.startTime, inSameDayAs: firstDate))
        XCTAssertEqual(calendar.component(.hour, from: item.startTime), 9)
        XCTAssertEqual(calendar.component(.minute, from: item.startTime), 30)
        XCTAssertEqual(item.endTime.timeIntervalSince(item.startTime), 7_200)
    }

    func testTripDayMoveUsesAvailableDateGapWithoutShiftingFollowingDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let september24 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        let september26 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26))!
        let september27 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!
        let september28 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        let firstDay = TripDay(date: september24, title: "9月24日", sortOrder: 0)
        let secondDay = TripDay(date: september26, title: "9月26日", sortOrder: 1)
        let thirdDay = TripDay(date: september27, title: "9月27日", sortOrder: 2)
        let insertedDay = TripDay(date: september28, title: "新增一天", sortOrder: 3)
        let days = [firstDay, secondDay, thirdDay, insertedDay]

        let plan = try XCTUnwrap(
            JourneyHierarchyService.tripDayScheduleMovePlan(
                id: insertedDay.id,
                to: secondDay.id,
                in: days,
                calendar: calendar
            )
        )

        XCTAssertFalse(plan.requiresFollowingShiftConfirmation)
        XCTAssertTrue(calendar.isDate(plan.movedDate, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: september24)!))
        XCTAssertTrue(
            JourneyHierarchyService.applyTripDayScheduleMovePlan(
                plan,
                in: days,
                shiftFollowingDays: false,
                calendar: calendar
            )
        )
        XCTAssertEqual(
            JourneyHierarchyService.sortedDays(days).map(\.id),
            [firstDay.id, insertedDay.id, secondDay.id, thirdDay.id]
        )
        XCTAssertTrue(calendar.isDate(secondDay.date, inSameDayAs: september26))
        XCTAssertTrue(calendar.isDate(thirdDay.date, inSameDayAs: september27))
    }

    func testTripDayMoveBetweenAdjacentDatesAlwaysReassignsConsecutiveDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let september24 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        let september25 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let september26 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26))!
        let september27 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!
        let firstDay = TripDay(date: september24, title: "9月24日", sortOrder: 0)
        let secondDay = TripDay(date: september25, title: "9月25日", sortOrder: 1)
        let thirdDay = TripDay(date: september26, title: "9月26日", sortOrder: 2)
        let insertedDay = TripDay(date: september27, title: "新增一天", sortOrder: 3)
        let days = [firstDay, secondDay, thirdDay, insertedDay]

        let plan = try XCTUnwrap(
            JourneyHierarchyService.tripDayScheduleMovePlan(
                id: insertedDay.id,
                to: secondDay.id,
                in: days,
                calendar: calendar
            )
        )

        XCTAssertFalse(plan.requiresFollowingShiftConfirmation)
        XCTAssertTrue(plan.followingDayIDsToShift.isEmpty)
        XCTAssertTrue(
            JourneyHierarchyService.applyTripDayScheduleMovePlan(
                plan,
                in: days,
                shiftFollowingDays: false,
                calendar: calendar
            )
        )
        XCTAssertEqual(
            JourneyHierarchyService.sortedDays(days).map(\.id),
            [firstDay.id, insertedDay.id, secondDay.id, thirdDay.id]
        )
        XCTAssertTrue(calendar.isDate(insertedDay.date, inSameDayAs: september25))
        XCTAssertTrue(calendar.isDate(secondDay.date, inSameDayAs: september26))
        XCTAssertTrue(calendar.isDate(thirdDay.date, inSameDayAs: september27))
    }

    func testDayDropCommitsLastPreviewDestinationAfterLiveCardsMove() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        let secondDate = calendar.date(byAdding: .day, value: 1, to: firstDate)!
        let thirdDate = calendar.date(byAdding: .day, value: 2, to: firstDate)!
        let firstDay = TripDay(date: firstDate, title: "西湖", sortOrder: 0)
        let secondDay = TripDay(date: secondDate, title: "灵隐寺", sortOrder: 1)
        let thirdDay = TripDay(date: thirdDate, title: "龙井村", sortOrder: 2)
        let days = [firstDay, secondDay, thirdDay]
        let originalDayIDs = days.map(\.id)

        XCTAssertTrue(
            JourneyHierarchyService.previewMoveTripDay(
                id: thirdDay.id,
                to: firstDay.id,
                in: days
            )
        )
        XCTAssertEqual(
            JourneyHierarchyService.sortedDays(days).map(\.id),
            [thirdDay.id, firstDay.id, secondDay.id]
        )

        // Live displacement can put the dragged card under the pointer at release.
        // Restore the original slots, then commit the last target the user actually saw.
        let daysByID = Dictionary(uniqueKeysWithValues: days.map { ($0.id, $0) })
        for (index, dayID) in originalDayIDs.enumerated() {
            daysByID[dayID]?.sortOrder = index
        }
        let committedDayID = resolvedTripDayDropDestination(
            lastPreviewDayID: firstDay.id,
            reportedDayID: thirdDay.id
        )

        XCTAssertEqual(committedDayID, firstDay.id)
        XCTAssertTrue(
            JourneyHierarchyService.moveTripDaySchedule(
                id: thirdDay.id,
                to: committedDayID,
                in: days,
                calendar: calendar
            )
        )
        XCTAssertEqual(
            JourneyHierarchyService.sortedDays(days).map(\.id),
            [thirdDay.id, firstDay.id, secondDay.id]
        )
        XCTAssertEqual(thirdDay.date, firstDate)
        XCTAssertEqual(firstDay.date, secondDate)
        XCTAssertEqual(secondDay.date, thirdDate)
    }

    func testDayDragBackToOriginalOrderIsTreatedAsUnchanged() {
        let date = Date()
        let firstDay = TripDay(date: date, title: "第一天", sortOrder: 0)
        let secondDay = TripDay(date: date.addingTimeInterval(86_400), title: "第二天", sortOrder: 1)
        let thirdDay = TripDay(date: date.addingTimeInterval(172_800), title: "第三天", sortOrder: 2)
        let days = [firstDay, secondDay, thirdDay]
        let originalDayIDs = days.map(\.id)

        XCTAssertTrue(
            JourneyHierarchyService.previewMoveTripDay(
                id: thirdDay.id,
                to: firstDay.id,
                in: days
            )
        )
        XCTAssertFalse(hasOriginalTripDayOrder(originalDayIDs, in: days))

        XCTAssertTrue(
            JourneyHierarchyService.previewMoveTripDay(
                id: thirdDay.id,
                to: secondDay.id,
                in: days
            )
        )
        XCTAssertEqual(JourneyHierarchyService.sortedDays(days).map(\.id), originalDayIDs)
        XCTAssertTrue(hasOriginalTripDayOrder(originalDayIDs, in: days))
    }

    func testDragPreviewReordersWithoutChangingStoredTimes() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
        let eleven = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: date)!
        let fourteen = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: date)!
        let day = TripDay(date: date, title: "第一天", sortOrder: 0)
        let first = ItineraryItem(title: "东方明珠", category: .attraction, startTime: nine, endTime: nine.addingTimeInterval(3600), sortOrder: 0)
        let second = ItineraryItem(title: "上海滩", category: .attraction, startTime: eleven, endTime: eleven.addingTimeInterval(7200), sortOrder: 1)
        let third = ItineraryItem(title: "豫园", category: .attraction, startTime: fourteen, endTime: fourteen.addingTimeInterval(3600), sortOrder: 2)
        day.items = [first, second, third]

        XCTAssertTrue(
            JourneyHierarchyService.previewMoveItineraryItem(
                id: first.id,
                to: third.id,
                in: [day]
            )
        )

        XCTAssertEqual(day.sortedItems.map(\.title), ["上海滩", "豫园", "东方明珠"])
        XCTAssertEqual(first.startTime, nine)
        XCTAssertEqual(second.startTime, eleven)
        XCTAssertEqual(third.startTime, fourteen)
    }

    func testDropCommitsLastPreviewDestinationWhenLiveReorderingMovesDropView() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
        let eleven = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: date)!
        let day = TripDay(date: date, title: "第一天", sortOrder: 0)
        let first = ItineraryItem(
            title: "东方明珠",
            category: .attraction,
            startTime: nine,
            endTime: nine.addingTimeInterval(3600),
            sortOrder: 0
        )
        let second = ItineraryItem(
            title: "上海滩",
            category: .attraction,
            startTime: eleven,
            endTime: eleven.addingTimeInterval(3600),
            sortOrder: 1
        )
        day.items = [first, second]

        XCTAssertTrue(
            JourneyHierarchyService.previewMoveItineraryItem(
                id: first.id,
                to: second.id,
                in: [day]
            )
        )
        XCTAssertEqual(day.sortedItems.map(\.id), [second.id, first.id])

        // The live swap places the dragged card under the pointer, so SwiftUI can report
        // `first` as the final drop view. Restoring and committing the last valid preview
        // target must still preserve the order shown to the user.
        first.sortOrder = 0
        second.sortOrder = 1
        let lastPreviewDestination = ItineraryDropDestination.item(second.id)
        let reportedDestination = ItineraryDropDestination.item(first.id)
        let committedDestination = resolvedItineraryDropDestination(
            lastPreview: lastPreviewDestination,
            reported: reportedDestination
        )

        guard case let .item(targetID) = committedDestination else {
            return XCTFail("Expected an item drop destination")
        }
        XCTAssertNotEqual(committedDestination, reportedDestination)
        let result = JourneyHierarchyService.moveItineraryItemResult(
            id: first.id,
            to: targetID,
            in: [day],
            calendar: calendar
        )

        XCTAssertTrue(result.didMove)
        XCTAssertEqual(day.sortedItems.map(\.id), [second.id, first.id])
    }

    func testItineraryDragBackToOriginalOrderIsTreatedAsUnchanged() {
        let date = Date()
        let day = TripDay(date: date, title: "第一天", sortOrder: 0)
        let first = ItineraryItem(
            title: "第一站",
            category: .attraction,
            startTime: date,
            endTime: date.addingTimeInterval(3_600),
            sortOrder: 0
        )
        let second = ItineraryItem(
            title: "第二站",
            category: .attraction,
            startTime: date.addingTimeInterval(3_600),
            endTime: date.addingTimeInterval(7_200),
            sortOrder: 1
        )
        let third = ItineraryItem(
            title: "第三站",
            category: .attraction,
            startTime: date.addingTimeInterval(7_200),
            endTime: date.addingTimeInterval(10_800),
            sortOrder: 2
        )
        day.items = [first, second, third]
        let originalItemsByDay = [day.id: day.sortedItems.map(\.id)]

        XCTAssertTrue(
            JourneyHierarchyService.previewMoveItineraryItem(
                id: first.id,
                to: third.id,
                in: [day]
            )
        )
        XCTAssertFalse(hasOriginalItineraryOrder(originalItemsByDay, in: [day]))

        XCTAssertTrue(
            JourneyHierarchyService.previewMoveItineraryItem(
                id: first.id,
                to: second.id,
                in: [day]
            )
        )
        XCTAssertEqual(day.sortedItems.map(\.id), originalItemsByDay[day.id])
        XCTAssertTrue(hasOriginalItineraryOrder(originalItemsByDay, in: [day]))
    }

    func testAppendingDayKeepsTripRangeAlignedWithConsecutiveDayCards() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6))!
        let originalEnd = calendar.date(byAdding: .day, value: 2, to: start)!
        let trip = Trip(title: "三日旅程", destination: "上海", startDate: start, endDate: originalEnd)
        trip.days = [TripDay(date: start, title: "第 1 天", sortOrder: 0)]

        let secondDay = JourneyHierarchyService.appendDay(to: trip, calendar: calendar)
        XCTAssertEqual(secondDay.date, calendar.date(byAdding: .day, value: 1, to: start))
        XCTAssertEqual(trip.endDate, secondDay.date)

        let thirdDay = JourneyHierarchyService.appendDay(to: trip, calendar: calendar)
        XCTAssertEqual(thirdDay.date, originalEnd)
        XCTAssertEqual(trip.endDate, originalEnd)

        let extraDay = JourneyHierarchyService.appendDay(to: trip, calendar: calendar)
        let extendedEnd = calendar.date(byAdding: .day, value: 3, to: start)!
        XCTAssertEqual(extraDay.date, extendedEnd)
        XCTAssertEqual(trip.endDate, extendedEnd)
    }

    func testAppendingDayRepairsExistingGapBeforeChoosingNextDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        let september2 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2))!
        let trip = Trip(title: "杭州", destination: "杭州", startDate: start, endDate: september2)
        trip.days = [
            TripDay(date: start, title: "第 1 天", sortOrder: 0),
            TripDay(date: september2, title: "第 2 天", sortOrder: 1)
        ]

        let newDay = JourneyHierarchyService.appendDay(to: trip, calendar: calendar)

        let expectedDates = (0..<3).map { calendar.date(byAdding: .day, value: $0, to: start)! }
        XCTAssertEqual(trip.sortedDays.map(\.date), expectedDates)
        XCTAssertEqual(newDay.date, expectedDates[2])
        XCTAssertEqual(trip.endDate, expectedDates[2])
    }

    func testDraggingEqualDurationItemsReordersAndExchangesTimeSlots() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
        let eleven = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: date)!
        let fourteen = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: date)!
        let day = TripDay(date: date, title: "第一天", sortOrder: 0)
        let first = ItineraryItem(title: "东方明珠", category: .attraction, startTime: nine, endTime: nine.addingTimeInterval(3600), sortOrder: 0)
        let second = ItineraryItem(title: "上海滩", category: .attraction, startTime: eleven, endTime: eleven.addingTimeInterval(3600), sortOrder: 1)
        let third = ItineraryItem(title: "豫园", category: .attraction, startTime: fourteen, endTime: fourteen.addingTimeInterval(3600), sortOrder: 2)
        day.items = [third, first, second]

        let result = JourneyHierarchyService.moveItineraryItemResult(
            id: first.id,
            to: third.id,
            in: [day],
            calendar: calendar
        )

        XCTAssertTrue(result.didMove)
        XCTAssertTrue(result.timeAdjustments.isEmpty)
        XCTAssertEqual(day.sortedItems.map(\.title), ["上海滩", "豫园", "东方明珠"])
        XCTAssertEqual(day.sortedItems.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(day.sortedItems.map { calendar.component(.hour, from: $0.startTime) }, [9, 11, 14])
        XCTAssertEqual(day.sortedItems.map { $0.endTime.timeIntervalSince($0.startTime) }, [3600, 3600, 3600])
    }

    func testDraggingUnequalDurationItemsRequestsTimeReviewForBothItems() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
        let eleven = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: date)!
        let day = TripDay(date: date, title: "第一天", sortOrder: 0)
        let first = ItineraryItem(title: "东方明珠", category: .attraction, startTime: nine, endTime: nine.addingTimeInterval(3600), sortOrder: 0)
        let second = ItineraryItem(title: "上海滩", category: .attraction, startTime: eleven, endTime: eleven.addingTimeInterval(7200), sortOrder: 1)
        day.items = [first, second]

        let result = JourneyHierarchyService.moveItineraryItemResult(
            id: first.id,
            to: second.id,
            in: [day],
            calendar: calendar
        )

        XCTAssertTrue(result.didMove)
        XCTAssertEqual(day.sortedItems.map(\.title), ["上海滩", "东方明珠"])
        XCTAssertEqual(result.timeAdjustments.map(\.item.id), [second.id, first.id])
        XCTAssertEqual(result.timeAdjustments.map { calendar.component(.hour, from: $0.suggestedStartTime) }, [9, 11])
        XCTAssertEqual(result.timeAdjustments.map { calendar.component(.hour, from: $0.suggestedEndTime) }, [10, 13])
        XCTAssertEqual(second.startTime, eleven)
        XCTAssertEqual(first.startTime, nine)
    }

    func testTimeReviewDoesNotTreatReverseCardOrderAsOverlap() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6))!
        let morningStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date)!
        let morningEnd = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
        let eveningStart = calendar.date(bySettingHour: 18, minute: 30, second: 0, of: date)!
        let eveningEnd = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: date)!

        XCTAssertFalse(hasOverlappingItineraryTimeRanges([
            (start: eveningStart, end: eveningEnd),
            (start: morningStart, end: morningEnd)
        ]))
        XCTAssertTrue(hasOverlappingItineraryTimeRanges([
            (start: morningStart, end: eveningStart),
            (start: morningEnd, end: eveningEnd)
        ]))
    }

    func testDraggingItineraryItemToAnotherDayMovesItAndPreservesTime() {
        let calendar = Calendar(identifier: .gregorian)
        let firstDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        let secondDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
        let start = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: firstDate)!
        let end = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: firstDate)!
        let sourceDay = TripDay(date: firstDate, title: "第一天", sortOrder: 0)
        let targetDay = TripDay(date: secondDate, title: "第二天", sortOrder: 1)
        let moving = ItineraryItem(title: "东方明珠", category: .attraction, startTime: start, endTime: end, sortOrder: 0)
        let targetStart = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: secondDate)!
        let target = ItineraryItem(title: "豫园", category: .attraction, startTime: targetStart, endTime: targetStart.addingTimeInterval(3600), sortOrder: 0)
        moving.day = sourceDay
        target.day = targetDay
        sourceDay.items = [moving]
        targetDay.items = [target]

        let result = JourneyHierarchyService.moveItineraryItemResult(
            id: moving.id,
            to: target.id,
            in: [sourceDay, targetDay],
            calendar: calendar
        )

        XCTAssertTrue(result.didMove)
        XCTAssertTrue(result.timeAdjustments.isEmpty)
        XCTAssertTrue(sourceDay.items.isEmpty)
        XCTAssertEqual(targetDay.sortedItems.map(\.title), ["东方明珠", "豫园"])
        XCTAssertEqual(moving.day?.id, targetDay.id)
        XCTAssertTrue(calendar.isDate(moving.startTime, inSameDayAs: secondDate))
        XCTAssertEqual(calendar.component(.hour, from: moving.startTime), 9)
        XCTAssertEqual(calendar.component(.minute, from: moving.startTime), 30)
        XCTAssertEqual(moving.endTime.timeIntervalSince(moving.startTime), 90 * 60, accuracy: 0.1)
    }

    func testDraggingUnequalDurationItemAcrossDaysRequestsReviewOnTargetDay() {
        let calendar = Calendar(identifier: .gregorian)
        let firstDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        let secondDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
        let sourceDay = TripDay(date: firstDate, title: "第一天", sortOrder: 0)
        let targetDay = TripDay(date: secondDate, title: "第二天", sortOrder: 1)
        let movingStart = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: firstDate)!
        let targetStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: secondDate)!
        let moving = ItineraryItem(title: "东方明珠", category: .attraction, startTime: movingStart, endTime: movingStart.addingTimeInterval(3600), sortOrder: 0)
        let target = ItineraryItem(title: "豫园", category: .attraction, startTime: targetStart, endTime: targetStart.addingTimeInterval(7200), sortOrder: 0)
        moving.day = sourceDay
        target.day = targetDay
        sourceDay.items = [moving]
        targetDay.items = [target]

        let result = JourneyHierarchyService.moveItineraryItemResult(
            id: moving.id,
            to: target.id,
            in: [sourceDay, targetDay],
            calendar: calendar
        )

        XCTAssertTrue(result.didMove)
        XCTAssertEqual(result.timeAdjustments.map(\.item.id), [moving.id, target.id])
        XCTAssertTrue(result.timeAdjustments.allSatisfy {
            calendar.isDate($0.suggestedStartTime, inSameDayAs: secondDate) &&
            calendar.isDate($0.suggestedEndTime, inSameDayAs: secondDate)
        })
        XCTAssertEqual(result.timeAdjustments.map { calendar.component(.hour, from: $0.suggestedStartTime) }, [9, 16])
        XCTAssertEqual(result.timeAdjustments.map { calendar.component(.hour, from: $0.suggestedEndTime) }, [11, 17])
    }

    func testAllMediaFollowsEntryAndMediaSortOrder() {
        let story = TravelStory(
            title: "苏州上海三日游",
            destination: "苏州、上海",
            startDate: Date(),
            endDate: Date(),
            summary: ""
        )

        let firstEntry = StoryEntry(title: "拙政园", category: .attraction, sortOrder: 0)
        let secondEntry = StoryEntry(title: "外滩", category: .attraction, sortOrder: 1)
        let firstPhoto = MediaReference(localIdentifier: "first", kind: .image, sortOrder: 0)
        let secondPhoto = MediaReference(localIdentifier: "second", kind: .image, sortOrder: 1)
        let thirdPhoto = MediaReference(localIdentifier: "third", kind: .image, sortOrder: 0)

        firstEntry.media = [secondPhoto, firstPhoto]
        secondEntry.media = [thirdPhoto]
        story.entries = [secondEntry, firstEntry]

        XCTAssertEqual(story.allMedia.map(\.localIdentifier), ["first", "second", "third"])
    }

    func testArchivingSameTripMergesIntoOneFootprintHierarchy() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let start = Date()
        let trip = Trip(title: "苏州两日", destination: "苏州", startDate: start, endDate: start)
        let day = TripDay(date: start, title: "园林与老城", sortOrder: 0, trip: trip)
        let first = ItineraryItem(title: "拙政园", category: .attraction, startTime: start, endTime: start, sortOrder: 0)
        let second = ItineraryItem(title: "平江路", category: .attraction, startTime: start, endTime: start, sortOrder: 1)
        first.address = "东北街178号"
        first.note = "提前十分钟到入口。"
        first.transport = .walk
        first.distanceText = "1.2 公里 · 18 分钟"
        first.cost = 80
        first.day = day
        second.day = day
        day.items = [first, second]
        trip.days = [day]
        context.insert(trip)

        let firstArchive = try StoryArchiveService.archive(
            trip: trip,
            selectedItems: [first],
            syncScope: .item,
            sourceIDs: [first.id],
            summary: "",
            modelContext: context
        )
        let secondArchive = try StoryArchiveService.archive(
            trip: trip,
            selectedItems: [second],
            syncScope: .item,
            sourceIDs: [second.id],
            summary: "",
            modelContext: context
        )
        _ = try StoryArchiveService.archive(
            trip: trip,
            selectedItems: [first],
            syncScope: .item,
            sourceIDs: [first.id],
            summary: "",
            modelContext: context
        )
        try context.save()

        let stories = try context.fetch(FetchDescriptor<TravelStory>())
        XCTAssertEqual(stories.count, 1)
        XCTAssertEqual(firstArchive.story.id, secondArchive.story.id)
        XCTAssertEqual(stories[0].sortedDays.count, 1)
        XCTAssertEqual(stories[0].sortedEntries.map(\.title), ["拙政园", "平江路"])
        let archivedEntry = stories[0].sortedEntries[0]
        XCTAssertEqual(archivedEntry.address, "")
        XCTAssertEqual(archivedEntry.supplementalInfo, "")
        XCTAssertEqual(archivedEntry.transport, .car)
        XCTAssertEqual(archivedEntry.distanceText, "")
        XCTAssertEqual(archivedEntry.cost, 0)
        XCTAssertEqual(archivedEntry.startTime, first.startTime)
        XCTAssertEqual(archivedEntry.endTime, first.endTime)
        XCTAssertEqual(archivedEntry.timeLabel, "\(first.startTime.timeText)～\(first.endTime.timeText)")
        XCTAssertEqual(archivedEntry.note, "")
        XCTAssertEqual(
            archivedEntry.sourceMemoryPrefill,
            "类型：景点；地点：拙政园；地址：东北街178号；步行前往，路程 1.2 公里 · 18 分钟；花费：¥80；补充：提前十分钟到入口。"
        )
        XCTAssertEqual(stories[0].syncScope, .item)
        XCTAssertEqual(stories[0].sourceSelectionIDs, [first.id, second.id])
    }

    func testWholeTripArchiveKeepsEmptyDaysInFootprintSkeleton() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let start = Date()
        let trip = Trip(title: "空白日测试", destination: "厦门", startDate: start, endDate: start)
        let emptyDay = TripDay(date: start, title: "自由活动", sortOrder: 0, trip: trip)
        trip.days = [emptyDay]
        context.insert(trip)

        let result = try StoryArchiveService.archive(
            trip: trip,
            selectedItems: trip.allItems,
            syncScope: .trip,
            sourceIDs: [],
            summary: "",
            modelContext: context
        )

        XCTAssertEqual(result.story.sortedDays.count, 1)
        XCTAssertEqual(result.story.sortedDays.first?.title, "自由活动")
        XCTAssertTrue(result.story.sortedEntries.isEmpty)
    }

    func testIndependentFootprintCreationBuildsDateHierarchyWithoutSourceTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 3))!

        let story = FootprintCreationService.create(
            title: "  海边三日  ",
            destination: " 厦门 ",
            startDate: start,
            endDate: end,
            summary: "",
            modelContext: context
        )

        XCTAssertEqual(story.title, "海边三日")
        XCTAssertEqual(story.destination, "厦门")
        XCTAssertNil(story.sourceTripID)
        XCTAssertEqual(story.sortedDays.map(\.title), ["第 1 天", "第 2 天", "第 3 天"])
        XCTAssertTrue(story.sortedEntries.isEmpty)
    }

    func testArchiveReselectionReplacesExistingFullTripSyncScope() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let start = Date()
        let trip = Trip(title: "级联选择", destination: "北京", startDate: start, endDate: start)
        let day = TripDay(date: start, title: "第一天", sortOrder: 0, trip: trip)
        let first = ItineraryItem(title: "故宫", category: .attraction, startTime: start, endTime: start, sortOrder: 0)
        let second = ItineraryItem(title: "景山", category: .attraction, startTime: start, endTime: start, sortOrder: 1)
        first.day = day
        second.day = day
        day.items = [first, second]
        trip.days = [day]
        context.insert(trip)

        let initial = try StoryArchiveService.archive(
            trip: trip,
            selectedItems: trip.allItems,
            syncScope: .trip,
            sourceIDs: [],
            summary: "",
            modelContext: context
        )
        _ = try StoryArchiveService.archive(
            trip: trip,
            selectedItems: [first],
            syncScope: .item,
            sourceIDs: [first.id],
            summary: "",
            replacesSyncSelection: true,
            modelContext: context
        )

        XCTAssertEqual(initial.story.syncScope, .item)
        XCTAssertEqual(initial.story.sourceSelectionIDs, [first.id])
        XCTAssertEqual(initial.story.sortedEntries.map(\.title), ["故宫"])
    }

    func testSyncAddsLatestDaySkeletonWithoutOverwritingFootprintContent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let start = Date()
        let trip = Trip(title: "杭州周末", destination: "杭州", startDate: start, endDate: start)
        let day = TripDay(date: start, title: "西湖一天", sortOrder: 0, trip: trip)
        let first = ItineraryItem(title: "西湖", category: .attraction, startTime: start, endTime: start, sortOrder: 0)
        first.day = day
        day.items = [first]
        trip.days = [day]
        context.insert(trip)

        let result = try StoryArchiveService.archive(
            trip: trip,
            selectedItems: [first],
            syncScope: .day,
            sourceIDs: [day.id],
            summary: "",
            modelContext: context
        )
        let savedEntry = try XCTUnwrap(result.story.sortedEntries.first)
        let savedDay = try XCTUnwrap(result.story.sortedDays.first)
        savedDay.note = "西湖边的一天"
        savedDay.details = "上午沿着北山街散步，傍晚在断桥看落日。"
        savedEntry.note = "傍晚的风很好"
        savedEntry.address = "用户补充的实际入口"
        savedEntry.routeInfo = "实际步行 4 公里"
        let photo = MediaReference(localIdentifier: "user-photo", kind: .image)
        photo.storyEntry = savedEntry
        savedEntry.media.append(photo)

        first.title = "西湖断桥"
        first.address = "北山街入口"
        first.note = "带好雨伞"
        first.transport = .walk
        first.distanceText = "2.6 公里 · 35 分钟"
        first.cost = 20
        let second = ItineraryItem(title: "雷峰塔", category: .attraction, startTime: start, endTime: start, sortOrder: 1)
        second.day = day
        day.items.append(second)

        _ = StorySyncService.sync(story: result.story, from: trip, modelContext: context)

        XCTAssertEqual(result.story.sortedEntries.map(\.title), ["西湖断桥", "雷峰塔"])
        XCTAssertEqual(savedEntry.note, "傍晚的风很好")
        XCTAssertEqual(savedEntry.address, "")
        XCTAssertEqual(savedEntry.supplementalInfo, "")
        XCTAssertEqual(savedEntry.transport, .car)
        XCTAssertEqual(savedEntry.routeInfo, "")
        XCTAssertEqual(savedEntry.cost, 0)
        XCTAssertEqual(result.story.sortedEntries[1].note, "")
        XCTAssertEqual(
            result.story.sortedEntries[1].sourceMemoryPrefill,
            "类型：景点；地点：雷峰塔；前往方式：驾车。"
        )
        XCTAssertEqual(savedEntry.media.map(\.localIdentifier), ["user-photo"])
        XCTAssertEqual(savedDay.note, "西湖边的一天")
        XCTAssertEqual(savedDay.details, "上午沿着北山街散步，傍晚在断桥看落日。")
    }

    func testLegacyInlineEntryNoteMigratesToDaySummaryOnlyOnce() {
        let story = TravelStory(
            title: "上海一日",
            destination: "上海",
            startDate: Date(),
            endDate: Date(),
            summary: ""
        )
        let day = StoryDay(date: Date(), title: "8月29日", sortOrder: 0, story: story)
        let entry = StoryEntry(title: "东方明珠", category: .attraction, sortOrder: 0)
        day.didMigrateInlineSummary = false
        entry.note = "旧版外层填写的摘要"
        entry.story = story
        entry.storyDay = day
        day.entries = [entry]
        story.days = [day]
        story.entries = [entry]

        StorySyncService.ensureHierarchy(for: story)

        XCTAssertEqual(day.note, "旧版外层填写的摘要")
        XCTAssertEqual(entry.note, "")
        XCTAssertTrue(day.didMigrateInlineSummary)

        day.note = ""
        entry.note = "后来补充的具体安排回忆"
        StorySyncService.ensureHierarchy(for: story)

        XCTAssertEqual(day.note, "")
        XCTAssertEqual(entry.note, "后来补充的具体安排回忆")
    }

    func testAutomaticSourceDetailsAreRemovedFromEditableMemory() {
        let story = TravelStory(
            title: "杭州周末",
            destination: "杭州",
            startDate: Date(),
            endDate: Date(),
            summary: ""
        )
        let day = StoryDay(date: Date(), title: "第一天", sortOrder: 0, story: story)
        let entry = StoryEntry(title: "断桥", category: .attraction, sortOrder: 0)
        let sourceDetails = "类型：景点；地点：断桥；步行前往，路程 1.2 公里。"
        entry.sourceItemID = UUID()
        entry.sourceMemoryPrefill = sourceDetails
        entry.note = sourceDetails
        entry.story = story
        entry.storyDay = day
        day.entries = [entry]
        story.days = [day]
        story.entries = [entry]

        StorySyncService.ensureHierarchy(for: story)

        XCTAssertEqual(entry.note, "")
        XCTAssertEqual(entry.sourceMemoryPrefill, sourceDetails)
        XCTAssertEqual(day.note, "")
    }

    func testJourneyModuleCapabilitiesKeepFootprintFocusedOnMemories() {
        XCTAssertTrue(JourneyModuleKind.itinerary.capabilities.supportsPlannedTransport)
        XCTAssertTrue(JourneyModuleKind.itinerary.capabilities.supportsBudget)
        XCTAssertFalse(JourneyModuleKind.footprint.capabilities.supportsPlannedTransport)
        XCTAssertFalse(JourneyModuleKind.footprint.capabilities.supportsBudget)
        XCTAssertTrue(JourneyModuleKind.footprint.capabilities.supportsPostTripNarrative)
    }

    func testLegacyStoryLocationMigrationFillsMissingFieldsWithoutOverwritingUserLocation() {
        let date = Date()
        let trip = Trip(title: "杭州周末", destination: "杭州", startDate: date, endDate: date)
        let day = TripDay(date: date, title: "抵达杭州", sortOrder: 0, trip: trip)
        let item = ItineraryItem(
            title: "高铁抵达杭州东站",
            category: .transport,
            startTime: date,
            endTime: date.addingTimeInterval(3_600),
            sortOrder: 0
        )
        item.locationMode = .single
        item.placeName = "杭州东站"
        item.placeAddress = "杭州市上城区全福桥路2号"
        item.day = day
        day.items = [item]
        trip.days = [day]

        let story = TravelStory(title: "杭州周末", destination: "杭州", startDate: date, endDate: date, summary: "")
        let entry = StoryEntry(title: item.title, category: .transport, sortOrder: 0)
        entry.sourceItemID = item.id
        entry.story = story
        story.entries = [entry]

        XCTAssertTrue(StorySyncService.migrateLegacyLocations(for: story, from: trip))
        XCTAssertEqual(entry.locationMode, .single)
        XCTAssertEqual(entry.placeName, "杭州东站")
        XCTAssertEqual(entry.placeAddress, "杭州市上城区全福桥路2号")

        entry.placeName = "用户标注的东广场入口"
        item.placeName = "杭州东站西广场"

        XCTAssertFalse(StorySyncService.migrateLegacyLocations(for: story, from: trip))
        XCTAssertEqual(entry.placeName, "用户标注的东广场入口")
    }

    func testStoryDayCardDisplaysSummaryWithoutFallingBackToDetails() {
        let day = StoryDay(date: Date(), title: "西湖环线", sortOrder: 0)
        day.note = "太阳从云后出来时，湖面一下亮了起来。"
        day.details = "这是当天的长文本测试区域，可记录天气、同行人和路线变化。"

        XCTAssertEqual(day.cardSummary, "太阳从云后出来时，湖面一下亮了起来。")

        day.note = ""
        XCTAssertEqual(day.cardSummary, "")
    }

    func testSyncDetachesDeletedSourcePointWhenFootprintHasUserContent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let start = Date()
        let trip = Trip(title: "南京一天", destination: "南京", startDate: start, endDate: start)
        let day = TripDay(date: start, title: "第一天", sortOrder: 0, trip: trip)
        let item = ItineraryItem(title: "明孝陵", category: .attraction, startTime: start, endTime: start, sortOrder: 0)
        item.day = day
        day.items = [item]
        trip.days = [day]
        context.insert(trip)

        let result = try StoryArchiveService.archive(
            trip: trip,
            selectedItems: [item],
            syncScope: .item,
            sourceIDs: [item.id],
            summary: "",
            modelContext: context
        )
        let savedEntry = try XCTUnwrap(result.story.sortedEntries.first)
        savedEntry.note = "保留这段回忆"
        day.items.removeAll()
        context.delete(item)

        let report = StorySyncService.sync(story: result.story, from: trip, modelContext: context)

        XCTAssertEqual(report.detachedEntries, 1)
        XCTAssertNil(savedEntry.sourceItemID)
        XCTAssertEqual(savedEntry.note, "保留这段回忆")
        XCTAssertEqual(result.story.sortedEntries.count, 1)
    }

    func testBackupRestoreReplacesLocalDataAndPreservesJourneyRelationships() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_788_000_000)

        let trip = Trip(title: "苏州周末", destination: "苏州", startDate: start, endDate: start, note: "慢慢逛")
        let day = TripDay(date: start, title: "园林", sortOrder: 0, trip: trip)
        day.note = "早起"
        let item = ItineraryItem(title: "拙政园", category: .attraction, startTime: start, endTime: start.addingTimeInterval(7_200), sortOrder: 0)
        item.address = "东北街178号"
        item.locationMode = .route
        item.originName = "苏州站"
        item.originAddress = "苏州市姑苏区苏站路"
        item.destinationName = "拙政园"
        item.destinationAddress = "苏州市姑苏区东北街178号"
        item.transport = .walk
        item.cost = 80
        item.completeIfElapsed(relativeTo: start)
        item.day = day
        let itineraryMedia = MediaReference(localIdentifier: "trip-photo", kind: .image)
        itineraryMedia.caption = "荷花"
        itineraryMedia.itineraryItem = item
        item.media = [itineraryMedia]
        day.items = [item]
        trip.days = [day]
        context.insert(trip)

        let story = TravelStory(title: "苏州周末", destination: "苏州", startDate: start, endDate: start, summary: "江南很好")
        story.sourceTripID = trip.id
        story.syncScope = .item
        story.sourceSelectionIDs = [item.id]
        let storyDay = StoryDay(date: start, title: "园林", sortOrder: 0, sourceDayID: day.id, story: story)
        storyDay.note = "当天小记"
        storyDay.details = "天气晴"
        let entry = StoryEntry(title: "拙政园", category: .attraction, sortOrder: 0)
        entry.sourceItemID = item.id
        entry.startTime = start
        entry.endTime = start.addingTimeInterval(7_200)
        entry.address = "东北街178号"
        entry.locationMode = .single
        entry.placeName = "拙政园"
        entry.placeAddress = "苏州市姑苏区东北街178号"
        entry.supplementalInfo = "提前预约"
        entry.transport = .walk
        entry.distanceText = "1.2 公里 · 18 分钟"
        entry.cost = 80
        entry.note = "值得再来"
        entry.story = story
        entry.storyDay = storyDay
        let storyMedia = MediaReference(localIdentifier: "story-video", kind: .video)
        storyMedia.caption = "园林视频"
        storyMedia.storyEntry = entry
        entry.media = [storyMedia]
        storyDay.entries = [entry]
        story.days = [storyDay]
        story.entries = [entry]
        context.insert(story)
        try context.save()

        let backupData = try DataBackupService.makeBackupData(from: context, exportedAt: start)
        let inspected = try DataBackupService.inspectBackup(backupData)
        XCTAssertEqual(inspected.tripCount, 1)
        XCTAssertEqual(inspected.storyCount, 1)
        XCTAssertEqual(inspected.dayCount, 2)
        XCTAssertEqual(inspected.placeCount, 2)
        XCTAssertEqual(inspected.mediaReferenceCount, 2)

        context.insert(Trip(title: "新手机上的临时数据", destination: "", startDate: start, endDate: start))
        try context.save()

        let restored = try DataBackupService.restoreBackup(backupData, into: context)
        XCTAssertEqual(restored, inspected)

        let savedTrips = try context.fetch(FetchDescriptor<Trip>())
        let savedStories = try context.fetch(FetchDescriptor<TravelStory>())
        XCTAssertEqual(savedTrips.count, 1)
        XCTAssertEqual(savedStories.count, 1)

        let savedTrip = try XCTUnwrap(savedTrips.first)
        let savedItem = try XCTUnwrap(savedTrip.sortedDays.first?.sortedItems.first)
        XCTAssertEqual(savedTrip.id, trip.id)
        XCTAssertEqual(savedTrip.note, "慢慢逛")
        XCTAssertEqual(savedItem.address, "东北街178号")
        XCTAssertEqual(savedItem.transport, .walk)
        XCTAssertEqual(savedItem.cost, 80)
        XCTAssertEqual(savedItem.executionStatus, .inProgress)
        XCTAssertFalse(savedItem.isAutomaticCompletionOverridden)
        XCTAssertEqual(savedItem.locationMode, .route)
        XCTAssertEqual(savedItem.originName, "苏州站")
        XCTAssertEqual(savedItem.destinationName, "拙政园")
        XCTAssertEqual(savedItem.media.first?.localIdentifier, "trip-photo")
        XCTAssertEqual(savedItem.media.first?.itineraryItem?.id, savedItem.id)

        let savedStory = try XCTUnwrap(savedStories.first)
        let savedStoryDay = try XCTUnwrap(savedStory.sortedDays.first)
        let savedEntry = try XCTUnwrap(savedStoryDay.sortedEntries.first)
        XCTAssertEqual(savedStory.sourceTripID, savedTrip.id)
        XCTAssertEqual(savedStory.sourceSelectionIDs, [savedItem.id])
        XCTAssertEqual(savedStoryDay.sourceDayID, savedTrip.sortedDays.first?.id)
        XCTAssertEqual(savedStoryDay.details, "天气晴")
        XCTAssertEqual(savedEntry.sourceItemID, savedItem.id)
        XCTAssertEqual(savedEntry.locationMode, .single)
        XCTAssertEqual(savedEntry.placeName, "拙政园")
        XCTAssertEqual(savedEntry.placeAddress, "苏州市姑苏区东北街178号")
        XCTAssertEqual(savedEntry.startTime, start)
        XCTAssertEqual(savedEntry.endTime, start.addingTimeInterval(7_200))
        XCTAssertEqual(savedEntry.address, "东北街178号")
        XCTAssertEqual(savedEntry.supplementalInfo, "提前预约")
        XCTAssertEqual(savedEntry.transport, .walk)
        XCTAssertEqual(savedEntry.distanceText, "1.2 公里 · 18 分钟")
        XCTAssertEqual(savedEntry.cost, 80)
        XCTAssertEqual(savedEntry.note, "值得再来")
        XCTAssertEqual(savedEntry.media.first?.localIdentifier, "story-video")
        XCTAssertEqual(savedEntry.media.first?.storyEntry?.id, savedEntry.id)
    }

    func testBackupRoundTripsFavoriteArrangements() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let favorite = ItineraryItem(
            title: "想去良渚",
            category: .attraction,
            startTime: now,
            endTime: now.addingTimeInterval(3_600),
            sortOrder: 0
        )
        favorite.isFavorite = true
        favorite.favoriteCreatedAt = now
        favorite.placeName = "良渚古城遗址公园"
        favorite.note = "等天气好时再去"
        let media = MediaReference(localIdentifier: "favorite-photo", kind: .image)
        media.itineraryItem = favorite
        favorite.media = [media]
        context.insert(favorite)
        try context.save()

        let data = try DataBackupService.makeBackupData(from: context, exportedAt: now)
        let summary = try DataBackupService.inspectBackup(data)
        XCTAssertEqual(summary.favoriteCount, 1)
        XCTAssertEqual(summary.placeCount, 1)
        XCTAssertEqual(summary.mediaReferenceCount, 1)

        let target = try makeContainer()
        _ = try DataBackupService.restoreBackup(data, into: target.mainContext)
        let restored = try target.mainContext.fetch(FetchDescriptor<ItineraryItem>())
            .filter(\.isFavorite)
        let saved = try XCTUnwrap(restored.first)
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(saved.title, "想去良渚")
        XCTAssertEqual(saved.placeName, "良渚古城遗址公园")
        XCTAssertEqual(saved.note, "等天气好时再去")
        XCTAssertNil(saved.day)
        XCTAssertEqual(saved.media.first?.localIdentifier, "favorite-photo")
    }

    func testLegacyBackupWithoutLocationAndExecutionFieldsStillRestores() throws {
        let source = try makeContainer()
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        let trip = Trip(title: "旧备份", destination: "上海", startDate: start, endDate: start)
        let day = TripDay(date: start, title: "浦东", sortOrder: 0, trip: trip)
        let item = ItineraryItem(
            title: "外滩夜景",
            category: .attraction,
            startTime: start,
            endTime: start.addingTimeInterval(3_600),
            sortOrder: 0
        )
        item.address = "上海市黄浦区中山东一路"
        item.isCompleted = true
        item.day = day
        day.items = [item]
        trip.days = [day]
        source.mainContext.insert(trip)
        try source.mainContext.save()

        let currentData = try DataBackupService.makeBackupData(from: source.mainContext, exportedAt: start)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: currentData) as? [String: Any])
        var trips = try XCTUnwrap(root["trips"] as? [[String: Any]])
        var days = try XCTUnwrap(trips[0]["days"] as? [[String: Any]])
        var items = try XCTUnwrap(days[0]["items"] as? [[String: Any]])
        for key in [
            "locationModeRaw", "placeName", "placeAddress", "originName", "originAddress",
            "destinationName", "destinationAddress", "executionStatusRaw", "isAutomaticCompletionOverridden"
        ] {
            items[0].removeValue(forKey: key)
        }
        days[0]["items"] = items
        trips[0]["days"] = days
        root["trips"] = trips
        let legacyData = try JSONSerialization.data(withJSONObject: root)

        let target = try makeContainer()
        _ = try DataBackupService.restoreBackup(legacyData, into: target.mainContext)
        let restoredTrip = try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<Trip>()).first)
        let restoredItem = try XCTUnwrap(restoredTrip.allItems.first)

        XCTAssertEqual(restoredItem.executionStatus, .completed)
        XCTAssertEqual(restoredItem.locationMode, .single)
        XCTAssertEqual(restoredItem.primaryNavigationTarget?.displayName, "外滩")
        XCTAssertEqual(restoredItem.primaryNavigationTarget?.address, "上海市黄浦区中山东一路")
    }

    func testStoryCoverAndCropRoundTripThroughBackupAndShareData() throws {
        let source = try makeContainer()
        let date = Date(timeIntervalSince1970: 1_788_000_000)
        let story = TravelStory(title: "西湖足迹", destination: "杭州", startDate: date, endDate: date, summary: "湖边慢走")
        story.coverZoom = 2.25
        story.coverOffsetX = -0.4
        story.coverOffsetY = 0.65
        let cover = MediaReference(localIdentifier: "local-cover-photo", kind: .image)
        cover.storyCover = story
        story.coverMedia = cover
        source.mainContext.insert(story)
        try source.mainContext.save()

        let backup = try DataBackupService.makeBackupData(from: source.mainContext, exportedAt: date)
        XCTAssertEqual(try DataBackupService.inspectBackup(backup).mediaReferenceCount, 1)

        let target = try makeContainer()
        _ = try DataBackupService.restoreBackup(backup, into: target.mainContext)
        let restored = try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<TravelStory>()).first)
        XCTAssertEqual(restored.coverMedia?.localIdentifier, "local-cover-photo")
        XCTAssertEqual(restored.coverMedia?.storyCover?.id, restored.id)
        XCTAssertEqual(restored.coverZoom, 2.25, accuracy: 0.001)
        XCTAssertEqual(restored.coverOffsetX, -0.4, accuracy: 0.001)
        XCTAssertEqual(restored.coverOffsetY, 0.65, accuracy: 0.001)

        let sharedData = try SharedJourneyService.makeShareData(story: story, sharedAt: date, includeMedia: true)
        XCTAssertEqual(try SharedJourneyService.inspect(sharedData).mediaCount, 1)
        let sharedTarget = try makeContainer()
        _ = try SharedJourneyService.importJourney(sharedData, into: sharedTarget.mainContext)
        let sharedStory = try XCTUnwrap(sharedTarget.mainContext.fetch(FetchDescriptor<TravelStory>()).first)
        XCTAssertEqual(sharedStory.coverMedia?.localIdentifier, "")
        XCTAssertEqual(sharedStory.coverZoom, 2.25, accuracy: 0.001)
        XCTAssertEqual(sharedStory.coverOffsetX, -0.4, accuracy: 0.001)
        XCTAssertEqual(sharedStory.coverOffsetY, 0.65, accuracy: 0.001)
    }

    func testLegacyStoryBackupWithoutCoverFieldsStillRestores() throws {
        let source = try makeContainer()
        let date = Date(timeIntervalSince1970: 1_788_000_000)
        source.mainContext.insert(
            TravelStory(title: "旧版足迹", destination: "厦门", startDate: date, endDate: date, summary: "")
        )
        try source.mainContext.save()

        let data = try DataBackupService.makeBackupData(from: source.mainContext, exportedAt: date)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var stories = try XCTUnwrap(root["stories"] as? [[String: Any]])
        for key in ["coverMedia", "coverZoom", "coverOffsetX", "coverOffsetY"] {
            stories[0].removeValue(forKey: key)
        }
        root["stories"] = stories
        let legacyData = try JSONSerialization.data(withJSONObject: root)

        let target = try makeContainer()
        _ = try DataBackupService.restoreBackup(legacyData, into: target.mainContext)
        let restored = try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<TravelStory>()).first)
        XCTAssertNil(restored.coverMedia)
        XCTAssertEqual(restored.coverZoom, 1)
        XCTAssertEqual(restored.coverOffsetX, 0)
        XCTAssertEqual(restored.coverOffsetY, 0)
    }

    func testShareCardDataSupportsWholeTripAndSingleDayScopes() {
        let calendar = Calendar(identifier: .gregorian)
        let firstDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        let secondDate = calendar.date(byAdding: .day, value: 1, to: firstDate)!
        let trip = Trip(title: "苏州两日游", destination: "苏州", startDate: firstDate, endDate: secondDate, note: "慢慢逛")
        let firstDay = TripDay(date: firstDate, title: "园林", sortOrder: 0, trip: trip)
        let secondDay = TripDay(date: secondDate, title: "古城", sortOrder: 1, trip: trip)
        let firstItem = ItineraryItem(title: "拙政园", category: .attraction, startTime: firstDate, endTime: firstDate.addingTimeInterval(3600), sortOrder: 0)
        let secondItem = ItineraryItem(title: "平江路", category: .attraction, startTime: secondDate, endTime: secondDate.addingTimeInterval(3600), sortOrder: 0)
        firstItem.day = firstDay
        secondItem.day = secondDay
        firstDay.items = [firstItem]
        secondDay.items = [secondItem]
        trip.days = [secondDay, firstDay]

        let whole = ShareCardData(trip: trip)
        let singleDay = ShareCardData(trip: trip, day: secondDay)

        XCTAssertEqual(whole.scopeLabel, "整段旅程")
        XCTAssertEqual(whole.sections.map(\.title), ["园林", "古城"])
        XCTAssertEqual(whole.sections.flatMap(\.items).map(\.title), ["拙政园", "平江路"])
        XCTAssertEqual(singleDay.scopeID, secondDay.id)
        XCTAssertEqual(singleDay.scopeLabel, "单日旅程")
        XCTAssertEqual(singleDay.sections.count, 1)
        XCTAssertEqual(singleDay.sections.first?.items.map(\.title), ["平江路"])
        let renderedImage = ShareCardImageRenderer.render(data: whole, coverImage: nil, scale: 1)
        XCTAssertNotNil(renderedImage?.pngData())
        XCTAssertEqual(renderedImage?.size.width, 360)
        XCTAssertGreaterThan(renderedImage?.size.height ?? 0, 190)
    }

    func testShareCardDataIncludesStoryDaySummaryDetailsAndCover() {
        let date = Date()
        let story = TravelStory(title: "上海一日", destination: "上海", startDate: date, endDate: date, summary: "")
        let day = StoryDay(date: date, title: "浦东", sortOrder: 0, story: story)
        day.note = "登高看城市"
        day.details = "傍晚灯光很好看"
        let entry = StoryEntry(title: "东方明珠", category: .attraction, sortOrder: 0)
        entry.story = story
        entry.storyDay = day
        let video = MediaReference(localIdentifier: "story-video", kind: .video, sortOrder: 0)
        let media = MediaReference(localIdentifier: "cover-photo", kind: .image, sortOrder: 1)
        let secondPhoto = MediaReference(localIdentifier: "second-photo", kind: .image, sortOrder: 2)
        video.storyEntry = entry
        media.storyEntry = entry
        secondPhoto.storyEntry = entry
        entry.media = [secondPhoto, media, video]
        day.entries = [entry]
        story.days = [day]
        story.entries = [entry]
        let customCover = MediaReference(localIdentifier: "custom-cover", kind: .image)
        customCover.storyCover = story
        story.coverMedia = customCover
        story.coverZoom = 1.8
        story.coverOffsetX = 0.25
        story.coverOffsetY = -0.5

        let data = ShareCardData(story: story, day: day)

        XCTAssertEqual(data.scopeLabel, "单日足迹")
        XCTAssertEqual(data.summary, "登高看城市")
        XCTAssertEqual(data.sections.first?.narrative, "傍晚灯光很好看")
        XCTAssertEqual(data.coverAssetIdentifier, "custom-cover")
        XCTAssertEqual(data.coverZoom, 1.8, accuracy: 0.001)
        XCTAssertEqual(data.coverOffsetX, 0.25, accuracy: 0.001)
        XCTAssertEqual(data.coverOffsetY, -0.5, accuracy: 0.001)
        XCTAssertEqual(data.sections.first?.items.first?.photoAssetIdentifiers, ["cover-photo", "second-photo"])
        XCTAssertEqual(data.photoAssetIdentifiers, ["cover-photo", "second-photo"])
    }

    func testSharedTripImportsAsAdditiveIdempotentCopyWithoutLocalMedia() throws {
        let sourceContainer = try makeContainer()
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        let trip = Trip(title: "杭州周末", destination: "杭州", startDate: start, endDate: start)
        let day = TripDay(date: start, title: "西湖", sortOrder: 0, trip: trip)
        let item = ItineraryItem(title: "前往断桥", category: .attraction, startTime: start, endTime: start.addingTimeInterval(3_600), sortOrder: 0)
        item.locationMode = .route
        item.originName = "杭州东站"
        item.originAddress = "杭州市上城区全福桥路2号"
        item.destinationName = "断桥"
        item.destinationAddress = "杭州市西湖区白堤"
        item.address = item.destinationAddress
        item.completeIfElapsed(relativeTo: start)
        item.day = day
        let media = MediaReference(localIdentifier: "only-valid-on-sender", kind: .image)
        media.itineraryItem = item
        item.media = [media]
        day.items = [item]
        trip.days = [day]
        sourceContainer.mainContext.insert(trip)
        try sourceContainer.mainContext.save()

        let data = try SharedJourneyService.makeShareData(trip: trip, sharedAt: start)
        let preview = try SharedJourneyService.preview(data)
        XCTAssertEqual(preview.summary.kind, .trip)
        XCTAssertEqual(preview.summary.title, "杭州周末")
        XCTAssertEqual(preview.summary.dayCount, 1)
        XCTAssertEqual(preview.summary.placeCount, 2)
        XCTAssertEqual(
            preview.days.first?.places.first?.address,
            "杭州东站 · 杭州市上城区全福桥路2号 → 断桥 · 杭州市西湖区白堤"
        )

        let targetContainer = try makeContainer()
        let targetContext = targetContainer.mainContext
        targetContext.insert(Trip(title: "我自己的行程", destination: "上海", startDate: start, endDate: start))
        try targetContext.save()

        let firstImport = try SharedJourneyService.importJourney(data, into: targetContext)
        XCTAssertFalse(firstImport.wasAlreadyPresent)
        XCTAssertEqual(try targetContext.fetch(FetchDescriptor<Trip>()).count, 2)
        let imported = try XCTUnwrap(try targetContext.fetch(FetchDescriptor<Trip>()).first { $0.id == trip.id })
        let importedItem = try XCTUnwrap(imported.sortedDays.first?.sortedItems.first)
        XCTAssertEqual(importedItem.title, "前往断桥")
        XCTAssertEqual(importedItem.locationMode, .route)
        XCTAssertEqual(importedItem.originName, "杭州东站")
        XCTAssertEqual(importedItem.destinationName, "断桥")
        XCTAssertEqual(importedItem.executionStatus, .inProgress)
        XCTAssertTrue(importedItem.media.isEmpty)

        let secondImport = try SharedJourneyService.importJourney(data, into: targetContext)
        XCTAssertTrue(secondImport.wasAlreadyPresent)
        XCTAssertEqual(try targetContext.fetch(FetchDescriptor<Trip>()).count, 2)
    }

    func testSharedFootprintDayImportsWithoutSenderSyncLinks() throws {
        let sourceContainer = try makeContainer()
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        let story = TravelStory(title: "南京两日", destination: "南京", startDate: start, endDate: start.addingTimeInterval(86_400), summary: "古都散步")
        story.sourceTripID = UUID()
        story.syncScope = .day
        let firstDay = StoryDay(date: start, title: "城墙", sortOrder: 0, sourceDayID: UUID(), story: story)
        let secondDay = StoryDay(date: start.addingTimeInterval(86_400), title: "博物院", sortOrder: 1, sourceDayID: UUID(), story: story)
        let entry = StoryEntry(title: "游览中华门城堡", category: .attraction, sortOrder: 0)
        entry.sourceItemID = UUID()
        entry.locationMode = .single
        entry.placeName = "中华门城堡"
        entry.placeAddress = "南京市秦淮区中华路"
        entry.story = story
        entry.storyDay = firstDay
        firstDay.entries = [entry]
        story.days = [firstDay, secondDay]
        story.entries = [entry]
        sourceContainer.mainContext.insert(story)
        try sourceContainer.mainContext.save()

        let data = try SharedJourneyService.makeShareData(story: story, selectedDay: firstDay, sharedAt: start)
        let preview = try SharedJourneyService.preview(data)
        XCTAssertEqual(preview.summary.placeCount, 1)
        XCTAssertEqual(preview.days.first?.places.first?.address, "中华门城堡 · 南京市秦淮区中华路")
        let targetContainer = try makeContainer()
        _ = try SharedJourneyService.importJourney(data, into: targetContainer.mainContext)

        let imported = try XCTUnwrap(try targetContainer.mainContext.fetch(FetchDescriptor<TravelStory>()).first)
        XCTAssertEqual(imported.title, "南京两日 · 城墙")
        XCTAssertEqual(imported.sortedDays.count, 1)
        XCTAssertNil(imported.sourceTripID)
        XCTAssertTrue(imported.sourceSelectionIDs.isEmpty)
        XCTAssertNil(imported.sortedDays.first?.sourceDayID)
        let importedEntry = try XCTUnwrap(imported.sortedEntries.first)
        XCTAssertNil(importedEntry.sourceItemID)
        XCTAssertEqual(importedEntry.title, "游览中华门城堡")
        XCTAssertEqual(importedEntry.locationMode, .single)
        XCTAssertEqual(importedEntry.placeName, "中华门城堡")
        XCTAssertEqual(importedEntry.placeAddress, "南京市秦淮区中华路")
    }

    func testSharedJourneyMediaMetadataOmitsSenderPhotoIdentifier() throws {
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        let trip = Trip(title: "带照片的行程", destination: "杭州", startDate: start, endDate: start)
        let day = TripDay(date: start, title: "西湖", sortOrder: 0, trip: trip)
        let item = ItineraryItem(title: "断桥", category: .attraction, startTime: start, endTime: start, sortOrder: 0)
        let media = MediaReference(localIdentifier: "sender-private-photo-identifier", kind: .image)
        media.itineraryItem = item
        item.media = [media]
        item.day = day
        day.items = [item]
        trip.days = [day]

        let data = try SharedJourneyService.makeShareData(trip: trip, includeMedia: true)
        let summary = try SharedJourneyService.inspect(data)

        XCTAssertEqual(summary.mediaCount, 1)
        XCTAssertFalse(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("sender-private-photo-identifier"))
    }

    func testPortableBackupContainerWithoutMediaRoundTrips() async throws {
        let sourceContainer = try makeContainer()
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        sourceContainer.mainContext.insert(
            Trip(title: "无媒体备份", destination: "南京", startDate: start, endDate: start)
        )
        try sourceContainer.mainContext.save()

        let exported = try await DataBackupService.makeBackupPackage(from: sourceContainer.mainContext, exportedAt: start)
        XCTAssertEqual(exported.mediaCount, 0)
        XCTAssertEqual(exported.mediaBytes, 0)
        let opened = try XCTUnwrap(PortablePackageService.open(exported.url))
        XCTAssertEqual(opened.kind, .backup)
        XCTAssertTrue(opened.media.isEmpty)

        let targetContainer = try makeContainer()
        let summary = try await DataBackupService.restoreBackup(from: exported.url, into: targetContainer.mainContext)
        XCTAssertEqual(summary.tripCount, 1)
        XCTAssertEqual(try targetContainer.mainContext.fetch(FetchDescriptor<Trip>()).first?.title, "无媒体备份")
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Trip.self,
            TripDay.self,
            ItineraryItem.self,
            MediaReference.self,
            TravelStory.self,
            StoryDay.self,
            StoryEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
