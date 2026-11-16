import AppKit
import SwiftUI
import MeleteCore

/// OWNER: sol. Keep `init(model:)` and `show()`.
@MainActor
final class StatsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Melete Stats"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: Text("Stats (stub)").padding(40))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
