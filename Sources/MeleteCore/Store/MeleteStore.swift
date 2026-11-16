import Foundation
import SwiftData

/// Local-only persistence (SwiftData). One store file in Application Support/Melete/.
@MainActor
public final class MeleteStore {
    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }

    public init(inMemory: Bool = false) throws {
        let schema = Schema([TaskItem.self, SessionRecord.self])
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let dir = URL.applicationSupportDirectory.appending(path: "Melete", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            config = ModelConfiguration(schema: schema, url: dir.appending(path: "Melete.store"))
        }
        container = try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: Tasks

    public func tasks() -> [TaskItem] {
        (try? context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]))) ?? []
    }

    public func task(id: UUID) -> TaskItem? {
        var d = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    @discardableResult
    public func addTask(title: String, plannedPomodoros: Int = 1) -> TaskItem {
        let next = (tasks().map(\.sortIndex).max() ?? -1) + 1
        let t = TaskItem(title: title, plannedPomodoros: plannedPomodoros, sortIndex: next)
        context.insert(t)
        save()
        return t
    }

    public func rename(_ task: TaskItem, to title: String) { task.title = title; save() }
    public func setPlanned(_ task: TaskItem, _ n: Int) { task.plannedPomodoros = max(1, n); save() }
    public func setDone(_ task: TaskItem, _ done: Bool) { task.isDone = done; task.doneAt = done ? Date() : nil; save() }
    public func delete(_ task: TaskItem) { context.delete(task); save() }

    /// Reorder like SwiftUI `onMove`.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var list = tasks()
        let moving = source.sorted().map { list[$0] }
        for i in source.sorted(by: >) { list.remove(at: i) }
        let insertAt = destination - source.filter { $0 < destination }.count
        list.insert(contentsOf: moving, at: max(0, min(insertAt, list.count)))
        for (i, t) in list.enumerated() { t.sortIndex = i }
        save()
    }

    // MARK: Sessions

    /// Insert a new record, or update the record with the same id (`summary.isUpdate`).
    /// Increments the task's `completedPomodoros` once, the first time a record becomes counted.
    public func record(_ summary: SessionSummary) {
        let id = summary.id
        var d = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        let existing = try? context.fetch(d).first
        let wasCounted = existing?.counted ?? false
        let title = summary.taskID.flatMap { task(id: $0)?.title }
        if let r = existing {
            r.endedAt = summary.endedAt
            r.actualDuration = summary.actualDuration
            r.endRaw = summary.end.rawValue
            r.counted = summary.counted || r.counted
        } else {
            context.insert(SessionRecord(summary: summary, taskTitle: title))
        }
        if summary.counted, !wasCounted, let tid = summary.taskID, let t = task(id: tid) {
            t.completedPomodoros += 1
        }
        save()
    }

    public func sessions(from start: Date, to end: Date) -> [SessionRecord] {
        let d = FetchDescriptor<SessionRecord>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)])
        return (try? context.fetch(d)) ?? []
    }

    public func save() {
        do { try context.save() } catch { NSLog("Melete: save failed: \(error)") }
    }
}
