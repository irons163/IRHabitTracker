//
//  ContentView.swift
//  IRHabitTracker
//
//  Created by Phil on 2025/10/11.
//

import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

#if canImport(WidgetKit)
    import WidgetKit
#endif

// MARK: - App Group (replace with your real one in Signing & Capabilities)
let APP_GROUP_ID = "group.yourcompany.habittracker"  // TODO: set actual App Group ID

// MARK: - Models
@Model
final class Habit: Identifiable {
    @Attribute(
        .unique
    ) var id: UUID
    var title: String
    var icon: String  // SF Symbol
    var colorHex: String
    var notes: String
    var createdAt: Date
    var targetPerDay: Int
    /// One element = one completion unit at that startOfDay
    var completions: [Date]
    // Reminders
    var remindEnabled: Bool = false
    var reminderHour: Int = 9
    var reminderMinute: Int = 0
    // Tags
    var tags: [String] = []

    init(
        title: String,
        icon: String = "checkmark.circle",
        color: Color = .blue,
        notes: String = "",
        targetPerDay: Int = 1,
        tags: [String] = []
    ) {
        self.id = UUID()
        self.title = title
        self.icon = icon
        self.colorHex = color.hex
        self.notes = notes
        self.createdAt = .now
        self.targetPerDay = max(
            1,
            targetPerDay
        )
        self.completions = []
        self.tags = tags
    }

    // MARK: Convenience
    var color: Color {
        Color(
            hex: colorHex
        )
    }
    var tagsDisplay: String {
        tags.joined(
            separator: ", "
        )
    }

    func count(
        on day: Date,
        cal: Calendar = .current
    ) -> Int {
        completions
            .filter {
                cal.isDate(
                    $0,
                    inSameDayAs: day
                )
            }.count
    }
    func isCompleted(
        on day: Date,
        cal: Calendar = .current
    ) -> Bool {
        count(
            on: day,
            cal: cal
        ) >= targetPerDay
    }

    func increment(
        on day: Date = .now,
        cal: Calendar = .current
    ) {
        completions.append(
            day.startOfDay(
                cal
            )
        )
        syncForWidget()
    }
    func decrement(
        on day: Date = .now,
        cal: Calendar = .current
    ) {
        if let idx = completions.lastIndex(
            where: {
                cal.isDate(
                    $0,
                    inSameDayAs: day
                )
            })
        {
            completions.remove(
                at: idx
            )
            syncForWidget()
        }
    }

    var todayCount: Int {
        count(
            on: .now
        )
    }
    var isDoneToday: Bool {
        todayCount >= targetPerDay
    }

    var currentStreak: Int {
        var streak = 0
        let cal = Calendar.current
        var d = Date().startOfDay(
            cal
        )
        while isCompleted(
            on: d,
            cal: cal
        ) {
            streak += 1
            d = cal.date(
                byAdding: .day,
                value: -1,
                to: d
            )!
        }
        return streak
    }

    func weeklyProgress(
        endingAt end: Date = .now,
        cal: Calendar = .current
    ) -> [(
        date: Date,
        done: Bool
    )] {
        let endDay = end.startOfDay(
            cal
        )
        return (0..<7).reversed()
            .map {
                off in
                let d = cal.date(
                    byAdding: .day,
                    value: -off,
                    to: endDay
                )!
                return (
                    d,
                    isCompleted(
                        on: d,
                        cal: cal
                    )
                )
            }
    }

    // Rates
    func completionRate(
        from start: Date,
        to end: Date,
        cal: Calendar = .current
    ) -> Double {
        guard start <= end else {
            return 0
        }
        var days = 0
        var completed = 0
        var d = start.startOfDay(
            cal
        )
        let endD = end.startOfDay(
            cal
        )
        while d <= endD {
            days += 1
            if isCompleted(
                on: d,
                cal: cal
            ) {
                completed += 1
            }
            d = cal.date(
                byAdding: .day,
                value: 1,
                to: d
            )!
        }
        return days == 0
            ? 0
            : Double(
                completed
            )
                / Double(
                    days
                )
    }
    func weeklyRate(
        reference: Date = .now
    ) -> Double {
        let cal = Calendar.current
        let end = reference.startOfDay(
            cal
        )
        let start = cal.date(
            byAdding: .day,
            value: -6,
            to: end
        )!
        return completionRate(
            from: start,
            to: end,
            cal: cal
        )
    }
    func monthlyRate(
        reference: Date = .now
    ) -> Double {
        let cal = Calendar.current
        let comp = cal.dateComponents(
            [
                .year,
                .month,
            ],
            from: reference
        )
        let start = cal.date(
            from: comp
        )!
        let next = cal.date(
            byAdding: .month,
            value: 1,
            to: start
        )!
        let end = cal.date(
            byAdding: .day,
            value: -1,
            to: next.startOfDay(
                cal
            )
        )!
        return completionRate(
            from: start,
            to: end,
            cal: cal
        )
    }

