import AppKit
import MeleteCore
import Observation

/// Composition root. OWNER: coord. Wires engine events to the store, the chime and the notch.
@MainActor
@Observable
final class AppModel {
    let settings: MeleteSettings
    let store: MeleteStore
    let engine: TimerEngine
    @ObservationIgnored let chime = ChimePlayer()

    /// Set by AppDelegate. Open the windows that sol provides.
    @ObservationIgnored var openStats: () -> Void = {}
    @ObservationIgnored var openSettings: () -> Void = {}
    /// Set by the notch shell. Called when a session reaches 0:00 (open state 9 / 10).
    @ObservationIgnored var onSessionReachedZero: ((Phase) -> Void)?

    init() {
        settings = MeleteSettings()
        do {
            store = try MeleteStore()
        } catch {
            NSLog("Melete: could not open the store, using memory only: \(error)")
            store = try! MeleteStore(inMemory: true)
        }
        engine = TimerEngine(durations: settings.durations)

        engine.onSessionEnded = { [weak self] summary in
            self?.store.record(summary)
        }
        engine.onPhaseEnded = { [weak self] phase in
            guard let self else { return }
            self.chime.play(name: self.settings.chimeName, volume: self.settings.chimeVolume)
            self.onSessionReachedZero?(phase)
        }
        observeSettings()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine.reconcile() }
        }
    }

    /// The current task title, if a task is selected.
    var currentTaskTitle: String? {
        engine.currentTaskID.flatMap { store.task(id: $0)?.title }
    }

    func quit() { NSApp.terminate(nil) }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.durations
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.engine.durations = self.settings.durations
                self.observeSettings()
            }
        }
    }
}
