import Foundation
import Testing
@testable import MeleteCore

struct StatsCalculatorTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c
    }
    func date(_ day: Int, month: Int = 11, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    func session(_ date: Date, phase: Phase = .focus, counted: Bool = true, seconds: Double = 100,
                 task: UUID? = nil, title: String? = nil) -> SessionSnapshot {
        SessionSnapshot(phase: phase, startedAt: date, endedAt: date.addingTimeInterval(seconds),
                        actualDuration: seconds, end: counted ? .completed : .skipped,
                        counted: counted, taskID: task, taskTitle: title)
    }
    @Test func totalsAndHistory() {
        let c = StatsCalculator(sessions: [session(date(16)), session(date(16, hour: 13), counted: false, seconds: 20),
            session(date(16, hour: 14), phase: .shortBreak), session(date(15)), session(date(9))],
            now: date(16), calendar: calendar)
        #expect(c.todayPomodoros == 1); #expect(c.focusSecondsToday == 120)
        #expect(c.last7DaysPomodoros == 2); #expect(c.streakDays == 2)
        #expect(c.todaySessions.map(\.phase) == [.shortBreak, .focus, .focus])
        #expect(c.perDay(.week).count == 7); #expect(c.perDay(.month).count == 30)
        #expect(c.perDay(.year).count == 12)
    }
    @Test func dayBoundariesAndStreakFallback() {
        let midnight = date(16, hour: 0)
        let c = StatsCalculator(sessions: [session(midnight.addingTimeInterval(-1)), session(date(14)),
            session(date(17, hour: 0))], now: date(16), calendar: calendar)
        #expect(c.todaySessions.isEmpty); #expect(c.streakDays == 2)
        #expect(c.perDay(.week).last?.pomodoros == 0)
        #expect(StatsCalculator(sessions: [session(date(14))], now: date(16), calendar: calendar).streakDays == 0)
    }
    @Test func monthBucketsAndTaskSnapshots() {
        let id = UUID()
        let c = StatsCalculator(sessions: [session(date(1, month: 12)), session(date(1, month: 11), task: id, title: "Old"),
            session(date(2, month: 11), task: id, title: "New"), session(date(16), counted: false, seconds: 50),
            session(date(16), phase: .longBreak)], now: date(16), calendar: calendar)
        #expect(c.perDay(.year).last?.pomodoros == 2)
        #expect(c.perTask(.month).first?.title == "New")
        #expect(c.perTask(.month).last?.title == "Intentions only")
        #expect(c.perTask(.month).last?.focusSeconds == 50)
        #expect(c.perTask(.week).count == 1)
        #expect(StatsCalculator(sessions: [], now: date(16), calendar: calendar).streakDays == 0)
    }
}

extension StatsCalculatorTests {
    @Test func rollingWindowsIncludeStartAndExcludeEnd() {
        let today = date(16, hour: 0)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today)!
        let monthStart = calendar.date(byAdding: .day, value: -29, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let c = StatsCalculator(sessions: [session(weekStart), session(weekStart.addingTimeInterval(-1)),
            session(monthStart), session(monthStart.addingTimeInterval(-1)), session(today), session(tomorrow)],
            now: date(16), calendar: calendar)
        #expect(c.last7DaysPomodoros == 2)
        #expect(c.perDay(.month).reduce(0) { $0 + $1.pomodoros } == 4)
        #expect(c.perTask(.week).first?.pomodoros == 2)
        #expect(c.perTask(.month).first?.pomodoros == 4)
        #expect(c.todaySessions.count == 1)
    }

    @Test func daylightSavingDaysUseCalendarBoundaries() {
        let start = date(1, hour: 0)
        let end = date(2, hour: 0)
        #expect(end.timeIntervalSince(start) == 25 * 3600)
        let c = StatsCalculator(sessions: [session(start), session(end.addingTimeInterval(-1)), session(end)],
            now: date(2), calendar: calendar)
        let bars = c.perDay(.week)
        #expect(bars[5].pomodoros == 2)
        #expect(bars[6].pomodoros == 1)
        #expect(c.streakDays == 2)
    }

    @Test func yearIncludesTwelveCalendarMonthsAcrossYearBoundary() {
        let now = calendar.date(from: DateComponents(year: 2027, month: 1, day: 15))!
        let first = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let c = StatsCalculator(sessions: [session(first.addingTimeInterval(-1)), session(first), session(now)],
            now: now, calendar: calendar)
        #expect(c.perDay(.year).first?.date == first)
        #expect(c.perDay(.year).first?.pomodoros == 1)
        #expect(c.perDay(.year).last?.pomodoros == 1)
        #expect(c.perTask(.year).first?.pomodoros == 2)
    }

    @Test func overnightSessionsBelongToTheirStartDay() {
        let midnight = date(16, hour: 0)
        let c = StatsCalculator(sessions: [session(midnight.addingTimeInterval(-60), seconds: 300),
            session(midnight, counted: false, seconds: 25)], now: date(16), calendar: calendar)
        #expect(c.todayPomodoros == 0)
        #expect(c.focusSecondsToday == 25)
        #expect(c.perDay(.week)[5].focusSeconds == 300)
        #expect(c.streakDays == 1)
    }

    @Test func taskGroupsKeepDistinctIDsAndIncludeUncountedFocusTime() {
        let a = UUID(), b = UUID()
        let c = StatsCalculator(sessions: [session(date(16), task: a, title: "Same title"),
            session(date(16), task: b, title: "Same title"), session(date(16), counted: false, seconds: 20),
            session(date(16), phase: .shortBreak, counted: false, seconds: 50)],
            now: date(16), calendar: calendar)
        let groups = c.perTask(.week)
        #expect(groups.count == 3)
        #expect(groups.filter { $0.title == "Same title" }.count == 2)
        #expect(groups.first { $0.taskID == nil }?.pomodoros == 0)
        #expect(groups.first { $0.taskID == nil }?.focusSeconds == 20)
        #expect(c.todaySessions.count == 4)
    }
}
