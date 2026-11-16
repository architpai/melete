import Foundation
import SwiftData

/// One logged session (focus or break, any end reason). Enums are stored as raw strings
/// because SwiftData predicates on enums are not reliable.
@Model
public final class SessionRecord {
    @Attribute(.unique) public var id: UUID
    public var phaseRaw: String
    public var startedAt: Date
    public var endedAt: Date
    public var plannedDuration: TimeInterval
    public var actualDuration: TimeInterval
    public var endRaw: String
    public var counted: Bool
    public var taskID: UUID?
    /// Copied at log time so stats survive task delete/rename.
    public var taskTitle: String?
    public var intention: String?

    public var phase: Phase { Phase(rawValue: phaseRaw) ?? .focus }
    public var end: SessionEnd { SessionEnd(rawValue: endRaw) ?? .completed }

    public init(summary: SessionSummary, taskTitle: String?) {
        id = summary.id
        phaseRaw = summary.phase.rawValue
        startedAt = summary.startedAt
        endedAt = summary.endedAt
        plannedDuration = summary.plannedDuration
        actualDuration = summary.actualDuration
        endRaw = summary.end.rawValue
        counted = summary.counted
        taskID = summary.taskID
        self.taskTitle = taskTitle
        intention = summary.intention
    }

    public var snapshot: SessionSnapshot {
        SessionSnapshot(id: id, phase: phase, startedAt: startedAt, endedAt: endedAt,
                        actualDuration: actualDuration, end: end, counted: counted,
                        taskID: taskID, taskTitle: taskTitle, intention: intention, plannedDuration: plannedDuration)
    }
}

/// Plain value copy of a SessionRecord. StatsCalculator works on these (pure, easy to test).
public struct SessionSnapshot: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var phase: Phase
    public var startedAt: Date
    public var endedAt: Date
    public var actualDuration: TimeInterval
    public var plannedDuration: TimeInterval
    public var end: SessionEnd
    public var counted: Bool
    public var taskID: UUID?
    public var taskTitle: String?
    public var intention: String?

    public init(id: UUID = UUID(), phase: Phase, startedAt: Date, endedAt: Date, actualDuration: TimeInterval,
                end: SessionEnd, counted: Bool, taskID: UUID? = nil, taskTitle: String? = nil, intention: String? = nil,
                plannedDuration: TimeInterval? = nil) {
        self.id = id; self.phase = phase; self.startedAt = startedAt; self.endedAt = endedAt
        self.actualDuration = actualDuration; self.end = end; self.counted = counted
        self.plannedDuration = plannedDuration ?? actualDuration
        self.taskID = taskID; self.taskTitle = taskTitle; self.intention = intention
    }
}
