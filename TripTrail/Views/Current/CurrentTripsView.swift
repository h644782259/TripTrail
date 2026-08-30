import Combine
import SwiftData
import SwiftUI

struct CurrentTripsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Trip.startDate, order: .forward) private var trips: [Trip]
    @State private var showsNewTrip = false
    @State private var tripToDelete: Trip?
    private let completionTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                hero
                if trips.isEmpty {
                    ContentUnavailableView {
                        Label("下一站，去哪里？", systemImage: "suitcase.rolling.fill")
                    } description: {
                        Text("新建旅行，按天安排地点、交通和照片。")
                    } actions: {
                        Button("创建第一段旅程") { showsNewTrip = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(minHeight: 320)
                } else {
                    ForEach(listTrips) { trip in
                        tripCard(trip)
                    }
                }
            }
            .padding()
        }
        .background(Color.tripCanvas)
        .navigationTitle("当前行程")
        .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsNewTrip = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showsNewTrip, onDismiss: { completeElapsedItems() }) { TripEditorView() }
        .alert(
            HierarchyDeletionCopy.tripTitle,
            isPresented: Binding(
                get: { tripToDelete != nil },
                set: { if !$0 { tripToDelete = nil } }
            ),
            presenting: tripToDelete
        ) { trip in
            Button(HierarchyDeletionCopy.confirmationButtonTitle, role: .destructive) {
                modelContext.delete(trip)
                tripToDelete = nil
            }
            Button(HierarchyDeletionCopy.cancelButtonTitle, role: .cancel) { tripToDelete = nil }
        } message: { trip in
            Text(HierarchyDeletionCopy.tripMessage(title: trip.title))
        }
        .onAppear { completeElapsedItems() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                completeElapsedItems()
            }
        }
        .onReceive(completionTimer) { date in
            completeElapsedItems(relativeTo: date)
        }
    }

    private var orderedTrips: [Trip] {
        TripTimelineOrdering.sorted(trips)
    }

    private var featuredTrip: Trip? {
        TripTimelineOrdering.featured(in: trips)
    }

    private var listTrips: [Trip] {
        guard let featuredTrip else { return orderedTrips }
        return orderedTrips.filter { $0.id != featuredTrip.id }
    }

    private func completeElapsedItems(relativeTo date: Date = Date()) {
        for day in trips.flatMap(\.days) {
            day.completeElapsedItems(relativeTo: date)
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let featuredTrip {
            tripCard(featuredTrip, isFeatured: true)
        } else {
            emptyHero
        }
    }

    private func tripCard(_ trip: Trip, isFeatured: Bool = false) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: trip) {
                if isFeatured {
                    FeaturedTripHero(trip: trip)
                } else {
                    TripCard(trip: trip)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开这段旅程")

            Menu {
                Button("删除行程", systemImage: "trash", role: .destructive) {
                    tripToDelete = trip
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.tripInk.opacity(0.72))
            .padding(12)
            .accessibilityLabel("\(trip.title)更多操作")
        }
        .contextMenu {
            Button("删除行程", systemImage: "trash", role: .destructive) {
                tripToDelete = trip
            }
        }
    }

    private var emptyHero: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("把期待排进日历")
                    .font(.title2.bold())
                Text("路线、照片和回忆，都在一处。")
                    .font(.subheadline)
                    .foregroundStyle(Color.tripInk.opacity(0.66))
            }
            Spacer()
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(Color.tripLake)
        }
        .foregroundStyle(Color.tripInk)
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background { journeyBackground }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.tripMist.opacity(0.46), lineWidth: 0.8)
        }
        .shadow(color: Color.tripInk.opacity(0.07), radius: 18, y: 8)
    }

    private var journeyBackground: some View {
        Image("JourneyLakeHero")
            .resizable()
            .scaledToFill()
            .overlay(Color.white.opacity(0.06))
    }
}

