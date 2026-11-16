import AppKit
import MeleteCore

/// Notch shell entry point. OWNER: opus. Replace the stub bodies; keep these three signatures.
@MainActor
final class NotchController {
    let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    /// Create the panel, start screen/hover/fullscreen tracking. In DEBUG, honor MELETE_DEBUG_STATE.
    func start() {}

    /// Open state 8. `firstRun` shows the "Melete lives here" hint and then sets
    /// `model.settings.hasCompletedFirstRun = true`.
    func showFullPanel(firstRun: Bool) {}
}
