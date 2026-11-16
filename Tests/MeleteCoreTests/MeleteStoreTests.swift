import Foundation
import Testing
@testable import MeleteCore

@MainActor
struct MeleteStoreTests {
    @Test func countedSessionIncrementsTaskOnce() throws {
        let store = try MeleteStore(inMemory: true)
        let t = store.addTask(title: "Write README", plannedPomodoros: 2)
        let s = SessionSummary(id: UUID(), phase: .focus, startedAt: .now, endedAt: .now, plannedDuration: 60,
                               actualDuration: 60, end: .completed, counted: true, taskID: t.id, intention: nil, isUpdate: false)
        store.record(s)
        store.record(SessionSummary(id: s.id, phase: .focus, startedAt: s.startedAt, endedAt: .now, plannedDuration: 60,
                                    actualDuration: 360, end: .completed, counted: true, taskID: t.id, intention: nil, isUpdate: true))
        #expect(t.completedPomodoros == 1)
        #expect(store.sessions(from: .distantPast, to: .distantFuture).count == 1)
        #expect(store.sessions(from: .distantPast, to: .distantFuture).first?.actualDuration == 360)
    }
}

extension MeleteStoreTests {
    private func summary(id: UUID = UUID(), start: Date = .now, task: UUID? = nil,
                         counted: Bool = true, seconds: Double = 100, update: Bool = false) -> SessionSummary {
        SessionSummary(id: id, phase: .focus, startedAt: start, endedAt: start.addingTimeInterval(seconds),
                       plannedDuration: 100, actualDuration: seconds, end: counted ? .completed : .skipped,
                       counted: counted, taskID: task, intention: "An intention", isUpdate: update)
    }

    @Test func taskCRUDAndManualCompletion() throws {
        let store = try MeleteStore(inMemory: true)
        let task = store.addTask(title: "Draft", plannedPomodoros: 0)
        #expect(store.task(id: task.id) === task)
        #expect(task.plannedPomodoros == 1)
        store.rename(task, to: "Revised")
        store.setPlanned(task, 3)
        #expect(store.tasks().first?.title == "Revised")
        #expect(task.plannedPomodoros == 3)
        store.setPlanned(task, -2)
        #expect(task.plannedPomodoros == 1)
        store.setDone(task, true)
        #expect(task.isDone && task.doneAt != nil)
        store.setDone(task, false)
        #expect(!task.isDone && task.doneAt == nil)
        let id = task.id
        store.delete(task)
        #expect(store.task(id: id) == nil)
        #expect(store.tasks().isEmpty)
    }

    @Test func moveSupportsMultipleRowsAndBothDirections() throws {
        let store = try MeleteStore(inMemory: true)
        for title in ["A", "B", "C", "D"] { store.addTask(title: title) }
        store.move(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        #expect(store.tasks().map(\.title) == ["B", "D", "A", "C"])
        store.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(store.tasks().map(\.title) == ["C", "B", "D", "A"])
        #expect(store.tasks().map(\.sortIndex) == [0, 1, 2, 3])
        store.move(fromOffsets: [], toOffset: 0)
        #expect(store.tasks().count == 4)
    }

    @Test func recordPreservesHistoricalTitleAndCountsPastPlan() throws {
        let store = try MeleteStore(inMemory: true)
        let task = store.addTask(title: "Original")
        let first = summary(task: task.id)
        store.record(first)
        store.rename(task, to: "Renamed")
        store.record(summary(id: first.id, start: first.startedAt, task: task.id, seconds: 400, update: true))
        store.record(summary(task: task.id))
        #expect(task.completedPomodoros == 2)
        #expect(!task.isDone)
        store.delete(task)
        let records = store.sessions(from: .distantPast, to: .distantFuture)
        #expect(records.count == 2)
        #expect(records.first { $0.id == first.id }?.taskTitle == "Original")
        #expect(records.first { $0.id == first.id }?.actualDuration == 400)
        #expect(records.allSatisfy { $0.intention == "An intention" })
    }

    @Test func firstCountedUpdateIncrementsOnlyOnce() throws {
        let store = try MeleteStore(inMemory: true)
        let task = store.addTask(title: "Task")
        let first = summary(task: task.id, counted: false, seconds: 20)
        store.record(first)
        #expect(task.completedPomodoros == 0)
        let counted = summary(id: first.id, start: first.startedAt, task: task.id, update: true)
        store.record(counted)
        store.record(counted)
        store.record(first)
        #expect(task.completedPomodoros == 1)
        let records = store.sessions(from: .distantPast, to: .distantFuture)
        #expect(records.count == 1)
        #expect(records.first?.counted == true)
    }

    @Test func sessionRangeIsHalfOpenAndSortedByStart() throws {
        let store = try MeleteStore(inMemory: true)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(1000)
        store.record(summary(start: end))
        store.record(summary(start: start.addingTimeInterval(500)))
        store.record(summary(start: start.addingTimeInterval(-1)))
        store.record(summary(start: start))
        #expect(store.sessions(from: start, to: end).map(\.startedAt) == [start, start.addingTimeInterval(500)])
        #expect(store.sessions(from: start, to: start).isEmpty)
    }
}
