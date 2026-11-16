import Foundation
import Testing
@testable import MeleteCore

struct NotchStateMachineTests {
    @Test func idleNotchShowsNothingAndHoverShowsStart() {
        var m = NotchMachine()
        #expect(m.presentation == .hidden)
        #expect(m.usesHotZone)
        m.handle(.pointer(inside: true))
        #expect(m.presentation == .idleHover)
        let fx = m.handle(.pointer(inside: false))
        #expect(fx.contains(.schedule(.exit, 0.3)))
        #expect(m.presentation == .idleHover) // waits for the exit delay
        m.handle(.timerFired(.exit))
        #expect(m.presentation == .hidden)
    }

    @Test func reenterBeforeExitDelayKeepsItOpen() {
        var m = NotchMachine()
        m.handle(.pointer(inside: true))
        m.handle(.pointer(inside: false))
        let fx = m.handle(.pointer(inside: true))
        #expect(fx.contains(.cancel(.exit)))
        m.handle(.timerFired(.exit)) // late timer: pointer is inside, ignored
        #expect(m.presentation == .idleHover)
    }

    @Test func noNotchIdleNeedsDwell() {
        var m = NotchMachine(hasNotch: false)
        let fx = m.handle(.pointer(inside: true))
        #expect(fx.contains(.schedule(.dwell, 0.4)))
        #expect(m.presentation == .hidden)
        m.handle(.timerFired(.dwell))
        #expect(m.presentation == .idleHover)
    }

    @Test func noNotchDwellCancelledWhenPointerLeaves() {
        var m = NotchMachine(hasNotch: false)
        m.handle(.pointer(inside: true))
        let fx = m.handle(.pointer(inside: false))
        #expect(fx.contains(.cancel(.dwell)))
        m.handle(.timerFired(.dwell))
        #expect(m.presentation == .hidden)
    }

    @Test func startFromHoverCollapsesAndSuppressesPeek() {
        var m = NotchMachine()
        m.handle(.pointer(inside: true))
        m.handle(.actionDone)
        m.handle(.engine(.running(.focus)))
        #expect(m.presentation == .collapsed)
        #expect(m.suppressHover)
        m.handle(.pointer(inside: false))
        m.handle(.pointer(inside: true))
        #expect(m.presentation == .peek)
    }

    @Test func runningHoverShowsPeekAndClickOpensFull() {
        var m = NotchMachine(status: .running(.focus))
        #expect(m.presentation == .collapsed)
        m.handle(.pointer(inside: true))
        #expect(m.presentation == .peek)
        let fx = m.handle(.clickShape)
        #expect(fx.contains(.makeKey))
        #expect(m.presentation == .full(firstRun: false))
        #expect(m.wantsKey)
    }

    @Test func fullClosesOnClickOutsideOrEscapeNotOnExit() {
        var m = NotchMachine(status: .running(.focus))
        m.handle(.openFull(firstRun: false))
        m.handle(.pointer(inside: true))
        let fx0 = m.handle(.pointer(inside: false))
        #expect(!fx0.contains(.schedule(.exit, 0.3)))
        m.handle(.timerFired(.exit))
        #expect(m.presentation == .full(firstRun: false))
        let fx = m.handle(.clickOutside)
        #expect(fx.contains(.resignKey))
        #expect(m.presentation == .collapsed)
        m.handle(.openFull(firstRun: false))
        m.handle(.escape)
        #expect(m.presentation == .collapsed)
    }

    @Test func firstRunMarksDoneAndShowsHint() {
        var m = NotchMachine()
        let fx = m.handle(.openFull(firstRun: true))
        #expect(fx.contains(.markFirstRunDone))
        #expect(m.presentation == .full(firstRun: true))
        m.handle(.escape)
        m.handle(.openFull(firstRun: false))
        #expect(m.presentation == .full(firstRun: false))
    }

    @Test func sessionEndOpensChoicesAndAutoClosesTo4b() {
        var m = NotchMachine(status: .running(.focus))
        let fx = m.handle(.sessionReachedZero(.focus))
        #expect(fx.contains(.schedule(.autoClose, 30)))
        #expect(m.presentation == .choices(ended: .focus))
        m.handle(.pointer(inside: false)) // no-op
        #expect(m.presentation == .choices(ended: .focus)) // not closed by pointer outside
        m.handle(.clickOutside)
        #expect(m.presentation == .choices(ended: .focus)) // auto panel ignores outside clicks
        m.handle(.timerFired(.autoClose))
        #expect(m.presentation == .collapsed) // 4b: collapsed + awaiting = "Done"
        #expect(m.status == .awaiting(.focus))
    }

    @Test func doneHoverReopensChoicesAndClosesOnExit() {
        var m = NotchMachine(status: .awaiting(.shortBreak))
        m.handle(.pointer(inside: true))
        #expect(m.presentation == .choices(ended: .shortBreak))
        m.handle(.pointer(inside: false))
        m.handle(.timerFired(.exit))
        #expect(m.presentation == .collapsed)
    }

