import AppKit
import MeleteCore
import SwiftUI

/// Notch shell entry point. OWNER: opus. Keep these three signatures.
///
/// One transparent panel sits at the top center of the pointer's screen. SwiftUI draws the black shape
/// for the current `NotchPresentation`. The panel takes mouse events only while the pointer is inside
/// that shape; everything else passes through. `NotchMachine` (MeleteCore) holds the rules.
@MainActor
final class NotchController {
    let model: AppModel
    private let panel = NotchPanel()
    private lazy var tracker = PointerTracker(panel: panel)
    private var vm: NotchViewModel!
    private var screenID: CGDirectDisplayID?
    private var fullscreen: [CGDirectDisplayID: Bool] = [:]
    private var timers: [NotchTimerKind: DispatchWorkItem] = [:]
    private var lastPointer = NSPoint.zero
    private var observers: [NSObjectProtocol] = []
    private let debug = DebugOptions()

    init(model: AppModel) {
        self.model = model
    }

    // MARK: Contract

    /// Create the panel, start screen/hover/fullscreen tracking. In DEBUG, honor MELETE_DEBUG_STATE.
    func start() {
        let screen = pointerScreen() ?? NSScreen.main ?? NSScreen.screens[0]
        screenID = screen.displayID
        let layout = layoutFor(screen)
        refreshFullscreen()
        let machine = NotchMachine(status: NotchEngineStatus(state: model.engine.state, phase: model.engine.phase),
                                   hasNotch: layout.hasNotch, fullscreen: isFullscreen(screen),
                                   timings: NotchTimings(hoverZoneDwell: Mono.hoverZoneDwell,
                                                         fullscreenDwell: Mono.fullscreenHoverDwell,
                                                         exitDelay: Mono.hoverExitDelay,
                                                         autoClose: Mono.sessionEndAutoClose))
        vm = NotchViewModel(model: model, taskStore: debug.taskStore ?? model.store, machine: machine, layout: layout)
        vm.send = { [weak self] e in self?.send(e) }

        let host = TrackingHostingView(rootView: NotchRootView(vm: vm))
        host.onMouse = { [weak self] in self?.pointerMoved(NSEvent.mouseLocation) }
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(layout.panelFrame, display: false)
        panel.orderFrontRegardless()

        tracker.onMove = { [weak self] p in self?.pointerMoved(p) }
        tracker.onClickOutside = { [weak self] in self?.send(.clickOutside) }
        tracker.onEscape = { [weak self] in self?.send(.escape) }
        tracker.start()

        model.onSessionReachedZero = { [weak self] phase in self?.sessionReachedZero(phase) }
        observeEngine()
        observeSystem()
        debug.apply(to: self)
        NotchLog.log("start screen=\(screen.localizedName) notch=\(layout.hasNotch) fullscreen=\(isFullscreen(screen))")
    }

    /// Open state 8. `firstRun` shows the "Melete lives here" hint and then sets
    /// `model.settings.hasCompletedFirstRun = true`.
    func showFullPanel(firstRun: Bool) {
        // A debug state wins over the app's first-run call (debug runs never mark the first run done).
        if firstRun, let state = debug.state, state != "firstRun" { return }
        if vm.machine.expansion != .full, let s = pointerScreen() { moveTo(s) }
        send(.openFull(firstRun: firstRun))
    }

    // MARK: Events

    fileprivate func send(_ event: NotchEvent) {
        let before = vm.machine.presentation
        let effects = vm.machine.handle(event)
        for fx in effects { run(fx) }
        let after = vm.machine.presentation
        if before != after { NotchLog.log("\(event) → \(after)") }
        updatePanel()
    }