    // MARK: Reminder helpers
    var reminderDateComponents: DateComponents {
        var dc = DateComponents()
        dc.hour = reminderHour
        dc.minute = reminderMinute
        return dc
    }
    func scheduleReminder() {
        guard remindEnabled else {
            cancelReminder()
            return
        }
        let c = UNMutableNotificationContent()
        c.title = "Habit Reminder"
        c.body = "Mark \(title) for today."
        c.sound = .default
        let t = UNCalendarNotificationTrigger(
            dateMatching: reminderDateComponents,
            repeats: true
        )
        let req = UNNotificationRequest(
            identifier: "habit-\(id.uuidString)",
            content: c,
            trigger: t
        )
        UNUserNotificationCenter.current().add(
            req
        )
    }
    func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["habit-\(id.uuidString)"]
        )
    }

    // MARK: Widget sync (App Group UserDefaults)
    func syncForWidget() {
        guard
            let ud = UserDefaults(
                suiteName: APP_GROUP_ID
            )
        else {
            return
        }
        let cal = Calendar.current
        let today = Date().startOfDay(
            cal
        )
        let payload: [String: Any] = [
            "id": id.uuidString,
            "title": title,
            "icon": icon,
            "colorHex": colorHex,
            "date": ISO8601DateFormatter()
                .string(
                    from: today
                ),
            "todayCount": todayCount,
            "targetPerDay": targetPerDay,
        ]
        ud
            .set(
                payload,
                forKey: "widget.primaryHabit"
            )
        ud
            .synchronize()
        #if canImport(WidgetKit)
            WidgetCenter.shared
                .reloadAllTimelines()
        #endif
    }
}

// MARK: - Codable snapshot for export/import
struct HabitSnapshot: Codable {
    struct HabitItem: Codable {
        var id: UUID
        var title: String
        var icon: String
        var colorHex: String
        var notes: String
        var createdAt: Date
        var targetPerDay: Int
        var completions: [Date]
        var remindEnabled: Bool
        var reminderHour: Int
        var reminderMinute: Int
        var tags: [String]
    }
    var exportedAt: Date
    var items: [HabitItem]
    static func fromModel(
        _ habits: [Habit]
    ) -> HabitSnapshot {
        .init(
            exportedAt: .now,
            items: habits.map {
                h in
                .init(
                    id: h.id,
                    title: h.title,
                    icon: h.icon,
                    colorHex: h.colorHex,
                    notes: h.notes,
                    createdAt: h.createdAt,
                    targetPerDay: h.targetPerDay,
                    completions: h.completions,
                    remindEnabled: h.remindEnabled,
                    reminderHour: h.reminderHour,
                    reminderMinute: h.reminderMinute,
                    tags: h.tags
                )
            })
    }
}

// MARK: - Root with Search/Sort/Leaderboard
struct RootView: View {
    @Environment(
        \.modelContext
    ) private var ctx
    @Query(
        sort: \Habit.createdAt,
        order: .reverse
    ) private var habits: [Habit]
    @State private var showNew = false
    @State private var search = ""
    @State private var sort: SortKey = .newest
    @State private var layout: LayoutMode = .list
    @State private var selection: Habit? = nil

    // Export / Import
    @State private var exportDoc: JSONDoc? = nil
    @State private var showImporter = false

