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
    @Test func skipBreaksAndManualSelection() {
        for phase in [Phase.shortBreak, .longBreak] {
            let (e, box) = make()
            e.select(phase); #expect(e.phase == phase)
            e.start(phase); e.select(.focus); #expect(e.phase == phase)
            e.skip(); #expect(e.phase == .focus)
            #expect(box.summaries.last?.end == .skipped)
            #expect(box.summaries.last?.counted == false)
            e.stop()
        }
    }

    @Test func resetAndStop() {
        let (e, box) = make()
        e.start(.shortBreak); time.advance(by: 3); e.reset()
        #expect(e.state == .idle); #expect(e.phase == .shortBreak)
        #expect(box.summaries.last?.actualDuration == 3)
        #expect(box.summaries.last?.end == .reset)
        e.startFocus(); time.advance(by: 100); e.reconcile(); e.startBreak()
        time.advance(by: 10); e.reconcile(); e.stop()
        #expect(e.cyclePosition == 1); #expect(e.phase == .focus)
        #expect(e.state == .idle)
    }

    @Test func extensionsTwiceThenStop() {
        let (e, box) = make()
        e.startFocus(); time.advance(by: 100); e.reconcile()
        let id = box.summaries[0].id
        e.extendFiveMinutes(); time.advance(by: 300); e.reconcile()
        e.extendFiveMinutes(); time.advance(by: 50); e.stop()
        #expect(box.summaries.count == 3)
        #expect(box.summaries.allSatisfy { $0.id == id && $0.counted })
        #expect(box.summaries.last?.actualDuration == 450)
        #expect(e.cyclePosition == 1)
    }

    @Test func skipBreakWrapAndDurationChange() {
        let (e, _) = make()
        e.startFocus(); time.advance(by: 100); e.reconcile(); e.skipBreak()
        time.advance(by: 100); e.reconcile(); e.skipBreak()
        #expect(e.cyclePosition == 0)
        var d = e.durations; d.focus = 200; d.cycleLength = 6; e.durations = d
        #expect(e.remaining(at: time.now) == 100)
        for _ in 0..<4 { time.advance(by: 200); e.reconcile(); e.skipBreak() }
        d.cycleLength = 2; e.durations = d
        #expect(e.cyclePosition == 2)
        e.stop(); e.startFocus(); #expect(e.remaining(at: time.now) == 200)
    }

    @Test func persistenceAndNewDay() {
        let (e, _) = make()
        e.startFocus(); time.advance(by: 100); e.reconcile(); e.stop()
        let (restored, _) = make()
        #expect(restored.cyclePosition == 1); #expect(restored.state == .idle)
        time.advance(by: 86400)
        #expect(restored.cyclePosition == 1)
        restored.startFocus(); #expect(restored.cyclePosition == 0)
        restored.stop()
    }

    @Test func longSleepAndProgress() {
        let (e, box) = make()
        #expect(e.progress(at: time.now) == 0)
        e.startFocus(); let end = time.now.addingTimeInterval(100)
        time.advance(by: 25)
        #expect(e.remaining(at: time.now) == 75); #expect(e.progress(at: time.now) == 0.25)
        e.togglePause(); time.advance(by: 50)
        #expect(e.progress(at: time.now) == 0.25)
        e.togglePause(); time.advance(by: 10000); e.reconcile()
        #expect(box.summaries.last?.endedAt == end.addingTimeInterval(50))
        #expect(box.summaries.last?.actualDuration == 100)
        #expect(e.remaining(at: time.now) == 0); #expect(e.progress(at: time.now) == 1)
    }

}
