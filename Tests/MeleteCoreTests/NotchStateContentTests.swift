import CoreGraphics
import Foundation
import Testing
@testable import MeleteCore

struct NotchStateContentTests {
    @Test func runningFocus() {
        let c = CollapsedContent.make(status: .running(.focus), cyclePosition: 2, cycleLength: 4, remaining: 1122, progress: 0.25)!
        #expect(c.dots == 4 && c.filledDots == 2)
        #expect(c.icon == .none && c.label == .time(1122) && !c.dimText && !c.blink && c.bar == .solid && c.ticks)
    }

    @Test func breakHasCupDimTextDashedBar() {
        let c = CollapsedContent.make(status: .running(.shortBreak), cyclePosition: 2, cycleLength: 4, remaining: 192, progress: 0.36)!
        #expect(c.icon == .cup && c.dimText && c.bar == .dashed && !c.blink)
    }

    @Test func pausedBlinksWithDimBar() {
        let c = CollapsedContent.make(status: .paused(.focus), cyclePosition: 1, cycleLength: 4, remaining: 1122, progress: 0.25)!
        #expect(c.icon == .pause && c.blink && c.bar == .dim && !c.ticks)
        let b = CollapsedContent.make(status: .paused(.longBreak), cyclePosition: 0, cycleLength: 4, remaining: 60, progress: 0.5)!
        #expect(b.bar == .dashedDim && b.dimText)
    }

    @Test func doneBlinksFullBar() {
        let c = CollapsedContent.make(status: .awaiting(.focus), cyclePosition: 3, cycleLength: 4, remaining: 0, progress: 1)!
        #expect(c.label == .done && c.blink && c.progress == 1 && c.bar == .solid)
    }

    @Test func idleShowsNothing() {
        #expect(CollapsedContent.make(status: .idle, cyclePosition: 0, cycleLength: 4, remaining: 0, progress: 0) == nil)
    }

    @Test func dotsFollowCycleLengthAndClamp() {
        for n in 2...6 {
            #expect(CollapsedContent.make(status: .running(.focus), cyclePosition: 9, cycleLength: n, remaining: 1, progress: 0)?.dots == n)
            #expect(CollapsedContent.make(status: .running(.focus), cyclePosition: 9, cycleLength: n, remaining: 1, progress: 0)?.filledDots == n)
        }
    }

    @Test func formats() {
        #expect(NotchFormat.clock(25 * 60) == "25:00")
        #expect(NotchFormat.clock(65.2) == "1:06")
        #expect(NotchFormat.clock(3900) == "1:05:00")
        #expect(NotchFormat.cycleNote(cyclePosition: 3, cycleLength: 4) == "1 more to long break")
        #expect(NotchFormat.cycleNote(cyclePosition: 4, cycleLength: 4) == "Long break next")
    }

    @Test func sessionEndCopy() {
        let f = SessionEndCopy.focusEnded(who: "Write README", cyclePosition: 3, cycleLength: 4, nextBreak: .shortBreak, breakDuration: 300)
        #expect(f.title == "Focus done" && f.primary == "Break 5:00" && f.secondary == ["+5 min", "Skip"])
        #expect(f.cycleNote == "1 more to long break")
        let l = SessionEndCopy.focusEnded(who: nil, cyclePosition: 4, cycleLength: 4, nextBreak: .longBreak, breakDuration: 900)
        #expect(l.primary == "Long break 15:00")
        let b = SessionEndCopy.breakEnded(who: "Write README", focusDuration: 1500)
        #expect(b.title == "Break over" && b.detail == "Next: Write README" && b.primary == "Focus 25:00" && b.secondary == ["Stop"])
        #expect(SessionEndCopy.breakEnded(who: nil, focusDuration: 1500).detail == "Next: focus")
    }

    @Test func peekSubtitle() {
        #expect(PeekCopy.subtitle(phase: .focus, taskTitle: "Write README", done: 2, planned: 4, intention: nil) == "Write README · 2 / 4 pomodoros")
        #expect(PeekCopy.subtitle(phase: .focus, taskTitle: nil, done: 0, planned: 0, intention: "Read paper") == "Read paper")
        #expect(PeekCopy.subtitle(phase: .focus, taskTitle: nil, done: 0, planned: 0, intention: " ") == "Focus")
        #expect(PeekCopy.subtitle(phase: .longBreak, taskTitle: "x", done: 0, planned: 1, intention: nil) == "Long break")
    }
}

struct NotchStateLayoutTests {
    // This Mac: 14" built-in (notch 185 x 32) and a 1080p external above it.
    let builtin = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                 visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
                                 safeAreaTop: 32, auxLeftWidth: 663, auxRightWidth: 664)
    let external = ScreenGeometry(frame: CGRect(x: -206, y: 982, width: 1920, height: 1080),
                                  visibleFrame: CGRect(x: -206, y: 982, width: 1920, height: 1056), safeAreaTop: 0)

    @Test func notchGeometry() {
        let l = NotchLayout(screen: builtin)
        #expect(l.hasNotch)
        #expect(l.notchSize == CGSize(width: 185, height: 32))
        #expect(l.centerX == 663 + 92.5)
        #expect(l.shapeSize(.collapsed) == CGSize(width: 185 + 128, height: 36))
        let r = l.shapeRect(.collapsed)
        #expect(r.maxY == 982 && r.minX == 755.5 - 156.5)
        #expect(l.hotZone(idle: true) == CGRect(x: 663, y: 950, width: 185, height: 32))
    }

    @Test func collapsedWidthIsTheSameInEveryRunningState() {
        // One presentation (.collapsed) for running, break, paused, done: same size by construction.
        let l = NotchLayout(screen: builtin)
        #expect(l.shapeSize(.collapsed).width == l.notchSize.width + 2 * NotchMetrics().wing)
    }

    @Test func noNotchGeometry() {
        let l = NotchLayout(screen: external)
        #expect(!l.hasNotch)
        #expect(l.topInset == 24)
        #expect(l.shapeSize(.collapsed) == CGSize(width: 104, height: 28))
        #expect(l.hotZone(idle: true).size == CGSize(width: 200, height: 24))
        #expect(l.hotZone(idle: true).maxY == 2062)
        #expect(l.centerX == external.frame.midX)
        // Expanded shapes keep the mock gap under the menu bar (32 → 24: 8 pt shorter).
        #expect(l.shapeSize(.peek).height == 120)
    }

    @Test func panelHoldsEveryShape() {
        for g in [builtin, external] {
            let l = NotchLayout(screen: g)
            for p: NotchPresentation in [.collapsed, .idleHover, .peek, .full(firstRun: true), .choices(ended: .focus)] {
                let r = l.shapeRect(p).insetBy(dx: -NotchMetrics().flare, dy: 0)
                #expect(l.panelFrame.contains(r), "\(p)")
            }
            #expect(l.panelFrame.maxY == g.frame.maxY)
        }
    }

    @Test func fallbackNotchWidthWhenAuxAreasMissing() {
        var g = builtin
        g.auxLeftWidth = nil
        #expect(NotchLayout(screen: g).notchSize.width == 185)
        #expect(NotchLayout(screen: g).centerX == 756)
    }
}