    enum SortKey: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case
            streak = "Streak"
        case
            weekly = "Weekly %"
        var id: String {
            rawValue
        }
    }

    enum LayoutMode: CaseIterable {
        case list, grid2, listTall
        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .grid2: return "square.grid.2x2"
            case .listTall: return "list.bullet.rectangle.portrait"
            }
        }
        mutating func toggle() {
            let all = Self.allCases
            if let i = all.firstIndex(of: self) {
                self = all[(i + 1) % all.count]
            }
        }
    }

    var filtered: [Habit] {
        let s = search.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        let base =
            s.isEmpty
            ? habits
            : habits.filter {
                h in
                h.title.lowercased().contains(
                    s
                )
                    || h.tags.joined(
                        separator: ","
                    ).lowercased().contains(
                        s
                    )
            }
        switch sort {
        case .newest:
            return base.sorted {
                $0.createdAt > $1.createdAt
            }
        case .streak:
            return base.sorted {
                $0.currentStreak > $1.currentStreak
            }
        case .weekly:
            return base.sorted {
                $0.weeklyRate() > $1.weeklyRate()
            }
        }
    }

    var body: some View {
        NavigationStack {
            if habits.isEmpty {
                EmptyState {
                    showNew = true
                }
                .navigationTitle(
                    "Habits"
                )
                .toolbar(
                    content: {
                        toolbarItems
                    })
            } else {
                List {
                    let top = habits.sorted(
                        by: {
                            $0.currentStreak > $1.currentStreak
                        }).prefix(
                            3
                        )
                    if !top.isEmpty {
                        Section("Leaderboard (Streak)") {
                            ForEach(
                                top
                            ) {
                                StreakRow(
                                    habit: $0
                                )
                            }
                        }
                    }
                    Section {
                        switch layout {
                        case .list:
                            ForEach(filtered) { h in
                                NavigationLink(value: h) { HabitRow(habit: h) }
                            }
                            .onDelete { idx in
                                idx.map { filtered[$0] }.forEach(ctx.delete)
                            }
                        case .grid2:
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                ], spacing: 12
                            ) {
                                ForEach(filtered, id: \.id) { h in
                                    Button {
                                        selection = h
                                    } label: {
                                        HabitGridCard(habit: h).contentShape(
                                            Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            ctx.delete(h)
                                            try? ctx.save()
                                        } label: {
                                            Label(
                                                "Delete", systemImage: "trash")
                                        }
                                        Button {
                                            withAnimation(.snappy) {
                                                h.increment()
                                            }
                                        } label: {
                                            Label(
                                                "+1 today",
                                                systemImage: "plus.circle")
                                        }
                                        if h.todayCount > 0 {
                                            Button {
                                                withAnimation(.snappy) {
                                                    h.decrement()
                                                }
                                            } label: {
                                                Label(
                                                    "-1 today",
                                                    systemImage: "minus.circle")
                                            }
                                        }
                                    }
                                }
                            }
                        case .listTall:
                            ForEach(filtered) { h in
                                NavigationLink(value: h) {
                                    HabitTallRow(habit: h)
                                }
                            }
                            .onDelete { idx in
                                idx.map { filtered[$0] }.forEach(ctx.delete)
                            }
                        }
                    } header: {
                        HStack {
                            Text(
                                "All Habits"
                            )
                            Spacer()
                            Picker(
                                "Sort",
                                selection: $sort
                            ) {
                                ForEach(
                                    SortKey.allCases
                                ) {
                                    Text(
                                        $0.rawValue
                                    ).tag(
                                        $0
                                    )
                                }
                            }.pickerStyle(
                                .segmented
                            ).frame(
                                maxWidth: 260
                            )
                            Button {
                                layout.toggle()
                            } label: {
                                Image(systemName: layout.icon)
                            }
                        }
                    }
                }
                .navigationDestination(for: Habit.self) {
                    HabitDetailView(habit: $0)
                }
                .navigationDestination(item: $selection) {
                    HabitDetailView(habit: $0)
                }
                .navigationTitle(
                    "Habits"
                )
                .toolbar {
                    toolbarItems
                }
                .searchable(
                    text: $search,
                    placement: .navigationBarDrawer(
                        displayMode: .always
                    ),
                    prompt: "Search title or tags…"
                )
            }
        }
        .sheet(
            isPresented: $showNew
        ) {
            NewHabitSheet()
        }
        .task {
            await NotificationManager.requestAuthorizationIfNeeded()
        }
        .fileExporter(
            isPresented: Binding(
                get: {
                    exportDoc != nil
                },
                set: {
                    if !$0 {
                        exportDoc = nil
                    }
                }),
            document: exportDoc,
            contentType: .json,
            defaultFilename:
                "HabitExport-\(Date().formatted(.iso8601.year().month().day()))"
        ) {
            _ in
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json])
        { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }

                let data = try Data(contentsOf: url)
                let snap = try JSONDecoder().decode(
                    HabitSnapshot.self, from: data)
                try importSnapshot(snap)
            } catch {
                print("Import error: \(error)")
            }
        }
    }

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        ToolbarItem(
            placement: .topBarLeading
        ) {
            Menu {
                Button(
                    "Export JSON"
                ) {
                    let snap = HabitSnapshot.fromModel(
                        habits
                    )
                    if let data = try? JSONEncoder().encode(
                        snap
                    ) {
                        exportDoc = JSONDoc(
                            data: data
                        )
                    }
                }
                Button(
                    "Import JSON"
                ) {
                    showImporter = true
                }
            } label: {
                Label(
                    "Data",
                    systemImage: "square.and.arrow.up"
                )
            }
        }
        ToolbarItem(
            placement: .topBarTrailing
        ) {
            Button {
                showNew = true
            } label: {
                Label(
                    "New Habit",
                    systemImage: "plus"
                )
            }
        }
    }

    private func importSnapshot(
        _ snap: HabitSnapshot
    ) throws {
        let existing = Dictionary(
            uniqueKeysWithValues: habits.map {
                (
                    $0.id,
                    $0
                )
            })
        for it in snap.items {
            if let h = existing[it.id] {
                h.title = it.title
                h.icon = it.icon
                h.colorHex = it.colorHex
                h.notes = it.notes
                h.createdAt = it.createdAt
                h.targetPerDay = it.targetPerDay
                h.completions = it.completions
                h.remindEnabled = it.remindEnabled
                h.reminderHour = it.reminderHour
                h.reminderMinute = it.reminderMinute
                h.tags = it.tags
                if h.remindEnabled {
                    h.scheduleReminder()
                } else {
                    h.cancelReminder()
                }
            } else {
                let h = Habit(
                    title: it.title,
                    icon: it.icon,
                    color: Color(
                        hex: it.colorHex
                    ),
                    notes: it.notes,
                    targetPerDay: it.targetPerDay,
                    tags: it.tags
                )
                h.id = it.id
                h.createdAt = it.createdAt
                h.completions = it.completions
                h.remindEnabled = it.remindEnabled
                h.reminderHour = it.reminderHour
                h.reminderMinute = it.reminderMinute
                if h.remindEnabled {
                    h.scheduleReminder()
                }
                ctx
                    .insert(
                        h
                    )
            }
        }
        try ctx
            .save()
    }
}