    @Test func doneClickPinsChoices() {
        var m = NotchMachine(status: .awaiting(.focus))
        m.handle(.clickShape)
        #expect(m.expansion == .choicesPinned)
        m.handle(.pointer(inside: true))
        m.handle(.pointer(inside: false))
        m.handle(.timerFired(.exit))
        #expect(m.presentation == .choices(ended: .focus))
        m.handle(.clickOutside)
        #expect(m.presentation == .collapsed)
    }

    @Test func pointerEnteringAutoChoicesCancelsAutoClose() {
        var m = NotchMachine(status: .running(.focus))
        m.handle(.sessionReachedZero(.focus))
        let fx = m.handle(.pointer(inside: true))
        #expect(fx.contains(.cancel(.autoClose)))
        #expect(m.expansion == .hover)
        m.handle(.timerFired(.autoClose))
        #expect(m.presentation == .choices(ended: .focus))
    }

    @Test func choosingCollapses() {
        var m = NotchMachine(status: .running(.focus))
        m.handle(.sessionReachedZero(.focus))
        m.handle(.engine(.running(.shortBreak)))
        #expect(m.presentation == .collapsed)
        #expect(m.expansion == .none)
    }

    @Test func choosingFromHoverChoicesCollapses() {
        var m = NotchMachine(status: .awaiting(.focus))
        m.handle(.pointer(inside: true))
        m.handle(.engine(.running(.focus)))
        #expect(m.presentation == .collapsed)
        #expect(m.suppressHover)
    }

    @Test func sessionEndKeepsFullPanelOpen() {
        var m = NotchMachine(status: .running(.focus))
        m.handle(.openFull(firstRun: false))
        let fx = m.handle(.sessionReachedZero(.focus))
        #expect(fx.isEmpty)
        #expect(m.presentation == .full(firstRun: false))
    }

    @Test func peekStaysWhenPausedOrReset() {
        var m = NotchMachine(status: .running(.focus))
        m.handle(.pointer(inside: true))
        m.handle(.engine(.paused(.focus)))
        #expect(m.presentation == .peek)
        m.handle(.engine(.idle))
        #expect(m.presentation == .idleHover)
    }

    @Test func fullscreenHidesUntilDwell() {
        var m = NotchMachine(status: .running(.focus), fullscreen: true)
        #expect(m.presentation == .hidden)
        #expect(m.usesHotZone)
        let fx = m.handle(.pointer(inside: true))
        #expect(fx.contains(.schedule(.dwell, 1.0)))
        m.handle(.timerFired(.dwell))
        #expect(m.presentation == .collapsed) // mock 4c: collapsed while hovering
        m.handle(.pointer(inside: false))
        m.handle(.timerFired(.exit))
        #expect(m.presentation == .hidden)
    }

    @Test func fullscreenIdleDwellShowsStart() {
        var m = NotchMachine(fullscreen: true)
        m.handle(.pointer(inside: true))
        m.handle(.timerFired(.dwell))
        #expect(m.presentation == .idleHover)
        m.handle(.pointer(inside: false))
        m.handle(.timerFired(.exit))
        #expect(m.presentation == .hidden)
    }

    @Test func fullscreenSessionEndStaysWhilePointerInside() {
        var m = NotchMachine(status: .running(.focus), fullscreen: true)
        m.handle(.sessionReachedZero(.focus))
        m.handle(.pointer(inside: true))
        #expect(m.presentation == .choices(ended: .focus))
        m.handle(.pointer(inside: false))
        m.handle(.timerFired(.exit))
        #expect(m.presentation == .hidden)
        #expect(m.status == .awaiting(.focus))
    }

    @Test func fullscreenShowsSessionEndThenHidesAgain() {
        var m = NotchMachine(status: .running(.focus), fullscreen: true)
        m.handle(.sessionReachedZero(.focus))
        #expect(m.presentation == .choices(ended: .focus))
        m.handle(.timerFired(.autoClose))
        #expect(m.presentation == .hidden)
        // A choice also hides it again.
        var n = NotchMachine(status: .running(.focus), fullscreen: true)
        n.handle(.sessionReachedZero(.focus))
        n.handle(.actionDone)
        n.handle(.engine(.running(.shortBreak)))
        #expect(n.presentation == .hidden)
    }

    @Test func screenChangeResetsHover() {
        var m = NotchMachine(status: .running(.focus))
        m.handle(.pointer(inside: true))
        m.handle(.screen(hasNotch: false, fullscreen: false))
        #expect(m.presentation == .collapsed)
        #expect(!m.pointerInside)
        #expect(!m.hasNotch)
    }

    @Test func statusFromEngineState() {
        #expect(NotchEngineStatus(state: .idle, phase: .focus) == .idle)
        #expect(NotchEngineStatus(state: .running(endsAt: Date(), total: 1), phase: .shortBreak) == .running(.shortBreak))
        #expect(NotchEngineStatus(state: .paused(remaining: 1, total: 2), phase: .focus) == .paused(.focus))
        #expect(NotchEngineStatus(state: .awaitingChoice(ended: .longBreak), phase: .focus) == .awaiting(.longBreak))
    }
}
