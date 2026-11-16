import Foundation

/// The engine state as the notch sees it.
public enum NotchEngineStatus: Equatable, Sendable {
    case idle
    case running(Phase)
    case paused(Phase)
    case awaiting(Phase)

    public init(state: TimerState, phase: Phase) {
        switch state {
        case .idle: self = .idle
        case .running: self = .running(phase)
        case .paused: self = .paused(phase)
        case let .awaitingChoice(ended): self = .awaiting(ended)
        }
    }

    public var isIdle: Bool { self == .idle }
    public var awaitingPhase: Phase? { if case let .awaiting(p) = self { return p }; return nil }
}

/// How far the notch is open (on top of the engine state).
public enum NotchExpansion: Equatable, Sendable {
    case none
    /// Opened by the pointer; closes when the pointer leaves (state 2, 7, or 9/10 from 4b hover).
    case hover
    /// Clicked open (8). Closes on click outside, Esc, Start, or a window icon.
    case full
    /// Session-end choices (9/10) that opened by themselves at 0:00. Close after 30 s → 4b.
    case choicesAuto
    /// Choices opened by a click on 4b. Close on click outside or Esc.
    case choicesPinned
}

public enum NotchTimerKind: Sendable, CaseIterable {
    /// Hover-zone dwell (no-notch idle 0.4 s, fullscreen 1 s).
    case dwell
    /// Delay after the pointer leaves.
    case exit
    /// Session-end panel auto close.
    case autoClose
}

public enum NotchEffect: Equatable, Sendable {
    case schedule(NotchTimerKind, TimeInterval)
    case cancel(NotchTimerKind)
    case makeKey
    case resignKey
    case markFirstRunDone
}

public struct NotchTimings: Equatable, Sendable {
    public var hoverZoneDwell: TimeInterval
    public var fullscreenDwell: TimeInterval
    public var exitDelay: TimeInterval
    public var autoClose: TimeInterval

    public init(hoverZoneDwell: TimeInterval = 0.4, fullscreenDwell: TimeInterval = 1.0,
                exitDelay: TimeInterval = 0.3, autoClose: TimeInterval = 30) {
        self.hoverZoneDwell = hoverZoneDwell; self.fullscreenDwell = fullscreenDwell
        self.exitDelay = exitDelay; self.autoClose = autoClose
    }
}

public enum NotchEvent: Equatable, Sendable {
    /// The pointer entered / left the hit rect (the shape when visible, the hot zone when hidden).
    case pointer(inside: Bool)
    case timerFired(NotchTimerKind)
    /// A click on the shape background (not on a control).
    case clickShape
    case clickOutside
    case escape
    /// The engine reached 0:00 (`AppModel.onSessionReachedZero`).
    case sessionReachedZero(Phase)
    /// The engine state changed.
    case engine(NotchEngineStatus)
    /// The user chose Start or a session-end choice: collapse.
    case actionDone
    case openFull(firstRun: Bool)
    /// The pointer moved to another screen, or the fullscreen state of the current screen changed.
    case screen(hasNotch: Bool, fullscreen: Bool)
}

/// Pure notch state machine: events in, state + timer/focus effects out. The controller runs the effects.
/// Rules: docs/spec.md "Notch states" + "Displays", docs/architecture.md "State machine decisions".
public struct NotchMachine: Equatable, Sendable {
    public let timings: NotchTimings
    public private(set) var status: NotchEngineStatus
    public private(set) var hasNotch: Bool
    public private(set) var fullscreen: Bool
    public private(set) var expansion: NotchExpansion = .none
    /// Fullscreen only: shown after a 1 s hover at the top center.
    public private(set) var revealed = false
    public private(set) var pointerInside = false
    /// After an action collapses the notch, do not reopen on hover until the pointer leaves.
    public private(set) var suppressHover = false
    public private(set) var firstRun = false

    public init(status: NotchEngineStatus = .idle, hasNotch: Bool = true, fullscreen: Bool = false,
                timings: NotchTimings = NotchTimings()) {
        self.status = status; self.hasNotch = hasNotch; self.fullscreen = fullscreen; self.timings = timings
    }

    /// False while hidden by a fullscreen app.
    public var isShown: Bool {
        if !fullscreen || revealed { return true }
        switch expansion {
        case .full, .choicesAuto, .choicesPinned: return true
        case .none, .hover: return false
        }
    }

    public var presentation: NotchPresentation {
        guard isShown else { return .hidden }
        switch expansion {
        case .full:
            return .full(firstRun: firstRun)
        case .choicesAuto, .choicesPinned:
            if let p = status.awaitingPhase { return .choices(ended: p) }
            return status.isIdle ? .hidden : .collapsed
        case .hover:
            switch status {
            case .idle: return .idleHover
            case .running, .paused: return .peek
            case let .awaiting(p): return .choices(ended: p)
            }
        case .none:
            return status.isIdle ? .hidden : .collapsed
        }
    }