    private func run(_ fx: NotchEffect) {
        switch fx {
        case let .schedule(kind, delay):
            timers[kind]?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.timers[kind] = nil
                self?.send(.timerFired(kind))
            }
            timers[kind] = item
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        case let .cancel(kind):
            timers[kind]?.cancel()
            timers[kind] = nil
        case .makeKey:
            panel.allowsKey = true
            panel.makeKey()
        case .resignKey:
            panel.resignKey()
            panel.allowsKey = false
        case .markFirstRunDone:
            if !debug.keepFirstRun { model.settings.hasCompletedFirstRun = true }
        }
    }

    /// Mouse pass-through: accept events only while the pointer is inside the visible shape.
    private func updatePanel() {
        panel.allowsKey = vm.machine.wantsKey
        let accepts = !vm.machine.usesHotZone && contains(hitRect(), lastPointer)
        if panel.ignoresMouseEvents == accepts {
            panel.ignoresMouseEvents = !accepts
            NotchLog.log("accepts mouse = \(accepts)")
        }
    }

    private func hitRect() -> CGRect {
        let m = vm.machine
        return m.usesHotZone ? vm.layout.hotZone(idle: m.status.isIdle) : vm.layout.shapeRect(m.presentation)
    }

    /// Inclusive of the top edge (the pointer can sit on y == maxY).
    private func contains(_ r: CGRect, _ p: NSPoint) -> Bool {
        p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY
    }

    private func pointerMoved(_ p: NSPoint) {
        lastPointer = p
        guard !debug.pinned else { return }
        if canFollowPointer, let s = NSScreen.containing(p), s.displayID != screenID {
            moveTo(s)
        }
        let inPanel: CGPoint? = vm.machine.expansion == .full && contains(panel.frame, p)
            ? CGPoint(x: p.x - panel.frame.minX, y: panel.frame.maxY - p.y) : nil
        if inPanel != vm.pointerInPanel { vm.pointerInPanel = inPanel; NotchLog.log("inPanel \(String(describing: inPanel))") }
        let inside = contains(hitRect(), p)
        if inside != vm.machine.pointerInside {
            NotchLog.log("pointer inside=\(inside) at \(p)")
            send(.pointer(inside: inside))
        } else {
            updatePanel()
        }
    }

    /// Stay on the screen while the user works in an open panel.
    private var canFollowPointer: Bool {
        if debug.screenPin != nil { return false }
        switch vm.machine.expansion {
        case .none: return true
        case .hover, .full, .choicesAuto, .choicesPinned: return false
        }
    }

    private func sessionReachedZero(_ phase: Phase) {
        if vm.machine.expansion != .full, debug.screenPin == nil, let s = NSScreen.containing(NSEvent.mouseLocation) {
            refreshFullscreen()
            moveTo(s)
        }
        send(.sessionReachedZero(phase))
    }

    // MARK: Screens

    private func pointerScreen() -> NSScreen? {
        if let pin = debug.screenPin { return pin() }
        return NSScreen.containing(NSEvent.mouseLocation)
    }

    private func layoutFor(_ s: NSScreen) -> NotchLayout {
        var g = s.notchGeometry
        if debug.forceNoNotch { g.safeAreaTop = 0; g.auxLeftWidth = nil; g.auxRightWidth = nil }
        return NotchLayout(screen: g)
    }

    private func moveTo(_ s: NSScreen) {
        let layout = layoutFor(s)
        let changed = s.displayID != screenID || layout != vm.layout
        screenID = s.displayID
        guard changed else { return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { vm.layout = layout }
        panel.setFrame(layout.panelFrame, display: true)
        send(.screen(hasNotch: layout.hasNotch, fullscreen: isFullscreen(s)))
        NotchLog.log("screen → \(s.localizedName) notch=\(layout.hasNotch) fullscreen=\(isFullscreen(s))")
    }

    private func isFullscreen(_ s: NSScreen) -> Bool {
        if debug.ignoreFullscreen { return false }
        return fullscreen[s.displayID] ?? false
    }

    private func refreshFullscreen() {
        for s in NSScreen.screens { fullscreen[s.displayID] = FullscreenDetector.isFullscreen(s) }
    }

    /// Fullscreen is checked on space / app / screen changes only (never on mouse moves).
    private func fullscreenMayHaveChanged() {
        refreshFullscreen()
        guard let vm, let s = NSScreen.screens.first(where: { $0.displayID == screenID }) else { return }
        let fs = isFullscreen(s)
        if fs != vm.machine.fullscreen {
            NotchLog.log("fullscreen \(s.localizedName) = \(fs)")
            send(.screen(hasNotch: vm.layout.hasNotch, fullscreen: fs))
        }
    }

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.fullscreenMayHaveChanged()
                    // Entering / leaving fullscreen animates; check again when it has settled.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.fullscreenMayHaveChanged() }
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshFullscreen()
                let s = self.pointerScreen() ?? NSScreen.main
                self.screenID = nil
                if let s { self.moveTo(s) }
            }
        })
    }

    /// Feed engine state changes to the machine (state and phase are @Observable).
    private func observeEngine() {
        withObservationTracking {
            _ = model.engine.state
            _ = model.engine.phase
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let status = NotchEngineStatus(state: self.model.engine.state, phase: self.model.engine.phase)
                if status != self.vm.machine.status { self.send(.engine(status)) }
                self.observeEngine()
            }
        }
    }

    // MARK: Debug hooks

    fileprivate func debugPointer(inside: Bool) { send(.pointer(inside: inside)) }
}

