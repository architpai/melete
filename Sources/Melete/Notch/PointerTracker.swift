import AppKit
import SwiftUI

/// Reports pointer moves and clicks from three sources, so moves are seen in every case:
/// - global monitor: the pointer is over another app (the panel ignores mouse events);
/// - local monitor: events sent to Melete (e.g. Stats/Settings window frontmost);
/// - the panel's tracking area (`.activeAlways`): the pointer is over the panel while Melete is not active.
/// Handlers must be O(1). No timers here.
@MainActor
final class PointerTracker {
    var onMove: (NSPoint) -> Void = { _ in }
    /// A mouse down outside the panel (another app, or another Melete window).
    var onClickOutside: () -> Void = {}
    var onEscape: () -> Void = {}

    private var monitors: [Any] = []
    private weak var panel: NSPanel?

    init(panel: NSPanel) { self.panel = panel }

    func start() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.onMove(NSEvent.mouseLocation) }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.onMove(NSEvent.mouseLocation) }
            return e
        }) { monitors.append(l) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.onClickOutside() }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] e in
            MainActor.assumeIsolated {
                guard let self else { return }
                if e.type == .keyDown {
                    if e.keyCode == 53, e.window === self.panel { self.onEscape() }
                } else if e.window !== self.panel {
                    self.onClickOutside()
                }
            }
            return e
        }) { monitors.append(l) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// Called by the panel's tracking area.
    func trackingMoved() { onMove(NSEvent.mouseLocation) }
}

/// Hosting view with a whole-panel tracking area (`.activeAlways`) so moves over the panel are seen
/// even when Melete is not the active app (the global monitor does not see them then).
final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var onMouse: () -> Void = {}
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }

    override func mouseMoved(with event: NSEvent) { super.mouseMoved(with: event); onMouse() }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); onMouse() }
    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); onMouse() }

    /// First click acts at once (the panel is not key).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
