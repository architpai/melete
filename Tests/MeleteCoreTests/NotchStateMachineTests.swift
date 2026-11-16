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

    @Test func pointerDoesNotCancelAutoCloseDeadline() {
        var m = NotchMachine(status: .running(.focus))
        m.handle(.sessionReachedZero(.shortBreak))
        let fxIn = m.handle(.pointer(inside: true))
        #expect(!fxIn.contains(.cancel(.autoClose)))
        #expect(m.expansion == .choicesAuto)
        let fxOut = m.handle(.pointer(inside: false))
        #expect(!fxOut.contains(.cancel(.autoClose)))
        #expect(!fxOut.contains(.schedule(.exit, 0.3))) // leaving does not shorten the deadline
        m.handle(.timerFired(.exit))
        #expect(m.presentation == .choices(ended: .shortBreak))
        m.handle(.timerFired(.autoClose))
        #expect(m.presentation == .collapsed) // 4b
        #expect(m.status == .awaiting(.shortBreak))
    }

    @Test func pointerInsideAtDeadlineClosesWhenPointerLeaves() {
        var m = NotchMachine(status: .running(.focus))
        m.handle(.sessionReachedZero(.focus))
        m.handle(.pointer(inside: true))
        m.handle(.timerFired(.autoClose))
        #expect(m.presentation == .choices(ended: .focus)) // still open under the pointer
        #expect(m.expansion == .hover)
        let fx = m.handle(.pointer(inside: false))
        #expect(fx.contains(.schedule(.exit, 0.3)))
        m.handle(.timerFired(.exit))
        #expect(m.presentation == .collapsed) // 4b
    }

    @Test func sessionEndFromPeekOpensAutoChoices() {
        var m = NotchMachine(status: .running(.focus))
        m.handle(.pointer(inside: true))
        #expect(m.presentation == .peek)
        let fx = m.handle(.sessionReachedZero(.focus))
        #expect(fx.contains(.schedule(.autoClose, 30)))
        #expect(m.expansion == .choicesAuto)
        #expect(m.presentation == .choices(ended: .focus))
        m.handle(.timerFired(.autoClose)) // pointer still inside
        m.handle(.pointer(inside: false))
        m.handle(.timerFired(.exit))
        #expect(m.presentation == .collapsed)
    }

    @Test func reopenedDoneChoicesHaveNoDeadline() {
        var m = NotchMachine(status: .running(.focus))
        m.handle(.sessionReachedZero(.focus))
        m.handle(.timerFired(.autoClose))
        let fx = m.handle(.pointer(inside: true))
        #expect(!fx.contains { if case .schedule(.autoClose, _) = $0 { true } else { false } })
        #expect(m.expansion == .hover)
        #expect(m.presentation == .choices(ended: .focus))
        m.handle(.timerFired(.autoClose)) // a late timer does nothing
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

    @Test func sessionEndFromFullShowsChoicesAndDropsKey() {
        var m = NotchMachine(status: .running(.focus))
        m.handle(.openFull(firstRun: false))
        let fx = m.handle(.sessionReachedZero(.focus))
        #expect(fx.contains(.resignKey))
        #expect(fx.contains(.schedule(.autoClose, 30)))
        #expect(m.presentation == .choices(ended: .focus))
        #expect(!m.wantsKey)
        m.handle(.timerFired(.autoClose))
        #expect(m.presentation == .collapsed) // 4b
    }

    @Test func oneEscapeClosesFullPanel() {
        var m = NotchMachine(status: .running(.focus))
        m.handle(.openFull(firstRun: false))
        m.handle(.pointer(inside: true))
        let fx = m.handle(.escape)
        #expect(fx.contains(.resignKey)) // the controller commits text edits on resign
        #expect(m.presentation == .collapsed)
        #expect(m.expansion == .none)
        #expect(!m.wantsKey)
    }

    @Test func followsPointerScreenAgainWhenExpansionCloses() {
        var m = NotchMachine(status: .running(.focus))
        #expect(m.followsPointerScreen)
        m.handle(.pointer(inside: true))
        #expect(!m.followsPointerScreen) // pinned while the peek is open
        m.handle(.pointer(inside: false))
        m.handle(.timerFired(.exit))
        #expect(m.followsPointerScreen)
        m.handle(.openFull(firstRun: false))
        #expect(!m.followsPointerScreen)
        m.handle(.clickOutside)
        #expect(m.followsPointerScreen)
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
        var m = NotchMachine(status: .running(.focus), hasNotch: false, fullscreen: true)
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
        var m = NotchMachine(hasNotch: false, fullscreen: true)
        m.handle(.pointer(inside: true))
        m.handle(.timerFired(.dwell))
        #expect(m.presentation == .idleHover)
        m.handle(.pointer(inside: false))
        m.handle(.timerFired(.exit))
        #expect(m.presentation == .hidden)
    }

    // Rule C (user test F2): in fullscreen the auto choices have no deadline; they stay until the user chooses.
    @Test func fullscreenSessionEndChoicesStayUntilChosen() {
        var m = NotchMachine(status: .running(.focus), hasNotch: false, fullscreen: true)
        let fx = m.handle(.sessionReachedZero(.focus))
        #expect(!fx.contains { if case .schedule(.autoClose, _) = $0 { true } else { false } })
        #expect(fx.contains(.cancel(.autoClose)))
        #expect(m.presentation == .choices(ended: .focus))
        #expect(!m.wantsKey)
        m.handle(.pointer(inside: true))
        let fxOut = m.handle(.pointer(inside: false))
        #expect(!fxOut.contains(.schedule(.exit, 0.3)))
        m.handle(.timerFired(.exit))
        m.handle(.clickOutside) // not key, not pinned: an outside click does not close it
        m.handle(.timerFired(.autoClose)) // a late timer does nothing in fullscreen
        #expect(m.presentation == .choices(ended: .focus))
        #expect(m.expansion == .choicesAuto)
        #expect(!m.followsPointerScreen) // stays on the fullscreen screen until the choice
        m.handle(.actionDone)
        m.handle(.engine(.running(.shortBreak)))
        #expect(m.presentation == .hidden)
        #expect(m.followsPointerScreen) // the controller re-picks: back to the home screen (rule A)
    }

    @Test func fullscreenAutoChoicesStillCloseOnEscapeOrPinnedClickOutside() {
        var m = NotchMachine(status: .running(.focus), hasNotch: false, fullscreen: true)
        m.handle(.sessionReachedZero(.focus))
        m.handle(.escape)
        #expect(m.presentation == .hidden)
        #expect(m.status == .awaiting(.focus))
        // 4b in fullscreen: dwell reveals the choices, a click pins them, click outside closes.
        m.handle(.pointer(inside: true))
        m.handle(.timerFired(.dwell))
        m.handle(.clickShape)
        #expect(m.expansion == .choicesPinned)
        m.handle(.clickOutside)
        #expect(m.presentation == .hidden)
    }

    @Test func nonFullscreenSessionEndKeepsThirtySecondDeadline() {
        var m = NotchMachine(status: .running(.focus), fullscreen: false)
        let fx = m.handle(.sessionReachedZero(.focus))
        #expect(fx.contains(.schedule(.autoClose, 30)))
        m.handle(.timerFired(.autoClose))
        #expect(m.presentation == .collapsed) // 4b
    }

    @Test func screenBecomingFullscreenCancelsAutoChoicesDeadline() {
        var m = NotchMachine(status: .running(.focus))
        m.handle(.sessionReachedZero(.focus))
        let fx = m.handle(.screen(hasNotch: false, fullscreen: true))
        #expect(fx.contains(.cancel(.autoClose)))
        #expect(m.presentation == .choices(ended: .focus)) // still shown over the fullscreen app
        m.handle(.timerFired(.autoClose)) // a timer that was already on its way
        #expect(m.presentation == .choices(ended: .focus))
    }

    @Test func leavingFullscreenDoesNotStartADeadline() {
        var m = NotchMachine(status: .running(.focus), hasNotch: false, fullscreen: true)
        m.handle(.sessionReachedZero(.focus))
        let fx = m.handle(.screen(hasNotch: false, fullscreen: false)) // the fullscreen app exits
        #expect(!fx.contains { if case .schedule(.autoClose, _) = $0 { true } else { false } })
        #expect(m.expansion == .choicesAuto)
        #expect(m.presentation == .choices(ended: .focus))
        m.handle(.screen(hasNotch: false, fullscreen: true)) // swipes back: still shown
        #expect(m.presentation == .choices(ended: .focus))
    }

    // Rule B: a fullscreen reveal keeps the panel on that screen until the exit delay ends.
    @Test func fullscreenRevealPinsScreenUntilExit() {
        var m = NotchMachine(status: .running(.focus), hasNotch: false, fullscreen: true)
        #expect(m.followsPointerScreen)
        m.handle(.pointer(inside: true))
        #expect(m.followsPointerScreen) // dwell pending: leaving the hot zone may send it home at once
        m.handle(.timerFired(.dwell))
        #expect(m.revealed)
        #expect(!m.followsPointerScreen)
        m.handle(.pointer(inside: false))
        #expect(!m.followsPointerScreen) // during the exit delay
        m.handle(.timerFired(.exit))
        #expect(!m.revealed)
        #expect(m.presentation == .hidden)
        #expect(m.followsPointerScreen) // the controller re-picks: back to the home screen
    }

    @Test func fullscreenPendingDwellDoesNotChangeAutoChoices() {
        var m = NotchMachine(status: .running(.focus), hasNotch: false, fullscreen: true)
        m.handle(.pointer(inside: true)) // hot zone: dwell scheduled
        let fx = m.handle(.sessionReachedZero(.focus))
        #expect(fx.contains(.cancel(.dwell)))
        m.handle(.timerFired(.dwell)) // a late dwell timer
        #expect(m.expansion == .choicesAuto)
        #expect(!m.revealed)
        m.handle(.pointer(inside: false))
        #expect(m.presentation == .choices(ended: .focus))
    }

    @Test func fullscreenDwellOnDoneOpensChoicesWithoutKey() {
        for ended in [Phase.focus, .shortBreak] {
            // 4b reached on a normal screen, then the screen goes fullscreen.
            var m = NotchMachine(status: .running(ended))
            m.handle(.sessionReachedZero(ended))
            m.handle(.timerFired(.autoClose))
            m.handle(.screen(hasNotch: false, fullscreen: true))
            #expect(m.presentation == .hidden) // 4b, hidden in fullscreen
            let fxIn = m.handle(.pointer(inside: true))
            #expect(fxIn.contains(.schedule(.dwell, 1.0)))
            let fx = m.handle(.timerFired(.dwell))
            #expect(m.presentation == .choices(ended: ended))
            #expect(!fx.contains(.makeKey))
            #expect(!m.wantsKey)
            m.handle(.pointer(inside: false))
            m.handle(.timerFired(.exit))
            #expect(m.presentation == .hidden)
        }
    }

    @Test func enteringFullscreenClosesFullPanelFromDesktop() {
        var m = NotchMachine(status: .running(.focus))
        m.handle(.openFull(firstRun: false))
        let fx = m.handle(.screen(hasNotch: false, fullscreen: true))
        #expect(fx.contains(.resignKey))
        #expect(!m.wantsKey)
        #expect(m.presentation == .hidden)
        m.handle(.pointer(inside: false))
        m.handle(.timerFired(.exit))
        #expect(m.presentation == .hidden)
    }

    @Test func fullPanelOpenedInFullscreenStays() {
        var m = NotchMachine(status: .running(.focus), hasNotch: false, fullscreen: true)
        m.handle(.pointer(inside: true))
        m.handle(.timerFired(.dwell))
        #expect(m.presentation == .collapsed)
        m.handle(.clickShape)
        #expect(m.presentation == .full(firstRun: false))
        // A later fullscreen check (same state) does not close it.
        let fx = m.handle(.screen(hasNotch: false, fullscreen: true))
        #expect(!fx.contains(.resignKey))
        #expect(m.presentation == .full(firstRun: false))
        m.handle(.pointer(inside: false))
        m.handle(.timerFired(.exit))
        #expect(m.presentation == .full(firstRun: false))
        m.handle(.escape)
        #expect(m.presentation == .hidden)
    }

    @Test func fullscreenShowsSessionEndThenHidesAfterChoice() {
        var m = NotchMachine(status: .running(.focus), hasNotch: false, fullscreen: true)
        m.handle(.sessionReachedZero(.focus))
        #expect(m.presentation == .choices(ended: .focus))
        m.handle(.timerFired(.autoClose))
        #expect(m.presentation == .choices(ended: .focus)) // no deadline in fullscreen
        // The choice (via the engine) hides it again.
        m.handle(.engine(.running(.shortBreak)))
        #expect(m.presentation == .hidden)
    }

    // User test (16 Nov): on a notched screen a fullscreen app leaves a black strip around the notch,
    // so the notch stays visible there. The fullscreen flag still removes the 30 s session-end deadline.
    @Test func notchedFullscreenScreenStaysVisible() {
        var m = NotchMachine(status: .running(.focus), hasNotch: true, fullscreen: true)
        #expect(m.presentation == .collapsed)
        #expect(!m.usesHotZone)
        let fx = m.handle(.pointer(inside: true))
        #expect(!fx.contains(.schedule(.dwell, 1.0)))
        #expect(m.presentation == .peek)
        m.handle(.pointer(inside: false))
        m.handle(.timerFired(.exit))
        #expect(m.presentation == .collapsed)
        let end = m.handle(.sessionReachedZero(.focus))
        #expect(m.presentation == .choices(ended: .focus))
        #expect(!end.contains(.schedule(.autoClose, 30)))
        m.handle(.timerFired(.autoClose))
        #expect(m.presentation == .choices(ended: .focus))
        m.handle(.engine(.idle))
        #expect(m.presentation == .hidden) // idle = the normal notch
        m.handle(.pointer(inside: true))
        #expect(m.presentation == .idleHover) // Start at once, no 1 s dwell
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