private struct FeaturedTripHero: View {
    let trip: Trip

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var startDate: Date { calendar.startOfDay(for: trip.startDate) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("JourneyLakeHero")
                .resizable()
                .scaledToFill()

            HStack(alignment: .top, spacing: 18) {
                calendarTile

                VStack(alignment: .leading, spacing: 7) {
                    Label(eyebrowText, systemImage: "calendar.badge.clock")
                        .font(.caption.bold())
                        .foregroundStyle(Color.tripLake)

                    Text(countdownText)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.tripInk)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)

                    Text(trip.title)
                        .font(.headline)
                        .foregroundStyle(Color.tripInk.opacity(0.90))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(destinationAndDates)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.tripInk.opacity(0.66))
                }

                Spacer(minLength: 0)
            }
            .padding(.trailing, 38)
            .padding(20)
        }
        .frame(maxWidth: .infinity, minHeight: 238, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.tripMist.opacity(0.48), lineWidth: 0.8)
        }
        .shadow(color: Color.tripInk.opacity(0.08), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
    }

    private var calendarTile: some View {
        VStack(spacing: 1) {
            Text(startDate.formatted(.dateTime.month(.abbreviated)))
                .font(.caption2.bold())
                .textCase(.uppercase)
            Text(String(calendar.component(.day, from: startDate)))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
            Text(startDate.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2.bold())
        }
        .foregroundStyle(Color.tripLake)
        .frame(width: 68, height: 78)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.tripLake.opacity(0.24))
                .frame(width: 28, height: 4)
                .padding(.top, 7)
        }
    }

    private var eyebrowText: String {
        startDate > today ? "下一段旅程" : "当前旅程"
    }

    private var countdownText: String {
        if startDate > today {
            let days = calendar.dateComponents([.day], from: today, to: startDate).day ?? 0
            return days == 1 ? "明天出发" : "还有 \(days) 天"
        }
        let journeyDay = (calendar.dateComponents([.day], from: startDate, to: today).day ?? 0) + 1
        return "旅行第 \(journeyDay) 天"
    }

    private var destinationAndDates: String {
        let dateRange = "\(trip.startDate.compactDayText) — \(trip.endDate.compactDayText)"
        guard !trip.destination.isEmpty else { return dateRange }
        return "\(trip.destination) · \(dateRange)"
    }
}

private struct TripCard: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(trip.title).font(.title3.bold()).foregroundStyle(.primary)
                    Label(trip.destination.isEmpty ? "待确定目的地" : trip.destination, systemImage: "mappin.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 48)
                Text(statusText)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(statusColor)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }
            .padding(.trailing, 42)
            HStack {
                Label("\(trip.startDate.compactDayText) — \(trip.endDate.compactDayText)", systemImage: "calendar")
                Spacer()
                Text("\(trip.completedCount)/\(trip.totalCount) 已完成")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: trip.progress)
                .tint(.tripSage)
        }
        .cardSurface()
    }

    private var statusText: String {
        switch TripTimelineOrdering.phase(for: trip) {
        case .current: "旅行中"
        case .upcoming: "即将出发"
        case .history: "待归档"
        }
    }

    private var statusColor: Color {
        statusText == "旅行中" ? Color.tripSage : (statusText == "即将出发" ? Color.tripLake : Color.secondary)
    }
}

struct TripEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let trip: Trip?
    @State private var title: String
    @State private var destination: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var note: String

    init(trip: Trip? = nil) {
        self.trip = trip
        _title = State(initialValue: trip?.title ?? "")
        _destination = State(initialValue: trip?.destination ?? "")
        _startDate = State(initialValue: trip?.startDate ?? Date())
        _endDate = State(initialValue: trip?.endDate ?? Calendar.current.date(byAdding: .day, value: 2, to: Date())!)
        _note = State(initialValue: trip?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("这次旅行") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("旅程名称")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("例如：初秋杭州三日", text: $title)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("目的地")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("例如：杭州", text: $destination)
                    }
                    .padding(.vertical, 4)

                    TwoTapDateRangePicker(
                        title: "旅行日期",
                        startTitle: "出发",
                        endTitle: "返程",
                        startDate: startDateSelection,
                        endDate: $endDate
                    )
                }
                Section("备注") {
                    TextField("同行人、旅行主题或准备事项", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(trip == nil ? "新建旅程" : "编辑旅程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var startDateSelection: Binding<Date> {
        Binding(
            get: { startDate },
            set: { newStartDate in
                let shiftedEndDate = JourneyHierarchyService.shiftedDate(
                    endDate,
                    whenTripStartMovesFrom: startDate,
                    to: newStartDate
                )
                startDate = newStartDate
                endDate = max(newStartDate, shiftedEndDate)
            }
        )
    }

    private func save() {
        let calendar = Calendar.current
        if let trip {
            let normalizedStartDate = calendar.startOfDay(for: startDate)
            JourneyHierarchyService.updateTripDateRange(
                trip,
                startDate: normalizedStartDate,
                endDate: endDate,
                calendar: calendar
            )
            trip.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            trip.destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            trip.note = note
        } else {
            let newTrip = Trip(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: calendar.startOfDay(for: startDate),
                endDate: calendar.startOfDay(for: endDate),
                note: note
            )
            modelContext.insert(newTrip)
            for seed in JourneyHierarchyService.daySeeds(from: startDate, through: endDate, calendar: calendar) {
                let day = TripDay(
                    date: seed.date,
                    title: seed.title,
                    sortOrder: seed.sortOrder,
                    trip: newTrip
                )
                newTrip.days.append(day)
            }
        }
        dismiss()
    }
}
