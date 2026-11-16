import AppKit
import SwiftUI
import MeleteCore

/// OWNER: sol. Keep `init(model:)` and `show()`.
@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Melete Settings"
            w.isReleasedWhenClosed = false
            let model = self.model
            w.contentView = NSHostingView(rootView: VStack(spacing: 16) {
                Text("Settings (stub)")
                Button("Quit Melete") { model.quit() }
            }.padding(40))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
