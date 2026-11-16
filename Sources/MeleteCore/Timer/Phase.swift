import Foundation

/// The three kinds of session.
public enum Phase: String, Codable, CaseIterable, Sendable {
    case focus, shortBreak, longBreak
    public var isBreak: Bool { self != .focus }
}

/// What the engine is doing now.
public enum TimerState: Equatable, Sendable {
    /// No session runs. `TimerEngine.phase` tells which phase starts next.
    case idle
    case running(endsAt: Date, total: TimeInterval)
    case paused(remaining: TimeInterval, total: TimeInterval)
    /// A session reached 0:00 and waits for the user's choice (notch states 9, 10, 4b).
    case awaitingChoice(ended: Phase)
}

/// Why a session ended.
public enum SessionEnd: String, Codable, Sendable {
    case completed, skipped, reset, stopped
}

/// Sent by the engine every time a session ends (any reason).
/// When the user picks "+5 min" after focus, the engine continues the SAME session; when that
/// extension ends it sends a second summary with the same `id` and `isUpdate == true`.
/// The receiver must update the existing record, not insert a new one.
public struct SessionSummary: Equatable, Sendable {
    public let id: UUID
    public let phase: Phase
    public let startedAt: Date
    public let endedAt: Date
    public let plannedDuration: TimeInterval
    public let actualDuration: TimeInterval
    public let end: SessionEnd
    /// True only for a focus session that reached 0:00. A counted pomodoro.
    public let counted: Bool
    public let taskID: UUID?
    public let intention: String?
    public let isUpdate: Bool

    public init(id: UUID, phase: Phase, startedAt: Date, endedAt: Date, plannedDuration: TimeInterval,
                actualDuration: TimeInterval, end: SessionEnd, counted: Bool, taskID: UUID?,
                intention: String?, isUpdate: Bool) {
        self.id = id; self.phase = phase; self.startedAt = startedAt; self.endedAt = endedAt
        self.plannedDuration = plannedDuration; self.actualDuration = actualDuration; self.end = end
        self.counted = counted; self.taskID = taskID; self.intention = intention; self.isUpdate = isUpdate
    }
}

/// Session lengths in seconds plus the cycle length (focus sessions before a long break).
public struct TimerDurations: Equatable, Sendable {
    public var focus: TimeInterval
    public var shortBreak: TimeInterval
    public var longBreak: TimeInterval
    /// 2...6
    public var cycleLength: Int

    public init(focus: TimeInterval = 25 * 60, shortBreak: TimeInterval = 5 * 60,
                longBreak: TimeInterval = 15 * 60, cycleLength: Int = 4) {
        self.focus = focus; self.shortBreak = shortBreak; self.longBreak = longBreak
        self.cycleLength = min(6, max(2, cycleLength))
    }

    public func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .focus: focus
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}
