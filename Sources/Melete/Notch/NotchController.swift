import AppKit
import MeleteCore
import SwiftUI

/// Notch shell entry point. OWNER: opus. Keep these three signatures.
///
/// One transparent panel sits at the top center of one screen: the pointer's screen if it is not fullscreen,
/// else the home screen (`NotchScreenPicker`, rules A/B). SwiftUI draws the black shape
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
    /// Cached per screen on space / screen / app changes, so a pointer move does only lookups.
    private var layouts: [CGDirectDisplayID: NotchLayout] = [:]
    private var screenInfos: [NotchScreenInfo] = []
    private var picker = NotchScreenPicker()
    /// True during the session-end move (rule C): a nested re-check must not send the panel home again.
    private var holdScreen = false
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
        refreshScreens()
        let screen = pickScreen(at: NSEvent.mouseLocation, pinned: false).flatMap(screen(withID:))
            ?? NSScreen.main ?? NSScreen.screens[0]
        screenID = screen.displayID
        let layout = layoutFor(screen)
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
        // Opens on the pointer's screen, or on the home screen when the pointer's screen is fullscreen.
        if vm.machine.expansion != .full, let s = pickScreen(at: NSEvent.mouseLocation, pinned: false).flatMap(screen(withID:)) {
            moveTo(s)
        }
        send(.openFull(firstRun: firstRun))
    }

    // MARK: Events

    fileprivate func send(_ event: NotchEvent) {
        let before = vm.machine.presentation
        let wasPinnedToScreen = !vm.machine.followsPointerScreen
        let effects = vm.machine.handle(event)
        for fx in effects { run(fx) }
        let after = vm.machine.presentation
        if before != after { NotchLog.log("\(event) → \(after)") }
        updatePanel()
        // An expansion closed: the pointer may already be on another screen. Follow it now, not on the next move.
        // (The nested `.screen` send starts unpinned, so this does not recurse.)
        if wasPinnedToScreen && vm.machine.followsPointerScreen { recheckPointer() }
    }

    /// Re-read the real pointer location: screen, hit rect membership, mouse pass-through.
    private func recheckPointer() { pointerMoved(NSEvent.mouseLocation) }

    private func run(_ fx: NotchEffect) {
        switch fx {
        case let .schedule(kind, delay):
            timers[kind]?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.timers[kind] = nil
                // The deadline depends on whether the pointer is inside the shape. A pointer that has not
                // moved since the shape grew has no fresh move event: read it now.
                if kind == .autoClose { self.recheckPointer() }
                self.send(.timerFired(kind))
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
            // End the field editor (its text is already in the bindings), then save the drafts before
            // the full panel view goes away.
            panel.makeFirstResponder(nil)
            vm.commitTextEdits()
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
        if !holdScreen, debug.screenPin == nil, let id = pickScreen(at: p, pinned: !vm.machine.followsPointerScreen),
           id != screenID, let s = screen(withID: id) {
            moveTo(s)
        }
        let inPanel: CGPoint? = vm.machine.expansion == .full && contains(panel.frame, p)
            ? CGPoint(x: p.x - panel.frame.minX, y: panel.frame.maxY - p.y) : nil
        if inPanel != vm.pointerInPanel { vm.pointerInPanel = inPanel }
        let inside = contains(hitRect(), p)
        if inside != vm.machine.pointerInside {
            NotchLog.log("pointer inside=\(inside) at \(p)")
            send(.pointer(inside: inside))
        } else {
            updatePanel()
        }
    }

    /// Rule C: the choices open on the pointer's screen, also when it is fullscreen (the user looks there).
    /// After the choice the picker brings the panel back to the home screen.
    /// A full panel stays where it is (the user works in it; it is key).
    private func sessionReachedZero(_ phase: Phase) {
        // `moveTo` sends `.screen`, which closes a hover in its exit delay; the re-check after it would
        // then pick the home screen before the choices pin the panel.
        holdScreen = true
        defer { holdScreen = false }
        refreshScreens()
        if vm.machine.expansion != .full, debug.screenPin == nil, let s = NSScreen.containing(NSEvent.mouseLocation) {
            moveTo(s)
        }
        // The panel may already be on that screen: the machine needs the fresh fullscreen flag for the deadline.
        syncFullscreenFlag()
        send(.sessionReachedZero(phase))
        // The choices shape is larger than the collapsed one: the pointer may be inside it without a move.
        recheckPointer()
    }

    // MARK: Screens

    /// The screen the panel should be on (rules A/B). `pinned`: the machine keeps the panel where it is.
    /// Per pointer move: dictionary / array lookups only, no fullscreen check.
    private func pickScreen(at p: NSPoint, pinned: Bool) -> CGDirectDisplayID? {
        if let pin = debug.screenPin { return pin()?.displayID }
        let ptr = NSScreen.containing(p)
        var inHotZone = false
        if let ptr, isFullscreen(ptr), let l = layouts[ptr.displayID] {
            let idle = vm?.machine.status.isIdle ?? (model.engine.state == .idle)
            inHotZone = contains(l.hotZone(idle: idle), p)
        }
        return picker.target(screens: screenInfos, pointer: ptr?.displayID, pointerInHotZone: inHotZone,
                             current: screenID, pinned: pinned)
    }

    private func screen(withID id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == id }
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
        if let forced = debug.forceFullscreen { return forced(s) }
        return fullscreen[s.displayID] ?? false
    }

    /// Fullscreen flags, layouts and picker input for every screen. Space / app / screen changes only.
    private func refreshScreens() {
        let screens = NSScreen.screens
        fullscreen = [:]; layouts = [:]
        for s in screens {
            fullscreen[s.displayID] = FullscreenDetector.isFullscreen(s)
            layouts[s.displayID] = layoutFor(s)
        }
        screenInfos = screens.map {
            // Picker "fullscreen" = the notch hides here. A notched screen never hides it (black strip).
            NotchScreenInfo(id: $0.displayID, fullscreen: isFullscreen($0) && $0.safeAreaInsets.top <= 0,
                            builtIn: CGDisplayIsBuiltin($0.displayID) != 0 || $0.safeAreaInsets.top > 0)
        }
        NotchLog.log("screens " + screens.map { "\($0.localizedName) fs=\(isFullscreen($0))" }.joined(separator: ", "))
    }

    /// Tell the machine when the fullscreen flag of the panel's own screen changed (also while pinned:
    /// auto choices on a screen that becomes fullscreen lose their deadline).
    private func syncFullscreenFlag() {
        guard let vm, let id = screenID, let s = screen(withID: id) else { return }
        let fs = isFullscreen(s)
        if fs != vm.machine.fullscreen {
            NotchLog.log("fullscreen \(s.localizedName) = \(fs)")
            send(.screen(hasNotch: vm.layout.hasNotch, fullscreen: fs))
        }
    }

    /// Fullscreen is checked on space / app / screen changes only (never on mouse moves).
    /// Then re-pick the screen: the home screen may be fullscreen now, or the pointer's screen may not be.
    private func fullscreenMayHaveChanged() {
        guard vm != nil else { return }
        refreshScreens()
        syncFullscreenFlag()
        recheckPointer()
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
                self.refreshScreens()
                // The picker re-picks when the panel's (or the home) screen is gone, even while pinned.
                // `moveTo` also applies a new layout of the same screen.
                let pinned = !self.vm.machine.followsPointerScreen
                if let id = self.pickScreen(at: NSEvent.mouseLocation, pinned: pinned) ?? NSScreen.main?.displayID,
                   let s = self.screen(withID: id) {
                    self.moveTo(s)
                }
                self.syncFullscreenFlag()
                self.recheckPointer()
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
/// - MELETE_DEBUG_FULLSCREEN=builtin|external: treat only that screen as fullscreen (home-screen checks).
/// - MELETE_DEBUG_SEED=1: show sample tasks from an in-memory store (the real store is not touched).
/// - MELETE_DEBUG_SECONDS=N: every session lasts N seconds, and sessions are not logged to the store.
///   With it, the running and peek states start a real focus session (it reaches 0:00 after N seconds).
///   Side effects: the engine saves the cycle position/day to the real UserDefaults, and the chime plays.
@MainActor
private struct DebugOptions {
    var state: String?
    var screenPin: (() -> NSScreen?)?
    /// Replaces the real fullscreen check (MELETE_DEBUG_NO_FULLSCREEN, MELETE_DEBUG_FULLSCREEN).
    var forceFullscreen: ((NSScreen) -> Bool)?
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
        switch env["MELETE_DEBUG_FULLSCREEN"] {
        case "builtin": forceFullscreen = { $0.safeAreaInsets.top > 0 }
        case "external": forceFullscreen = { $0.safeAreaInsets.top == 0 }
        default: if env["MELETE_DEBUG_NO_FULLSCREEN"] == "1" { forceFullscreen = { _ in false } }
        }
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
        case "running" where shortSessions != nil, "peek" where shortSessions != nil:
            e.startFocus() // a real session of N seconds, so 0:00 really happens
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