extension RootView {

    // MARK: - Rows & Components
    struct HabitGridCard: View {
        let habit: Habit
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: habit.icon)
                    Text(habit.title).font(.subheadline.weight(.semibold))
                    Spacer()
                }
                ProgressView(
                    value: min(
                        Double(habit.todayCount)
                            / Double(max(1, habit.targetPerDay)), 1))
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                    Text("\(habit.currentStreak)")
                    Spacer()
                    Text("\(habit.todayCount)/\(habit.targetPerDay)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(habit.color.opacity(0.08), in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(
                    .quaternary, lineWidth: 1))
        }
    }

    struct HabitTallRow: View {
        let habit: Habit
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: habit.icon).foregroundStyle(habit.color)
                    Text(habit.title).font(.headline)
                    Spacer()
                    Text("\(habit.todayCount)/\(habit.targetPerDay)").font(
                        .subheadline
                    ).foregroundStyle(.secondary)
                }
                ProgressView(
                    value: min(
                        Double(habit.todayCount)
                            / Double(max(1, habit.targetPerDay)), 1))
                HStack(spacing: 8) {
                    StreakBadge(streak: habit.currentStreak, color: habit.color)
                    if !habit.tags.isEmpty {
                        Text(habit.tags.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    WeekStripStatic(weeks: habit.weeklyProgress())
                }
            }
            .padding(.vertical, 8)
        }
    }

    struct StreakBadge: View {
        let streak: Int
        let color: Color
        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                Text("\(streak)")
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: .capsule)
            .foregroundStyle(color)
        }
    }
}

// MARK: - Rows & Components
struct EmptyState: View {
    var onTap: () -> Void
    var body: some View {
        VStack(
            spacing: 16
        ) {
            Image(
                systemName: "checklist"
            ).font(
                .system(
                    size: 64
                )
            ).foregroundStyle(
                .secondary
            )
            Text(
                "Build better days"
            ).font(
                .title.bold()
            )
            Text(
                "Create your first habit and track your streaks."
            ).foregroundStyle(
                .secondary
            )
            Button(
                action: onTap
            ) {
                Label(
                    "New Habit",
                    systemImage: "plus"
                )
            }.buttonStyle(
                .borderedProminent
            )
        }.padding()
    }
}

struct StreakRow: View {
    let habit: Habit
    var body: some View {
        HStack {
            Image(
                systemName: habit.icon
            ).frame(
                width: 20
            )
            Text(
                habit.title
            )
            Spacer()
            Label(
                "\(habit.currentStreak)",
                systemImage: "flame.fill"
            ).labelStyle(
                .titleAndIcon
            )
        }.foregroundStyle(
            habit.color
        )
    }
}

struct HabitRow: View {
    let habit: Habit
    var body: some View {
        HStack(
            spacing: 12
        ) {
            ProgressRing(
                progress: min(
                    Double(
                        habit.todayCount
                    )
                        / Double(
                            max(
                                1,
                                habit.targetPerDay
                            )
                        ),
                    1
                ),
                color: habit.color,
                icon: habit.icon
            )
            .frame(
                width: 36,
                height: 36
            )
            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                HStack {
                    Text(
                        habit.title
                    )
                    if !habit.tags.isEmpty {
                        Text(
                            "· "
                        )
                            + Text(
                                habit.tagsDisplay
                            ).font(
                                .caption
                            ).foregroundStyle(
                                .secondary
                            )
                    }
                }
                WeekStripStatic(
                    weeks: habit.weeklyProgress()
                )
            }
            Spacer()
            Text(
                "\(habit.todayCount)/\(habit.targetPerDay)"
            )
            .font(
                .footnote
            )
            .foregroundStyle(
                .secondary
            )
        }
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            "\(habit.title), streak \(habit.currentStreak) days"
        )
    }
}

struct ProgressRing: View {
    var progress: Double
    var color: Color
    var icon: String
    var body: some View {
        ZStack {
            Circle().stroke(
                .quaternary,
                lineWidth: 6
            )
            Circle().trim(
                from: 0,
                to: progress
            ).stroke(
                color,
                style: .init(
                    lineWidth: 6,
                    lineCap: .round
                )
            ).rotationEffect(
                .degrees(
                    -90
                )
            )
            Image(
                systemName: icon
            ).imageScale(
                .small
            )
        }
    }
}
struct WeekStripStatic: View {
    let weeks:
        [(
            date: Date,
            done: Bool
        )]
    var body: some View {
        HStack(
            spacing: 4
        ) {
            ForEach(
                weeks,
                id: \.date
            ) {
                it in
                Circle().fill(
                    it.done ? .primary : Color.clear
                ).opacity(
                    it.done ? 0.9 : 0
                ).overlay(
                    Circle().strokeBorder(
                        .quaternary,
                        lineWidth: 1
                    )
                ).frame(
                    width: 8,
                    height: 8
                )
            }
        }
    }
}

