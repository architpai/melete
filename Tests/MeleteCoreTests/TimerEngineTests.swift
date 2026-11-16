import Foundation
import Testing
@testable import MeleteCore

@MainActor
struct TimerEngineTests {
    let time = ManualTimeSource()
    let defaults: UserDefaults = {
        let d = UserDefaults(suiteName: "melete.tests.\(UUID().uuidString)")!
        return d
    }()

    func make() -> (TimerEngine, Box) {
        let e = TimerEngine(durations: TimerDurations(focus: 100, shortBreak: 10, longBreak: 30, cycleLength: 2),
                            timeSource: time, defaults: defaults)
        let box = Box()
        e.onSessionEnded = { box.summaries.append($0) }
        return (e, box)
    }

    final class Box { var summaries: [SessionSummary] = [] }

    @Test func focusCompletesAndCounts() {
        let (e, box) = make()
        e.startFocus()
        time.advance(by: 100); e.reconcile()
        #expect(e.state == .awaitingChoice(ended: .focus))
        #expect(e.cyclePosition == 1)
        #expect(box.summaries.last?.counted == true)
    }

    @Test func skipFocusDoesNotCount() {
        let (e, box) = make()
        e.startFocus(); time.advance(by: 30); e.skip()
        #expect(e.state == .idle)
        #expect(e.cyclePosition == 0)
        #expect(box.summaries.last?.counted == false)
        #expect(box.summaries.last?.end == .skipped)
    }

    @Test func extendUpdatesSameSession() {
        let (e, box) = make()
        e.startFocus(); time.advance(by: 100); e.reconcile()
        let id = box.summaries.last!.id
        e.extendFiveMinutes(); time.advance(by: 300); e.reconcile()
        #expect(box.summaries.last?.id == id)
        #expect(box.summaries.last?.isUpdate == true)
        #expect(box.summaries.last?.actualDuration == 400)
        #expect(e.cyclePosition == 1)
    }

    @Test func longBreakAfterCycleAndReset() {
        let (e, _) = make()
        e.startFocus(); time.advance(by: 100); e.reconcile(); e.startBreak()
        #expect(e.phase == .shortBreak)
        time.advance(by: 10); e.reconcile(); e.startFocus()
        time.advance(by: 100); e.reconcile()
        #expect(e.nextBreak == .longBreak)
        e.startBreak(); time.advance(by: 30); e.reconcile()
        #expect(e.cyclePosition == 0)
    }

    @Test func pauseKeepsRemaining() {
        let (e, _) = make()
        e.startFocus(); time.advance(by: 40); e.pause(); time.advance(by: 500)
        #expect(e.remaining(at: time.now) == 60)
        e.resume(); time.advance(by: 60); e.reconcile()
        #expect(e.state == .awaitingChoice(ended: .focus))
    }
}