    /// Hit-test against the hot zone (true) or against the visible shape (false).
    public var usesHotZone: Bool { presentation == .hidden }

    /// The panel takes key focus only in the full panel (intention and task fields).
    public var wantsKey: Bool { expansion == .full }

    @discardableResult
    public mutating func handle(_ event: NotchEvent) -> [NotchEffect] {
        var fx: [NotchEffect] = []
        switch event {
        case let .pointer(inside):
            guard inside != pointerInside else { return [] }
            pointerInside = inside
            inside ? pointerEntered(&fx) : pointerLeft(&fx)

        case .timerFired(.dwell):
            guard pointerInside else { break }
            if fullscreen && !revealed {
                revealed = true
                if status.isIdle { expansion = .hover } else { suppressHover = true }
            } else if status.isIdle, expansion == .none {
                expansion = .hover
            }

        case .timerFired(.exit):
            guard !pointerInside else { break }
            if expansion == .hover { expansion = .none }
            if expansion == .none { revealed = false }

        case .timerFired(.autoClose):
            if expansion == .choicesAuto { collapse(&fx) }

        case .clickShape:
            switch expansion {
            case .none, .hover:
                if status.awaitingPhase != nil {
                    expansion = .choicesPinned
                } else {
                    openFull(firstRun: false, &fx)
                }
            case .full, .choicesAuto, .choicesPinned:
                break
            }

        case .clickOutside:
            switch expansion {
            case .full, .choicesPinned: collapse(&fx)
            case .none, .hover, .choicesAuto: break
            }

        case .escape:
            if expansion != .none { collapse(&fx) }

        case let .sessionReachedZero(p):
            status = .awaiting(p)
            if expansion == .full { break }
            if pointerInside && isShownIgnoringExpansion {
                expansion = .hover
            } else {
                expansion = .choicesAuto
                fx.append(.schedule(.autoClose, timings.autoClose))
            }

        case let .engine(new):
            let old = status
            status = new
            let leftChoice = old.awaitingPhase != nil && new.awaitingPhase == nil
            switch expansion {
            case .choicesAuto, .choicesPinned:
                if new.awaitingPhase == nil { collapse(&fx) }
            case .hover:
                if leftChoice { collapse(&fx) }
            case .none, .full:
                break
            }

        case .actionDone:
            collapse(&fx)

        case let .openFull(firstRun):
            openFull(firstRun: firstRun, &fx)

        case let .screen(notch, fs):
            hasNotch = notch
            if fs != fullscreen { revealed = false }
            fullscreen = fs
            pointerInside = false
            suppressHover = false
            if expansion == .hover { expansion = .none }
            fx.append(.cancel(.dwell))
            fx.append(.cancel(.exit))
        }
        return fx
    }

    // MARK: Helpers

    private var isShownIgnoringExpansion: Bool { !fullscreen || revealed }

    private mutating func pointerEntered(_ fx: inout [NotchEffect]) {
        fx.append(.cancel(.exit))
        if presentation == .hidden {
            if fullscreen && !revealed {
                fx.append(.schedule(.dwell, timings.fullscreenDwell))
            } else if status.isIdle {
                if hasNotch { expansion = .hover } else { fx.append(.schedule(.dwell, timings.hoverZoneDwell)) }
            }
            return
        }
        switch expansion {
        case .choicesAuto:
            // The user came to look: now it behaves like a hover panel (closes when the pointer leaves).
            expansion = .hover
            fx.append(.cancel(.autoClose))
        case .none:
            if !suppressHover { expansion = .hover }
        case .hover, .full, .choicesPinned:
            break
        }
    }

    private mutating func pointerLeft(_ fx: inout [NotchEffect]) {
        suppressHover = false
        fx.append(.cancel(.dwell))
        if expansion == .hover || (revealed && expansion == .none) {
            fx.append(.schedule(.exit, timings.exitDelay))
        }
    }

    private mutating func openFull(firstRun: Bool, _ fx: inout [NotchEffect]) {
        if expansion == .choicesAuto { fx.append(.cancel(.autoClose)) }
        expansion = .full
        self.firstRun = firstRun
        fx.append(.makeKey)
        if firstRun { fx.append(.markFirstRunDone) }
    }

    /// Back to the collapsed (or hidden) state. In fullscreen it hides again.
    private mutating func collapse(_ fx: inout [NotchEffect]) {
        if expansion == .full { fx.append(.resignKey) }
        if expansion == .choicesAuto { fx.append(.cancel(.autoClose)) }
        expansion = .none
        firstRun = false
        suppressHover = pointerInside
        if fullscreen { revealed = false }
    }
}