// MARK: - Detail + Calendar
struct HabitDetailView: View {
    @Environment(
        \.dismiss
    ) private var dismiss
    @Environment(
        \.modelContext
    ) private var ctx
    @Bindable var habit: Habit
    @State private var showEdit = false
    @State private var monthStart = Date().startOfMonth

    var body: some View {
        List {
            Section(
                "Overview"
            ) {
                HStack {
                    Label(
                        "Created",
                        systemImage: "calendar"
                    )
                    Spacer()
                    Text(
                        habit.createdAt.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )
                }
                HStack {
                    Label(
                        "Target / day",
                        systemImage: "target"
                    )
                    Spacer()
                    Text(
                        "\(habit.targetPerDay)"
                    )
                }
                HStack {
                    Label(
                        "Current streak",
                        systemImage: "flame.fill"
                    )
                    Spacer()
                    Text(
                        "\(habit.currentStreak)"
                    )
                }
            }
            Section(
                "Today"
            ) {
                HStack {
                    ProgressRing(
                        progress: min(
                            Double(
                                habit.todayCount
                            )
                                / Double(
                                    max(
                                        1,
                                        habit.targetPerDay
                                    )
                                ),
                            1
                        ),
                        color: habit.color,
                        icon: habit.icon
                    ).frame(
                        width: 56,
                        height: 56
                    )
                    Stepper(
                        "Count: \(habit.todayCount)",
                        onIncrement: {
                            habit.increment()
                        },
                        onDecrement: {
                            habit.decrement()
                        })
                }
            }
            Section(
                "Calendar"
            ) {
                MonthCalendar(
                    habit: habit,
                    monthStart: monthStart
                )
                HStack {
                    Button {
                        withAnimation {
                            monthStart = Calendar.current.date(
                                byAdding: .month,
                                value: -1,
                                to: monthStart
                            )!
                        }
                    } label: {
                        Label(
                            "Prev",
                            systemImage: "chevron.left"
                        )
                    }
                    Spacer()
                    Text(
                        monthStart,
                        format: .dateTime.year().month()
                    )
                    Spacer()
                    Button {
                        withAnimation {
                            monthStart = Calendar.current.date(
                                byAdding: .month,
                                value: 1,
                                to: monthStart
                            )!
                        }
                    } label: {
                        Label(
                            "Next",
                            systemImage: "chevron.right"
                        )
                    }
                }
            }
            Section(
                "Trends"
            ) {
                HStack {
                    StatPill(
                        title: "Weekly",
                        value: habit.weeklyRate().formatted(
                            .percent.precision(
                                .fractionLength(
                                    0
                                )
                            )
                        )
                    )
                    StatPill(
                        title: "Monthly",
                        value: habit.monthlyRate().formatted(
                            .percent.precision(
                                .fractionLength(
                                    0
                                )
                            )
                        )
                    )
                }
                HabitCountChart(
                    habit: habit,
                    days: 30
                )
                .frame(
                    height: 180
                )
            }
            if !habit.notes.isEmpty {
                Section(
                    "Notes"
                ) {
                    Text(
                        habit.notes
                    )
                }
            }
            Section(
                "Danger Zone"
            ) {
                Button(
                    role: .destructive
                ) {
                    ctx.delete(
                        habit
                    )
                    try? ctx.save()
                    dismiss()
                } label: {
                    Label(
                        "Delete Habit",
                        systemImage: "trash"
                    )
                }
            }
        }
        .navigationTitle(
            habit.title
        )
        .toolbar {
            ToolbarItem(
                placement: .topBarTrailing
            ) {
                Button {
                    showEdit = true
                } label: {
                    Label(
                        "Edit",
                        systemImage: "pencil"
                    )
                }
            }
        }
        .sheet(
            isPresented: $showEdit
        ) {
            EditHabitSheet(
                habit: habit
            )
        }
        .onAppear {
            habit.syncForWidget()
        }
    }
}

struct MonthCalendar: View {
    @Bindable var habit: Habit
    var monthStart: Date

    private func rotatedWeekdaySymbols(cal: Calendar) -> [String] {
        let df = DateFormatter()
        df.locale = cal.locale
        // 預設 Foundation 的 weekday 符號順序為從星期日開始
        let base = df.veryShortStandaloneWeekdaySymbols
            ?? df.shortStandaloneWeekdaySymbols
            ?? df.shortWeekdaySymbols ?? []
        guard base.count == 7 else { return ["S","M","T","W","T","F","S"] }
        let start = cal.firstWeekday - 1 // 轉為 0...6
        return Array(base[start...] + base[..<start])
    }

