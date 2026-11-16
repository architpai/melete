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

/// Pure stats over session snapshots. OWNER: sol. Bodies below are stubs; implement + test.
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

    public var todayPomodoros: Int { 0 }
    public var focusSecondsToday: TimeInterval { 0 }
    public var streakDays: Int { 0 }
    public var last7DaysPomodoros: Int { 0 }
    public func perDay(_ range: StatsRange) -> [DayCount] { [] }
    public func perTask(_ range: StatsRange) -> [TaskStat] { [] }
    /// Today's sessions, newest first, all phases.
    public var todaySessions: [SessionSnapshot] { [] }
}