/// DEBUG-only launch options (env vars). All off in release builds.
/// - MELETE_DEBUG_STATE: idle, idleHover, running, break, paused, done, peek, full, focusEnd, breakEnd, noNotch, firstRun
/// - MELETE_DEBUG_SCREEN=builtin|external: pin the notch to a screen.
/// - MELETE_DEBUG_NO_FULLSCREEN=1: ignore fullscreen (for screenshots over a fullscreen app).
/// - MELETE_DEBUG_SEED=1: show sample tasks from an in-memory store (the real store is not touched).
/// - MELETE_DEBUG_SECONDS=N: every session lasts N seconds, and sessions are not logged to the store.
@MainActor
private struct DebugOptions {
    var state: String?
    var screenPin: (() -> NSScreen?)?
    var ignoreFullscreen = false
    var forceNoNotch = false
    var keepFirstRun = false
    var taskStore: MeleteStore?
    /// Hover-type debug states ignore the real pointer so they stay put for screenshots.
    var pinned = false
    var shortSessions: TimeInterval?

    init() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        state = env["MELETE_DEBUG_STATE"].flatMap { $0.isEmpty ? nil : $0 }
        switch env["MELETE_DEBUG_SCREEN"] {
        case "builtin": screenPin = { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main }
        case "external": screenPin = { NSScreen.screens.first { $0.safeAreaInsets.top == 0 } ?? NSScreen.main }
        default: break
        }
        ignoreFullscreen = env["MELETE_DEBUG_NO_FULLSCREEN"] == "1"
        forceNoNotch = state == "noNotch"
        keepFirstRun = state != nil
        pinned = ["idleHover", "peek", "focusEnd", "breakEnd", "full", "firstRun"].contains(state ?? "")
        shortSessions = env["MELETE_DEBUG_SECONDS"].flatMap(TimeInterval.init)
        if env["MELETE_DEBUG_SEED"] == "1", let s = try? MeleteStore(inMemory: true) {
            let a = s.addTask(title: "Write README", plannedPomodoros: 4); a.completedPomodoros = 2
            let b = s.addTask(title: "Review PR #12", plannedPomodoros: 2); _ = b
            let c = s.addTask(title: "Plan sprint", plannedPomodoros: 1); c.completedPomodoros = 1; s.setDone(c, true)
            s.save()
            taskStore = s
        }
        #endif
    }

    func apply(to c: NotchController) {
        #if DEBUG
        if let n = shortSessions {
            let e = c.model.engine
            e.durations = TimerDurations(focus: n, shortBreak: n, longBreak: n, cycleLength: e.durations.cycleLength)
            e.onSessionEnded = nil
        }
        guard let state else { return }
        let e = c.model.engine
        let now = Date()
        if let first = (taskStore ?? c.model.store).tasks().first { e.currentTaskID = first.id }
        switch state {
        case "running", "peek", "noNotch":
            e.debugForce(phase: .focus, state: .running(endsAt: now.addingTimeInterval(1122), total: 1500), cyclePosition: 2)
        case "break":
            e.debugForce(phase: .shortBreak, state: .running(endsAt: now.addingTimeInterval(192), total: 300), cyclePosition: 2)
        case "paused":
            e.debugForce(phase: .focus, state: .paused(remaining: 1122, total: 1500), cyclePosition: 1)
        case "done", "focusEnd":
            e.debugForce(phase: .focus, state: .awaitingChoice(ended: .focus), cyclePosition: 3)
        case "breakEnd":
            e.debugForce(phase: .shortBreak, state: .awaitingChoice(ended: .shortBreak), cyclePosition: 3)
        default:
            break
        }
        c.send(.engine(NotchEngineStatus(state: e.state, phase: e.phase)))
        switch state {
        case "idleHover", "peek": c.debugPointer(inside: true)
        case "focusEnd": c.send(.sessionReachedZero(.focus))
        case "breakEnd": c.send(.sessionReachedZero(.shortBreak))
        case "full": c.showFullPanel(firstRun: false)
        case "firstRun": c.showFullPanel(firstRun: true)
        default: break
        }
        #endif
    }
}