    var body: some View {
        let cal = Calendar.current
        let first = monthStart.startOfMonth

        // 當月天數範圍
        let range = cal.range(of: .day, in: .month, for: first) ?? 1..<31

        // 0...6（0=Sunday, 6=Saturday）
        let weekdayIndex0 = cal.component(.weekday, from: first) - 1
        let firstWeekdayIndex0 = cal.firstWeekday - 1
        // 前置空白：將當月第一天對齊到使用者的一週起始日
        let prefix = (weekdayIndex0 - firstWeekdayIndex0 + 7) % 7

        let days = Array(repeating: 0, count: prefix) + Array(range)

        LazyVGrid(
            columns: Array(
                repeating: GridItem(
                    .flexible(),
                    spacing: 6
                ),
                count: 7
            ),
            spacing: 6
        ) {
            // 星期標頭（在地化並依 firstWeekday 旋轉）
            let syms = rotatedWeekdaySymbols(cal: cal)
            ForEach(Array(syms.enumerated()), id: \.offset) { _, sym in
                Text(sym)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(
                0..<days.count,
                id: \.self
            ) { idx in
                if days[idx] == 0 {
                    Color.clear
                        .frame(
                            height: 30
                        )
                } else {
                    let dayDate = cal.date(
                        byAdding: .day,
                        value: days[idx] - 1,
                        to: first
                    )!
                    let done = habit.isCompleted(
                        on: dayDate,
                        cal: cal
                    )
                    Text(
                        "\(days[idx])"
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 30
                    )
                    .padding(
                        6
                    )
                    .background(
                        done
                            ? habit.color.opacity(
                                0.2
                            ) : Color.clear,
                        in: .rect(
                            cornerRadius: 8
                        )
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: 8
                        ).stroke(
                            .quaternary,
                            lineWidth: 1
                        )
                    )
                    .onTapGesture {
                        withAnimation(
                            .snappy
                        ) {
                            if done {
                                habit.decrement(
                                    on: dayDate
                                )
                            } else {
                                habit.increment(
                                    on: dayDate
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

struct StatPill: View {
    var title: String
    var value: String
    var body: some View {
        VStack(
            spacing: 4
        ) {
            Text(
                title
            ).font(
                .caption
            ).foregroundStyle(
                .secondary
            )
            Text(
                value
            ).font(
                .headline
            )
        }.padding(
            .horizontal,
            12
        ).padding(
            .vertical,
            8
        ).background(
            .thinMaterial,
            in: .capsule
        )
    }
}

// MARK: - Charts
struct HabitCountChart: View {
    @Bindable var habit: Habit
    var days: Int = 30
    var body: some View {
        let cal = Calendar.current
        let end = Date().startOfDay(
            cal
        )
        let series:
            [(
                Date,
                Int
            )] = (0..<days).reversed().map {
                off in
                let d = cal.date(
                    byAdding: .day,
                    value: -off,
                    to: end
                )!
                return (
                    d,
                    habit.count(
                        on: d,
                        cal: cal
                    )
                )
            }
        Chart(
            series,
            id: \.0
        ) {
            (
                date,
                cnt
            ) in
            BarMark(
                x: .value(
                    "Day",
                    date,
                    unit: .day
                ),
                y: .value(
                    "Count",
                    cnt
                )
            )
        }.chartXAxis {
            AxisMarks(
                values: .stride(
                    by: .day,
                    count: max(
                        1,
                        days / 6
                    )
                )
            ) {
                _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(
                    format: .dateTime.day(
                        .twoDigits
                    )
                )
            }
        }
    }
}

// MARK: - Create / Edit
struct NewHabitSheet: View {
    @Environment(
        \.dismiss
    ) private var dismiss
    @Environment(
        \.modelContext
    ) private var ctx
    @State private var title = ""
    @State private var icon = "checkmark.circle"
    @State private var color: Color = .blue
    @State private var notes = ""
    @State private var targetPerDay = 1
    @State private var tagsText = ""  // comma-separated
    @State private var remindEnabled = false
    @State private var remindTime = Calendar.current.date(
        bySettingHour: 9,
        minute: 0,
        second: 0,
        of: Date()
    )!

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    "Basics"
                ) {
                    TextField(
                        "Title",
                        text: $title
                    )
                    HStack {
                        Text(
                            "Icon"
                        )
                        Spacer()
                        Image(
                            systemName: icon
                        ).foregroundStyle(
                            color
                        )
                    }
                    .onTapGesture {
                        IconPicker(
                            selected: $icon
                        ).present()
                    }
                    ColorPicker(
                        "Color",
                        selection: $color,
                        supportsOpacity: false
                    )
                    TextField(
                        "Tags (comma separated)",
                        text: $tagsText
                    )
                }
                Stepper(
                    "Target per day: \(targetPerDay)",
                    value: $targetPerDay,
                    in: 1...50
                )
                Section(
                    "Notes"
                ) {
                    TextField(
                        "Optional notes",
                        text: $notes,
                        axis: .vertical
                    ).lineLimit(
                        3...6
                    )
                }
                Section(
                    "Reminder"
                ) {
                    Toggle(
                        "Enable daily reminder",
                        isOn: $remindEnabled
                    )
                    DatePicker(
                        "Time",
                        selection: $remindTime,
                        displayedComponents: .hourAndMinute
                    ).disabled(
                        !remindEnabled
                    )
                }
            }
            .navigationTitle(
                "New Habit"
            )
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button(
                        "Cancel",
                        action: {
                            dismiss()
                        })
                }
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        "Add"
                    ) {
                        add()
                    }.disabled(
                        title.trimmed.isEmpty
                    )
                }
            }
        }
    }

    private func add() {
        let tags = tagsText.split(
            separator: ","
        ).map {
            $0.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }.filter {
            !$0.isEmpty
        }
        let h = Habit(
            title: title.trimmed,
            icon: icon,
            color: color,
            notes: notes.trimmed,
            targetPerDay: targetPerDay,
            tags: tags
        )
        if remindEnabled {
            let c = Calendar.current.dateComponents(
                [
                    .hour,
                    .minute,
                ],
                from: remindTime
            )
            h.remindEnabled = true
            h.reminderHour = c.hour ?? 9
            h.reminderMinute = c.minute ?? 0
            h.scheduleReminder()
        }
        ctx
            .insert(
                h
            )
        try? ctx
            .save()
        h
            .syncForWidget()
        dismiss()
    }
}

struct EditHabitSheet: View {
    @Environment(
        \.dismiss
    ) private var dismiss
    @Bindable var habit: Habit
    @State private var iconSheet = false

