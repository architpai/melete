import Foundation

public enum NotchFormat {
    /// "18:42", "1:05:00" (same as `Mono.clock`).
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// "1 more to long break", "Long break next".
    public static func cycleNote(cyclePosition: Int, cycleLength: Int) -> String {
        let left = max(0, cycleLength - cyclePosition)
        return left == 0 ? "Long break next" : "\(left) more to long break"
    }

    public static func phaseName(_ p: Phase) -> String {
        switch p {
        case .focus: "Focus"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }
}

/// What the collapsed notch (B) or the no-notch tab shows. Pure, so the rules are testable.
public struct CollapsedContent: Equatable, Sendable {
    public enum Icon: Equatable, Sendable { case none, cup, pause }
    public enum Label: Equatable, Sendable { case time(TimeInterval), done }
    public enum Bar: Equatable, Sendable { case solid, dashed, dim, dashedDim }

    public var dots: Int
    public var filledDots: Int
    public var icon: Icon
    public var label: Label
    /// Break: time at 60 % (ink2).
    public var dimText: Bool
    /// Paused time and "Done" blink slowly.
    public var blink: Bool
    public var bar: Bar
    public var progress: Double
    /// The countdown changes every second (redraw once per second only then).
    public var ticks: Bool

    /// Nil when idle (nothing to show).
    public static func make(status: NotchEngineStatus, cyclePosition: Int, cycleLength: Int,
                            remaining: TimeInterval, progress: Double) -> CollapsedContent? {
        let dots = min(6, max(2, cycleLength))
        let filled = min(dots, max(0, cyclePosition))
        switch status {
        case .idle:
            return nil
        case let .running(p):
            return CollapsedContent(dots: dots, filledDots: filled, icon: p.isBreak ? .cup : .none,
                                    label: .time(remaining), dimText: p.isBreak, blink: false,
                                    bar: p.isBreak ? .dashed : .solid, progress: progress, ticks: true)
        case let .paused(p):
            return CollapsedContent(dots: dots, filledDots: filled, icon: .pause, label: .time(remaining),
                                    dimText: p.isBreak, blink: true, bar: p.isBreak ? .dashedDim : .dim,
                                    progress: progress, ticks: false)
        case .awaiting:
            return CollapsedContent(dots: dots, filledDots: filled, icon: .none, label: .done, dimText: false,
                                    blink: true, bar: .solid, progress: 1, ticks: false)
        }
    }
}

/// Texts of the session-end panels (9, 10).
public struct SessionEndCopy: Equatable, Sendable {
    public var title: String
    public var detail: String
    /// Focus end only: "1 more to long break".
    public var cycleNote: String?
    public var primary: String
    /// Secondary button labels, in order.
    public var secondary: [String]

    /// `who` = task title or intention (nil when none).
    public static func focusEnded(who: String?, cyclePosition: Int, cycleLength: Int,
                                  nextBreak: Phase, breakDuration: TimeInterval) -> SessionEndCopy {
        let name = nextBreak == .longBreak ? "Long break" : "Break"
        return SessionEndCopy(title: "Focus done", detail: who ?? "Pomodoro counted",
                              cycleNote: NotchFormat.cycleNote(cyclePosition: cyclePosition, cycleLength: cycleLength),
                              primary: "\(name) \(NotchFormat.clock(breakDuration))", secondary: ["+5 min", "Skip"])
    }

    public static func breakEnded(who: String?, focusDuration: TimeInterval) -> SessionEndCopy {
        SessionEndCopy(title: "Break over", detail: "Next: \(who ?? "focus")", cycleNote: nil,
                       primary: "Focus \(NotchFormat.clock(focusDuration))", secondary: ["Stop"])
    }
}

/// The small line above the time in the hover peek (7).
public enum PeekCopy {
    public static func subtitle(phase: Phase, taskTitle: String?, done: Int, planned: Int, intention: String?) -> String {
        if phase.isBreak { return NotchFormat.phaseName(phase) }
        if let t = taskTitle, !t.isEmpty { return "\(t) · \(done) / \(planned) pomodoros" }
        if let i = intention?.trimmingCharacters(in: .whitespaces), !i.isEmpty { return i }
        return "Focus"
    }
}
