#if DEBUG
import Photos
import SwiftData

@MainActor
enum DebugSampleDataService {
    static let demoBackupFilename = "旅迹真机样例数据.triptrailbackup"

    private static let markerTripID = fixedID(1)
    private static let exportArgument = "--export-demo-backup"

    private struct DemoMediaIdentifiers {
        let lake: String
        let city: String
        let motion: String
    }

    private struct DemoLibrary {
        let trips: [Trip]
        let stories: [TravelStory]
    }

    static func prepareIfNeeded(in modelContext: ModelContext) async {
        let shouldExport = ProcessInfo.processInfo.arguments.contains(exportArgument)

        do {
            let existingTrips = try modelContext.fetch(FetchDescriptor<Trip>())
            let shouldSeed = !existingTrips.contains { $0.id == markerTripID }
            guard shouldSeed || shouldExport else { return }

            let media = try await importBundledMedia()
            if shouldSeed {
                let library = makeDemoLibrary(media: media)
                library.trips.forEach(modelContext.insert)
                library.stories.forEach(modelContext.insert)
                try modelContext.save()
                print("TRIPTRAIL_DEMO_SEED_READY:\(library.trips.count):\(library.stories.count)")
            }

            if shouldExport {
                let backupURL = try await makeDemoBackup(media: media)
                print("TRIPTRAIL_DEMO_BACKUP_READY:\(backupURL.path)")
            }
        } catch {
            print("TRIPTRAIL_DEMO_PREPARE_FAILED:\(error.localizedDescription)")
        }
    }

    private static func importBundledMedia() async throws -> DemoMediaIdentifiers {
        let currentStatus = PhotoLibraryService.status
        let authorization = currentStatus == .notDetermined
            ? await PhotoLibraryService.requestReadWriteAccess()
            : currentStatus
        guard authorization == .authorized || authorization == .limited else {
            throw PhotoLibraryError.permissionDenied
        }

        let lakeURL = try bundledResource(named: "triptrail-demo-lake", extension: "png")
        let cityURL = try bundledResource(named: "triptrail-demo-city", extension: "png")
        let motionURL = try bundledResource(named: "triptrail-demo-motion", extension: "mov")
        let lake = try await PhotoLibraryService.importAssetFile(at: lakeURL, kind: .image)
        let city = try await PhotoLibraryService.importAssetFile(at: cityURL, kind: .image)
        let motion = try await PhotoLibraryService.importAssetFile(at: motionURL, kind: .video)
        return DemoMediaIdentifiers(
            lake: lake,
            city: city,
            motion: motion
        )
    }

