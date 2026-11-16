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

    // Task-list text drafts. They live here (not in view @State) so the controller can commit them
    // before the full panel closes (Esc, click outside, session end, fullscreen).
    var addingTask = false
    var newTaskTitle = ""
    var renamingTask: UUID?
    var renameText = ""

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

    /// Save the typed text: a rename in progress and a non-empty new task. The intention is saved as typed.
    func commitTextEdits() {
        if let id = renamingTask {
            let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, let t = taskStore.task(id: id) { taskStore.rename(t, to: title) }
            renamingTask = nil
            renameText = ""
        }
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { taskStore.addTask(title: title) }
        newTaskTitle = ""
        addingTask = false
    }

    /// Run an engine action that ends a choice (Start, Break, Focus, +5, Skip, Stop): collapse the notch.
    func act(_ f: (TimerEngine) -> Void) {
        f(engine)
        send(.engine(status)) // before collapsing, so the shape goes straight to the new state
        send(.actionDone)
    }
}
