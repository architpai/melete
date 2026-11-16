import Foundation
import SwiftData

@Model
public final class TaskItem {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var plannedPomodoros: Int
    /// Can go past `plannedPomodoros` (e.g. 5 / 4).
    public var completedPomodoros: Int
    /// Set only by the user (no auto-done).
    public var isDone: Bool
    public var doneAt: Date?
    public var createdAt: Date
    public var sortIndex: Int

    public init(title: String, plannedPomodoros: Int = 1, sortIndex: Int = 0, createdAt: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.plannedPomodoros = max(1, plannedPomodoros)
        self.completedPomodoros = 0
        self.isDone = false
        self.doneAt = nil
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }
}