    private static func bundledResource(named name: String, extension fileExtension: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).\(fileExtension)"])
        }
        return url
    }

    private static func makeDemoBackup(media: DemoMediaIdentifiers) async throws -> URL {
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
        let library = makeDemoLibrary(media: media)
        library.trips.forEach(context.insert)
        library.stories.forEach(context.insert)
        try context.save()

        let package = try await DataBackupService.makeBackupPackage(from: context)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destination = documents.appendingPathComponent(demoBackupFilename)
        try Data(contentsOf: package.url).write(to: destination, options: .atomic)
        let summary = try DataBackupService.inspectBackup(at: destination)
        guard summary.tripCount == 3,
              summary.storyCount == 3,
              summary.mediaReferenceCount == 6
        else {
            throw TripTrailBackupError.restoreFailed("样例备份内容校验失败。")
        }
        return destination
    }

    private static func makeDemoLibrary(media: DemoMediaIdentifiers) -> DemoLibrary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today) ?? today
        }
        func time(_ hour: Int, _ minute: Int = 0, on date: Date) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }

        let currentTrip = Trip(
            title: "杭州湖畔慢游（测试）",
            destination: "杭州",
            startDate: day(-1),
            endDate: day(1),
            note: "覆盖路线、预约、费用、导航、照片和视频的完整测试行程。"
        )
        currentTrip.id = markerTripID
        currentTrip.createdAt = day(-20)

        let arrivalDay = makeTripDay(id: 10, date: day(-1), title: "抵达杭州", order: 0, trip: currentTrip)
        let todayDay = makeTripDay(id: 11, date: day(0), title: "西湖环线", order: 1, trip: currentTrip)
        let teaDay = makeTripDay(id: 12, date: day(1), title: "茶园与返程", order: 2, trip: currentTrip)

        let station = makeItem(
            id: 100,
            title: "杭州东站",
            category: .transport,
            start: time(9, 10, on: arrivalDay.date),
            end: time(9, 40, on: arrivalDay.date),
            order: 0,
            address: "抵达后从东广场出站，乘地铁前往酒店。",
            coordinate: (30.2921, 120.2120),
            note: "从东广场出站，乘地铁前往酒店。",
            transport: .train,
            distance: "高铁 1 小时 5 分",
            duration: 30,
            reservation: "G7311 · 08车12A",
            cost: 73,
            completed: true,
            day: arrivalDay
        )
        let hotel = makeItem(
            id: 101,
            title: "湖滨酒店",
            category: .hotel,
            start: time(10, 30, on: arrivalDay.date),
            end: time(11, 0, on: arrivalDay.date),
            order: 1,
            address: "先寄存行李，下午两点后办理入住。",
            coordinate: (30.2550, 120.1610),
            note: "先寄存行李，下午两点后领取房卡。",
            transport: .bus,
            distance: "地铁 6 站",
            duration: 30,
            reservation: "预订号 TT20260830",
            cost: 688,
            completed: true,
            day: arrivalDay
        )
        let checklist = makeItem(
            id: 102,
            title: "湖滨银泰 in77",
            category: .other,
            start: time(11, 10, on: arrivalDay.date),
            end: time(11, 25, on: arrivalDay.date),
            order: 2,
            address: "补充防晒与雨具，并检查充电宝、纸巾和备用电池。",
            coordinate: nil,
            note: "检查充电宝、纸巾和备用电池。",
            transport: .walk,
            distance: "步行 350 米",
            duration: 15,
            reservation: "",
            cost: 96.5,
            completed: false,
            day: arrivalDay
        )
        arrivalDay.items = [station, hotel, checklist]

        let brokenBridge = makeItem(
            id: 110,
            title: "断桥残雪",
            category: .attraction,
            start: time(8, 0, on: todayDay.date),
            end: time(9, 30, on: todayDay.date),
            order: 0,
            address: "从北山街入口慢慢走到平湖秋月，适合拍湖面晨光。",
            coordinate: (30.2636, 120.1488),
            note: "从北山街慢慢走到平湖秋月，拍一段湖面晨光。",
            transport: .walk,
            distance: "步行 1.8 公里",
            duration: 90,
            reservation: "无需预约",
            cost: 0,
            completed: true,
            day: todayDay
        )
        attachMedia(id: 1000, identifier: media.lake, kind: .image, caption: "西湖晨光测试照片", order: 0, to: brokenBridge)
        attachMedia(id: 1001, identifier: media.motion, kind: .video, caption: "三秒动态测试视频", order: 1, to: brokenBridge)

        let lunch = makeItem(
            id: 111,
            title: "楼外楼（孤山店）",
            category: .restaurant,
            start: time(11, 30, on: todayDay.date),
            end: time(13, 0, on: todayDay.date),
            order: 1,
            address: "预留临窗位，尝试西湖醋鱼与龙井虾仁。",
            coordinate: (30.2525, 120.1421),
            note: "预留临窗位，尝试西湖醋鱼与龙井虾仁。",
            transport: .walk,
            distance: "步行 900 米",
            duration: 90,
            reservation: "12:00 · 2人 · 手机尾号 0830",
            cost: 328,
            completed: false,
            day: todayDay
        )
        let market = makeItem(
            id: 112,
            title: "河坊街",
            category: .other,
            start: time(15, 20, on: todayDay.date),
            end: time(17, 0, on: todayDay.date),
            order: 2,
            address: "挑选茶叶和桂花糕，控制在一个手提袋内。",
            coordinate: (30.2417, 120.1761),
            note: "茶叶和桂花糕控制在一个手提袋内。",
            transport: .ride,
            distance: "骑行 3.2 公里",
            duration: 100,
            reservation: "",
            cost: 180,
            completed: false,
            day: todayDay
        )
        todayDay.items = [brokenBridge, lunch, market]

        let teaGarden = makeItem(
            id: 120,
            title: "龙井村茶园",
            category: .special,
            start: time(9, 0, on: teaDay.date),
            end: time(11, 30, on: teaDay.date),
            order: 0,
            address: "天气合适就沿十里琅珰走一小段。",
            coordinate: (30.2242, 120.1017),
            note: "天气合适就沿十里琅珰走一小段。",
            transport: .car,
            distance: "驾车约 11 公里",
            duration: 150,
            reservation: "茶室预约 09:30",
            cost: 120,
            completed: false,
            day: teaDay
        )
        let returnTrain = makeItem(
            id: 121,
            title: "杭州东站",
            category: .transport,
            start: time(17, 5, on: teaDay.date),
            end: time(18, 10, on: teaDay.date),
            order: 1,
            address: "提前四十分钟到站，乘坐返程高铁。",
            coordinate: (30.2921, 120.2120),
            note: "提前四十分钟到站。",
            transport: .train,
            distance: "高铁 1 小时 5 分",
            duration: 65,
            reservation: "G7590 · 05车06F",
            cost: 73,
            completed: false,
            day: teaDay
        )
        teaDay.items = [teaGarden, returnTrain]
        currentTrip.days = [arrivalDay, todayDay, teaDay]

        let upcomingTrip = Trip(
            title: "上海周末城市漫步（测试）",
            destination: "上海",
            startDate: day(7),
            endDate: day(8),
            note: "用于查看即将出发状态、城市坐标与跨系统分享效果。"
        )
        upcomingTrip.id = fixedID(2)
        upcomingTrip.createdAt = day(-10)
        let shanghaiDay = makeTripDay(id: 20, date: day(7), title: "建筑与夜色", order: 0, trip: upcomingTrip)
        let flight = makeItem(
            id: 200,
            title: "上海虹桥国际机场 T2",
            category: .transport,
            start: time(8, 0, on: shanghaiDay.date),
            end: time(9, 0, on: shanghaiDay.date),
            order: 0,
            address: "在出发层集合，留意登机口变更。",
            coordinate: (31.1968, 121.3363),
            note: "测试飞机交通方式与预约信息。",
            transport: .flight,
            distance: "机场线",
            duration: 60,
            reservation: "MU5101 · 登机口 C52",
            cost: 860,
            completed: false,
            day: shanghaiDay
        )
        let bund = makeItem(
            id: 201,
            title: "外滩",
            category: .attraction,
            start: time(18, 30, on: shanghaiDay.date),
            end: time(20, 30, on: shanghaiDay.date),
            order: 1,
            address: "蓝调时刻前到达，沿中山东一路慢慢散步。",
            coordinate: (31.2400, 121.4900),
            note: "蓝调时刻前到达，测试城市照片展示。",
            transport: .bus,
            distance: "公交约 25 分钟",
            duration: 120,
            reservation: "",
            cost: 0,
            completed: false,
            day: shanghaiDay
        )
        attachMedia(id: 2000, identifier: media.city, kind: .image, caption: "外滩夜景测试照片", order: 0, to: bund)
        shanghaiDay.items = [flight, bund]
        upcomingTrip.days = [shanghaiDay]

        let historyTrip = Trip(
            title: "厦门海风旧游（测试）",
            destination: "厦门",
            startDate: day(-45),
            endDate: day(-42),
            note: "用于查看历史行程、全部完成进度与归档入口。"
        )
        historyTrip.id = fixedID(3)
        historyTrip.createdAt = day(-60)
        let xiamenDay = makeTripDay(id: 30, date: day(-45), title: "鼓浪屿一日", order: 0, trip: historyTrip)
        let ferry = makeItem(
            id: 300,
            title: "厦门邮轮中心厦鼓码头",
            category: .transport,
            start: time(8, 10, on: xiamenDay.date),
            end: time(8, 35, on: xiamenDay.date),
            order: 0,
            address: "刷身份证登船，提前留意候船区提示。",
            coordinate: (24.4895, 118.0686),
            note: "刷身份证登船。",
            transport: .car,
            distance: "轮渡约 25 分钟",
            duration: 25,
            reservation: "08:10 船票",
            cost: 35,
            completed: true,
            day: xiamenDay
        )
        let pianoMuseum = makeItem(
            id: 301,
            title: "菽庄花园与钢琴博物馆",
            category: .attraction,
            start: time(9, 20, on: xiamenDay.date),
            end: time(11, 40, on: xiamenDay.date),
            order: 1,
            address: "从菽庄花园入园，顺路参观钢琴博物馆。",
            coordinate: (24.4376, 118.0603),
            note: "旧行程全部完成。",
            transport: .walk,
            distance: "步行 1.4 公里",
            duration: 140,
            reservation: "",
            cost: 30,
            completed: true,
            day: xiamenDay
        )
        xiamenDay.items = [ferry, pianoMuseum]
        historyTrip.days = [xiamenDay]

        let linkedStory = TravelStory(
            title: "杭州湖畔慢游 · 足迹（测试）",
            destination: "杭州",
            startDate: currentTrip.startDate,
            endDate: currentTrip.endDate,
            summary: "从测试行程同步而来的足迹，用于验证源行程同步、照片视频和逐日记录。"
        )
        linkedStory.id = fixedID(500)
        linkedStory.createdAt = day(0)
        linkedStory.sourceTripID = currentTrip.id
        linkedStory.syncScope = .trip
        linkedStory.sourceSelectionIDs = Set(currentTrip.days.map(\.id) + currentTrip.allItems.map(\.id))
        let linkedStoryDay = makeStoryDay(id: 510, date: todayDay.date, title: "西湖环线", order: 0, sourceDayID: todayDay.id, story: linkedStory)
        linkedStoryDay.note = "太阳从云后出来时，湖面一下亮了起来。"
        linkedStoryDay.details = "这是当天的长文本测试区域，可记录天气、同行人和路线变化。"
        let linkedEntry = makeStoryEntry(
            id: 520,
            title: "断桥残雪",
            category: .attraction,
            time: "08:00–09:30",
            address: brokenBridge.address,
            coordinate: (brokenBridge.latitude, brokenBridge.longitude),
            note: "风不大，适合慢慢走，也拍下了一段动态素材。",
            route: "沿北山街步行 1.8 公里",
            order: 0,
            sourceItemID: brokenBridge.id,
            story: linkedStory,
            day: linkedStoryDay
        )
        attachStoryMedia(id: 5000, identifier: media.lake, kind: .image, caption: "足迹中的西湖照片", order: 0, to: linkedEntry)
        attachStoryMedia(id: 5001, identifier: media.motion, kind: .video, caption: "足迹中的测试视频", order: 1, to: linkedEntry)
        linkedStoryDay.entries = [linkedEntry]
        linkedStory.days = [linkedStoryDay]
        linkedStory.entries = [linkedEntry]

        let cityStory = TravelStory(
            title: "上海夜色收藏（测试）",
            destination: "上海",
            startDate: day(-12),
            endDate: day(-11),
            summary: "独立创建的足迹，不关联任何行程，用于验证收藏导入后的编辑体验。"
        )
        cityStory.id = fixedID(600)
        cityStory.createdAt = day(-9)
        let cityStoryDay = makeStoryDay(id: 610, date: cityStory.startDate, title: "夜色散步", order: 0, sourceDayID: nil, story: cityStory)
        cityStoryDay.note = "从武康路一路走到外滩，城市的颜色慢慢亮起来。"
        let cityEntry = makeStoryEntry(
            id: 620,
            title: "外滩",
            category: .attraction,
            time: "18:42",
            address: "蓝调时刻前到达，沿江记录城市夜色。",
            coordinate: (31.2400, 121.4900),
            note: "这张图用于检查足迹卡片封面、轮播与跨设备媒体恢复。",
            route: "地铁 2 号线后步行 700 米",
            order: 0,
            sourceItemID: nil,
            story: cityStory,
            day: cityStoryDay
        )
        attachStoryMedia(id: 6000, identifier: media.city, kind: .image, caption: "上海夜色测试照片", order: 0, to: cityEntry)
        cityStoryDay.entries = [cityEntry]
        cityStory.days = [cityStoryDay]
        cityStory.entries = [cityEntry]

        let journalStory = TravelStory(
            title: "厦门海风手记（测试）",
            destination: "厦门",
            startDate: historyTrip.startDate,
            endDate: historyTrip.endDate,
            summary: "纯文字足迹，用于检查没有媒体时的占位状态与长文本排版。"
        )
        journalStory.id = fixedID(700)
        journalStory.createdAt = day(-40)
        let journalDay = makeStoryDay(id: 710, date: journalStory.startDate, title: "鼓浪屿", order: 0, sourceDayID: nil, story: journalStory)
        journalDay.note = "海风很轻，沿着小路随意转弯，比照着攻略走更有意思。"
        journalDay.details = "午后在树荫下休息，记下店名与想再次拜访的小路。"
        let journalEntry = makeStoryEntry(
            id: 720,
            title: "菽庄花园",
            category: .attraction,
            time: "09:20–11:40",
            address: "从菽庄花园入园，顺路参观钢琴博物馆。",
            coordinate: (24.4376, 118.0603),
            note: "没有照片也能完整保留文字、说明与路线。",
            route: "从三丘田码头步行约 20 分钟",
            order: 0,
            sourceItemID: nil,
            story: journalStory,
            day: journalDay
        )
        journalDay.entries = [journalEntry]
        journalStory.days = [journalDay]
        journalStory.entries = [journalEntry]

        return DemoLibrary(
            trips: [currentTrip, upcomingTrip, historyTrip],
            stories: [linkedStory, cityStory, journalStory]
        )
    }

    private static func makeTripDay(id: Int, date: Date, title: String, order: Int, trip: Trip) -> TripDay {
        let result = TripDay(date: date, title: title, sortOrder: order, trip: trip)
        result.id = fixedID(id)
        return result
    }

    private static func makeItem(
        id: Int,
        title: String,
        category: PlaceCategory,
        start: Date,
        end: Date,
        order: Int,
        address: String,
        coordinate: (Double, Double)?,
        note: String,
        transport: TransportMode,
        distance: String,
        duration: Int,
        reservation: String,
        cost: Double,
        completed: Bool,
        day: TripDay
    ) -> ItineraryItem {
        let result = ItineraryItem(title: title, category: category, startTime: start, endTime: end, sortOrder: order)
        result.id = fixedID(id)
        result.address = address
        result.latitude = coordinate?.0
        result.longitude = coordinate?.1
        result.note = note
        result.transport = transport
        result.distanceText = distance
        result.playDurationMinutes = duration
        result.reservationInfo = reservation
        result.cost = cost
        result.isCompleted = completed
        result.day = day
        return result
    }

    private static func attachMedia(
        id: Int,
        identifier: String,
        kind: MediaKind,
        caption: String,
        order: Int,
        to item: ItineraryItem
    ) {
        let media = MediaReference(localIdentifier: identifier, kind: kind, sortOrder: order)
        media.id = fixedID(id)
        media.caption = caption
        media.itineraryItem = item
        item.media.append(media)
    }

    private static func makeStoryDay(
        id: Int,
        date: Date,
        title: String,
        order: Int,
        sourceDayID: UUID?,
        story: TravelStory
    ) -> StoryDay {
        let result = StoryDay(date: date, title: title, sortOrder: order, sourceDayID: sourceDayID, story: story)
        result.id = fixedID(id)
        return result
    }

    private static func makeStoryEntry(
        id: Int,
        title: String,
        category: PlaceCategory,
        time: String,
        address: String,
        coordinate: (Double?, Double?),
        note: String,
        route: String,
        order: Int,
        sourceItemID: UUID?,
        story: TravelStory,
        day: StoryDay
    ) -> StoryEntry {
        let result = StoryEntry(title: title, category: category, sortOrder: order)
        result.id = fixedID(id)
        result.timeLabel = time
        result.address = address
        result.latitude = coordinate.0
        result.longitude = coordinate.1
        result.note = note
        result.routeInfo = route
        result.sourceItemID = sourceItemID
        result.story = story
        result.storyDay = day
        return result
    }

    private static func attachStoryMedia(
        id: Int,
        identifier: String,
        kind: MediaKind,
        caption: String,
        order: Int,
        to entry: StoryEntry
    ) {
        let media = MediaReference(localIdentifier: identifier, kind: kind, sortOrder: order)
        media.id = fixedID(id)
        media.caption = caption
        media.storyEntry = entry
        entry.media.append(media)
    }

    private static func fixedID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
    }
}
#endif