    private var reminderDateBinding: Binding<Date> {
        Binding(
            get: {
                let cal = Calendar.current
                var c = DateComponents()
                c.hour = habit.reminderHour
                c.minute = habit.reminderMinute
                return cal.date(
                    from: c
                ) ?? cal.date(
                    bySettingHour: 9,
                    minute: 0,
                    second: 0,
                    of: Date()
                )!
            },
            set: {
                let comps = Calendar.current.dateComponents(
                    [
                        .hour,
                        .minute,
                    ],
                    from: $0
                )
                habit.reminderHour = comps.hour ?? 9
                habit.reminderMinute = comps.minute ?? 0
            })
    }

    @State private var tagsText: String = ""
    var body: some View {
        NavigationStack {
            Form {
                Section(
                    "Basics"
                ) {
                    TextField(
                        "Title",
                        text: $habit.title
                    )
                    HStack {
                        Text(
                            "Icon"
                        )
                        Spacer()
                        Image(
                            systemName: habit.icon
                        ).foregroundStyle(
                            habit.color
                        )
                    }
                    .onTapGesture {
                        iconSheet = true
                    }
                    ColorPicker(
                        "Color",
                        selection: Binding(
                            get: {
                                habit.color
                            },
                            set: {
                                habit.colorHex = $0.hex
                            }),
                        supportsOpacity: false
                    )
                    TextField(
                        "Tags (comma separated)",
                        text: Binding(
                            get: {
                                tagsText.isEmpty
                                    ? habit.tags.joined(
                                        separator: ", "
                                    ) : tagsText
                            },
                            set: {
                                tagsText = $0
                            })
                    )
                }
                Stepper(
                    "Target per day: \(habit.targetPerDay)",
                    value: $habit.targetPerDay,
                    in: 1...50
                )
                Section(
                    "Notes"
                ) {
                    TextField(
                        "Optional notes",
                        text: $habit.notes,
                        axis: .vertical
                    ).lineLimit(
                        3...6
                    )
                }
                Section(
                    "Reminder"
                ) {
                    Toggle(
                        "Enable daily reminder",
                        isOn: $habit.remindEnabled
                    )
                    DatePicker(
                        "Time",
                        selection: reminderDateBinding,
                        displayedComponents: .hourAndMinute
                    ).disabled(
                        !habit.remindEnabled
                    )
                }
            }
            .navigationTitle(
                "Edit Habit"
            )
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        "Done"
                    ) {
                        if !tagsText.isEmpty {
                            habit.tags = tagsText.split(
                                separator: ","
                            ).map {
                                $0.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            }.filter {
                                !$0.isEmpty
                            }
                        }
                        if habit.remindEnabled {
                            habit.scheduleReminder()
                        } else {
                            habit.cancelReminder()
                        }
                        habit.syncForWidget()
                        dismiss()
                    }
                }
            }
        }
        .sheet(
            isPresented: $iconSheet
        ) {
            IconPicker(
                selected: Binding(
                    get: {
                        habit.icon
                    },
                    set: {
                        habit.icon = $0
                    })
            )
        }
        .onAppear {
            tagsText = habit.tags.joined(
                separator: ", "
            )
        }
    }
}

// MARK: - Pickers & Utils
struct IconPicker: View {
    @Environment(
        \.dismiss
    ) private var dismiss
    @Binding var selected: String
    private let icons = [
        "checkmark.circle", "figure.walk", "flame", "leaf", "book", "bolt",
        "moon",
        "sun.max", "heart", "pencil", "dumbbell", "brain.head.profile", "drop",
        "bed.double", "bubble.left", "timer",
    ]
    init(
        selected: Binding<String>
    ) {
        self._selected = selected
    }
    func present() {
        _ = selected
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(
                    icons,
                    id: \.self
                ) {
                    name in
                    HStack {
                        Image(
                            systemName: name
                        ).frame(
                            width: 28
                        )
                        Text(
                            name
                        )
                        Spacer()
                        if name == selected {
                            Image(
                                systemName: "checkmark"
                            ).foregroundStyle(
                                .tint
                            )
                        }
                    }.contentShape(
                        Rectangle()
                    ).onTapGesture {
                        selected = name
                        dismiss()
                    }
                }
            }.navigationTitle(
                "Pick an Icon"
            ).toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button(
                        "Close",
                        action: {
                            dismiss()
                        })
                }
            }
        }
    }
}

