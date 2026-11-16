import Foundation

public enum StatsRange: String, CaseIterable, Sendable {
    /// Rolling last 7 days, one bar per day.
    case week
    /// Rolling last 30 days, one bar per day.
    case month
    /// Rolling last 12 months, one bar per month.
    case year
}

public struct DayCount: Identifiable, Equatable, Sendable {
    /// Start of the day (or of the month for `.year`).
    public var date: Date
    public var pomodoros: Int
    public var focusSeconds: TimeInterval
    public var id: Date { date }
    public init(date: Date, pomodoros: Int, focusSeconds: TimeInterval) {
        self.date = date; self.pomodoros = pomodoros; self.focusSeconds = focusSeconds
    }
}

public struct TaskStat: Identifiable, Equatable, Sendable {
    /// nil = "Intentions only" group (sessions with no task).
    public var taskID: UUID?
    public var title: String
    public var pomodoros: Int
    public var focusSeconds: TimeInterval
    public var id: String { taskID?.uuidString ?? "intentions" }
    public init(taskID: UUID?, title: String, pomodoros: Int, focusSeconds: TimeInterval) {
        self.taskID = taskID; self.title = title; self.pomodoros = pomodoros; self.focusSeconds = focusSeconds
    }
}

/// Pure stats over session snapshots, attributed to the calendar day they started.
/// Definitions (docs/spec.md):
/// - A pomodoro = a focus snapshot with `counted == true`.
/// - Focus time = sum of `actualDuration` of focus snapshots (counted or not).
/// - Streak = consecutive days with ≥1 pomodoro, ending today; if today has 0 so far, ending yesterday.
/// - "This week" tile = rolling last 7 days including today.
public struct StatsCalculator: Sendable {
    public var sessions: [SessionSnapshot]
    public var now: Date
    public var calendar: Calendar

    public init(sessions: [SessionSnapshot], now: Date = Date(), calendar: Calendar = .current) {
        self.sessions = sessions; self.now = now; self.calendar = calendar
    }

    private var today: Date { calendar.startOfDay(for: now) }
    private func offset(_ value: Int, _ component: Calendar.Component, from date: Date) -> Date {
        calendar.date(byAdding: component, value: value, to: date)!
    }
    private func within(_ start: Date, _ end: Date) -> [SessionSnapshot] {
        sessions.filter { $0.startedAt >= start && $0.startedAt < end }
    }
    private func count(_ items: [SessionSnapshot]) -> Int {
        items.filter { $0.phase == .focus && $0.counted }.count
    }
    private func focus(_ items: [SessionSnapshot]) -> TimeInterval {
        items.filter { $0.phase == .focus }.reduce(0) { $0 + $1.actualDuration }
    }
    public var todayPomodoros: Int { count(todaySessions) }
    public var focusSecondsToday: TimeInterval { focus(todaySessions) }
    public var streakDays: Int {
        let days = Set(sessions.filter { $0.phase == .focus && $0.counted }
            .map { calendar.startOfDay(for: $0.startedAt) })
        var day = days.contains(today) ? today : offset(-1, .day, from: today)
        var streak = 0
        while days.contains(day) { streak += 1; day = offset(-1, .day, from: day) }
        return streak
    }
    public var last7DaysPomodoros: Int { perDay(.week).reduce(0) { $0 + $1.pomodoros } }
    private func buckets(_ range: StatsRange) -> [Date] {
        let monthly = range == .year
        let end = monthly ? calendar.dateInterval(of: .month, for: now)!.start : today
        let length = range == .week ? 7 : range == .month ? 30 : 12
        return (0..<length).map { offset($0 - length + 1, monthly ? .month : .day, from: end) }
    }
    public func perDay(_ range: StatsRange) -> [DayCount] {
        buckets(range).map { date in
            let items = within(date, offset(1, range == .year ? .month : .day, from: date))
            return DayCount(date: date, pomodoros: count(items), focusSeconds: focus(items))
        }
    }
    public func perTask(_ range: StatsRange) -> [TaskStat] {
        let items = within(buckets(range)[0], offset(1, .day, from: today)).filter { $0.phase == .focus }
        return Dictionary(grouping: items, by: \.taskID).map { id, group in
            let title = id == nil ? "Intentions only" :
                (group.sorted { $0.startedAt > $1.startedAt }.compactMap(\.taskTitle).first ?? "Deleted task")
            return TaskStat(taskID: id, title: title, pomodoros: count(group), focusSeconds: focus(group))
        }.sorted {
            if $0.pomodoros != $1.pomodoros { return $0.pomodoros > $1.pomodoros }
            if $0.focusSeconds != $1.focusSeconds { return $0.focusSeconds > $1.focusSeconds }
            return $0.id < $1.id
        }
    }
    /// Sessions are attributed to their start day, matching MeleteStore.sessions(from:to:).
    public var todaySessions: [SessionSnapshot] {
        within(today, offset(1, .day, from: today)).sorted { $0.startedAt > $1.startedAt }
    }
}
