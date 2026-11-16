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
