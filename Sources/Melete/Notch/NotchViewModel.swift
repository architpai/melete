import MeleteCore
import Observation
import SwiftUI

/// Shared state for the notch views. The controller owns it and feeds events to `machine`.
@MainActor
@Observable
final class NotchViewModel {
    var machine: NotchMachine
    var layout: NotchLayout
    let model: AppModel
    /// Store for the task list. Normally `model.store`; DEBUG `MELETE_DEBUG_SEED=1` uses a seeded in-memory store.
    let taskStore: MeleteStore
    /// Pointer in SwiftUI window coordinates (top-left origin), only while the full panel shows.
    /// Drives row hover: SwiftUI `onHover` does not fire in a non-activating panel of an inactive app.
    var pointerInPanel: CGPoint?
    @ObservationIgnored var send: (NotchEvent) -> Void = { _ in }

    init(model: AppModel, taskStore: MeleteStore, machine: NotchMachine, layout: NotchLayout) {
        self.model = model
        self.taskStore = taskStore
        self.machine = machine
        self.layout = layout
    }

    var engine: TimerEngine { model.engine }
    var presentation: NotchPresentation { machine.presentation }

    var status: NotchEngineStatus { NotchEngineStatus(state: engine.state, phase: engine.phase) }

    var currentTask: TaskItem? { engine.currentTaskID.flatMap { taskStore.task(id: $0) } }

    /// Task title, else the intention (for "who" lines).
    var who: String? {
        if let t = currentTask?.title, !t.isEmpty { return t }
        if let i = engine.intention?.trimmingCharacters(in: .whitespaces), !i.isEmpty { return i }
        return nil
    }

    /// Run an engine action that ends a choice (Start, Break, Focus, +5, Skip, Stop): collapse the notch.
    func act(_ f: (TimerEngine) -> Void) {
        f(engine)
        send(.engine(status)) // before collapsing, so the shape goes straight to the new state
        send(.actionDone)
    }
}
