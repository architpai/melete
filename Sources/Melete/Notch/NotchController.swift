import AppKit
import MeleteCore
import SwiftUI

@MainActor @Observable final class SpikeState {
    var size = CGSize(width: 313, height: 36)
    var full = false
    var text = "" { didSet { NotchLog.log("text=\(text) appActive=\(NSApp.isActive)") } }
}

struct SpikeView: View {
    @Bindable var s: SpikeState
    @FocusState private var focused: Bool
    var body: some View {
        VStack {
            ZStack(alignment: .bottom) {
                Rectangle().fill(.black)
                if s.full {
                    TextField("type here", text: $s.text).textFieldStyle(.roundedBorder).padding(20).focused($focused).onAppear { focused = true }
                } else {
                    Text("spike").foregroundStyle(.white).padding(.bottom, 2)
                }
            }
            .frame(width: s.size.width, height: s.size.height)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Notch shell entry point. OWNER: opus. Keep these three signatures.
@MainActor
final class NotchController {
    let model: AppModel
    private let panel = NotchPanel()
    private lazy var tracker = PointerTracker(panel: panel)
    private let spike = SpikeState()
    private var screen: NSScreen?
    private var layout: NotchLayout?
    private var fullscreen: [CGDirectDisplayID: Bool] = [:]
    private var inside = false

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        let host = TrackingHostingView(rootView: SpikeView(s: spike))
        host.onMouse = { [weak self] in self?.pointerMoved(NSEvent.mouseLocation) }
        panel.contentView = host
        tracker.onMove = { [weak self] p in self?.pointerMoved(p) }
        tracker.onClickOutside = { [weak self] in NotchLog.log("clickOutside"); self?.setFull(false) }
        tracker.onEscape = { [weak self] in NotchLog.log("escape"); self?.setFull(false) }
        tracker.start()
        refreshFullscreen()
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFullscreen() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screen = nil; self?.refreshFullscreen(); self?.moveTo(self?.pointerScreen()) }
        }
        moveTo(pointerScreen())
        panel.orderFrontRegardless()
        if ProcessInfo.processInfo.environment["MELETE_DEBUG_STATE"] == "full" { setFull(true) }
    }

    func showFullPanel(firstRun: Bool) { setFull(true) }

    private func pointerScreen() -> NSScreen? {
        if let pin = ProcessInfo.processInfo.environment["MELETE_DEBUG_SCREEN"] {
            if pin == "builtin" { return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } }
            if pin == "external" { return NSScreen.screens.first { $0.safeAreaInsets.top == 0 } }
        }
        return NSScreen.containing(NSEvent.mouseLocation) ?? NSScreen.main
    }

    private func refreshFullscreen() {
        for s in NSScreen.screens { fullscreen[s.displayID] = FullscreenDetector.isFullscreen(s) }
        NotchLog.log("fullscreen \(NSScreen.screens.map { "\($0.localizedName)=\(fullscreen[$0.displayID] ?? false)" })")
    }

    private func moveTo(_ s: NSScreen?) {
        guard let s else { return }
        screen = s
        let l = NotchLayout(screen: s.notchGeometry)
        layout = l
        panel.setFrame(l.panelFrame, display: true)
        NotchLog.log("screen \(s.localizedName) notch=\(l.hasNotch) notchSize=\(l.notchSize) panel=\(l.panelFrame)")
    }

    private func shapeRect() -> CGRect {
        guard let layout else { return .zero }
        let f = layout.panelFrame
        return CGRect(x: f.midX - spike.size.width / 2, y: f.maxY - spike.size.height, width: spike.size.width, height: spike.size.height)
    }

    private func pointerMoved(_ p: NSPoint) {
        if !spike.full, let s = NSScreen.containing(p), s.displayID != screen?.displayID,
           ProcessInfo.processInfo.environment["MELETE_DEBUG_SCREEN"] == nil {
            NotchLog.log("follow → \(s.localizedName)")
            moveTo(s)
        }
        let now = shapeRect().contains(p)
        if now != inside {
            inside = now
            panel.ignoresMouseEvents = !now
            NotchLog.log("inside=\(now) at \(p)")
        }
    }

    private func setFull(_ on: Bool) {
        spike.full = on
        spike.size = on ? CGSize(width: 440, height: 200) : CGSize(width: 313, height: 36)
        panel.allowsKey = on; if on { panel.ignoresMouseEvents = false }
        if on { panel.makeKey() } else { panel.resignKey() }
        NotchLog.log("full=\(on) isKey=\(panel.isKeyWindow)")
    }
}