enum NotificationManager {
    static func requestAuthorizationIfNeeded() async {
        let c = UNUserNotificationCenter.current()
        let s = await c.notificationSettings()
        guard s.authorizationStatus == .notDetermined else {
            return
        }
        _ = try? await c.requestAuthorization(
            options: [
                .alert,
                .sound,
                .badge,
            ]
        )
    }
}

// MARK: - File Export Helper
struct JSONDoc: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }
    var data: Data
    init(
        data: Data
    ) {
        self.data = data
    }
    init(
        configuration: ReadConfiguration
    ) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        .init(
            regularFileWithContents: data
        )
    }
}

// MARK: - Extensions
extension Date {
    func startOfDay(
        _ cal: Calendar = .current
    ) -> Date {
        cal.startOfDay(
            for: self
        )
    }
    var startOfMonth: Date {
        let cal = Calendar.current
        let comp = cal.dateComponents(
            [
                .year,
                .month,
            ],
            from: self
        )
        return
            cal
            .date(
                from: comp
            )!
    }
}
extension String {
    var trimmed: String {
        trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }
}
extension Color {
    init(
        hex: String
    ) {
        var s = hex.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted
        )
        if s.count == 3 {
            s = s.map {
                "\($0)\($0)"
            }.joined()
        }
        var n: UInt64 = 0
        Scanner(
            string: s
        )
        .scanHexInt64(
            &n
        )
        let r =
            Double(
                (n >> 16) & 0xFF
            ) / 255
        let g =
            Double(
                (n >> 8) & 0xFF
            ) / 255
        let b =
            Double(
                n & 0xFF
            ) / 255
        self = Color(
            red: r,
            green: g,
            blue: b
        )
    }
    var hex: String {
        #if canImport(UIKit)
            let ui = UIColor(
                self
            )
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            ui.getRed(
                &r,
                green: &g,
                blue: &b,
                alpha: &a
            )
            return String(
                format: "%02X%02X%02X",
                Int(
                    r * 255
                ),
                Int(
                    g * 255
                ),
                Int(
                    b * 255
                )
            )
        #else
            return "1C7ED6"
        #endif
    }
}

// MARK: - (Optional) Widget (sample UI only; wire via App Group key "widget.primaryHabit")
#if canImport(WidgetKit)
    struct HabitEntry: TimelineEntry {
        let date: Date
        let title: String
        let progress: Double
        let icon: String
    }
    struct HabitProvider: TimelineProvider {
        func placeholder(
            in: Context
        ) -> HabitEntry {
            .init(
                date: .now,
                title: "Habit",
                progress: 0.5,
                icon: "checkmark.circle"
            )
        }
        func getSnapshot(
            in context: Context,
            completion: @escaping (
                HabitEntry
            ) -> Void
        ) {
            completion(
                placeholder(
                    in: context
                )
            )
        }
        func getTimeline(
            in context: Context,
            completion: @escaping (
                Timeline<HabitEntry>
            ) -> Void
        ) {
            var entry = placeholder(
                in: context
            )
            if let ud = UserDefaults(
                suiteName: APP_GROUP_ID
            ),
                let dict = ud.dictionary(
                    forKey: "widget.primaryHabit"
                ),
                let title = dict["title"] as? String,
                let icon = dict["icon"] as? String,
                let target = dict["targetPerDay"] as? Int,
                let tc = dict["todayCount"] as? Int
            {
                entry = .init(
                    date: .now,
                    title: title,
                    progress: target == 0
                        ? 0
                        : min(
                            Double(
                                tc
                            )
                                / Double(
                                    target
                                ),
                            1
                        ),
                    icon: icon
                )
            }
            completion(
                Timeline(
                    entries: [entry],
                    policy: .after(
                        Date().addingTimeInterval(
                            1800
                        )
                    )
                )
            )
        }
    }
    struct HabitWidgetEntryView: View {
        var entry: HabitEntry
        var body: some View {
            VStack(
                alignment: .leading
            ) {
                HStack {
                    Image(
                        systemName: entry.icon
                    )
                    Text(
                        entry.title
                    ).font(
                        .headline
                    )
                }
                ProgressView(
                    value: entry.progress
                )
            }.padding()
        }
    }
    @available(
        iOSApplicationExtension 17.0,
        *
    )
    struct HabitWidget: Widget {
        var body: some WidgetConfiguration {
            StaticConfiguration(
                kind: "HabitWidget",
                provider: HabitProvider()
            ) {
                HabitWidgetEntryView(
                    entry: $0
                )
            }.configurationDisplayName(
                "Habit Progress"
            ).description(
                "Shows today's progress."
            )
        }
    }
#endif

#Preview {
    RootView()
}
