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
