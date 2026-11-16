import AppKit
import MeleteCore

/// OWNER: coord.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var notch: NotchController!
    private var statsWindow: StatsWindowController!
    private var settingsWindow: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        statsWindow = StatsWindowController(model: model)
        settingsWindow = SettingsWindowController(model: model)
        model.openStats = { [weak self] in self?.statsWindow.show() }
        model.openSettings = { [weak self] in self?.settingsWindow.show() }

        notch = NotchController(model: model)
        notch.start()
        if !model.settings.hasCompletedFirstRun {
            notch.showFullPanel(firstRun: true)
        }
    }

    /// Opening the app again (Finder, Spotlight) opens the full panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        notch.showFullPanel(firstRun: false)
        return false
    }
}
