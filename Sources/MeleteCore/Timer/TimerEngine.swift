import Foundation
import Observation

/// The Pomodoro state machine. Wall-clock based: a running session stores `endsAt`,
/// and one wake-up is scheduled for that moment (no 1 s tick).
///
/// Rules (docs/spec.md → "Counting rules" and "State machine"):
/// - A pomodoro counts when focus reaches 0:00. `+5 min` continues the same session (same id).
/// - Skip during focus: not counted, cycle does not move, engine goes to idle (focus next).
/// - Skip during a break: next focus starts. Skipping a long break resets the cycle.
/// - Reset: session ends uncounted, engine goes to idle, same phase next.
/// - Stop: session ends uncounted (if one runs), engine goes to idle, focus next. Cycle kept.
/// - The cycle (dots) resets when a long break ends or is skipped, and on the first start of a new day.
@MainActor
@Observable
public final class TimerEngine {
    // MARK: Public state
    public private(set) var phase: Phase = .focus
    public private(set) var state: TimerState = .idle
    /// Counted focus sessions in the current cycle, 0...cycleLength.
    public private(set) var cyclePosition: Int = 0
    /// New durations apply to the next session. A smaller cycleLength applies now.
    public var durations: TimerDurations {
        didSet { cyclePosition = min(cyclePosition, durations.cycleLength); persistCycle() }
    }
    public var currentTaskID: UUID?
    public var intention: String?

    // MARK: Events
    /// A session reached 0:00 (play the chime, open the panel).
    @ObservationIgnored public var onPhaseEnded: ((Phase) -> Void)?
    /// Any session ended (log it).
    @ObservationIgnored public var onSessionEnded: ((SessionSummary) -> Void)?

    // MARK: Private
    @ObservationIgnored private let time: TimeSource
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var session: Current?
    /// The focus session that just completed; kept so "+5 min" can continue it.
    @ObservationIgnored private var lastCompleted: Current?
    @ObservationIgnored private var cycleDay: Date?

    private struct Current {
        var id: UUID
        var phase: Phase
        var startedAt: Date
        var planned: TimeInterval
        /// Seconds added by "+5 min" choices. > 0 means this run is an extension.
        var extra: TimeInterval = 0
        var isExtension: Bool { extra > 0 }
        var taskID: UUID?
        var intention: String?
    }

    private enum Key {
        static let position = "engine.cyclePosition"
        static let day = "engine.cycleDay"
    }

    public init(durations: TimerDurations = TimerDurations(),
                timeSource: TimeSource = SystemTimeSource(),
                defaults: UserDefaults = .standard) {
        self.durations = durations
        self.time = timeSource
        self.defaults = defaults
        self.cyclePosition = min(defaults.integer(forKey: Key.position), durations.cycleLength)
        self.cycleDay = defaults.object(forKey: Key.day) as? Date
    }

    // MARK: Reads

    public func remaining(at date: Date) -> TimeInterval {
        switch state {
        case .idle: durations.duration(of: phase)
        case let .running(endsAt, _): max(0, endsAt.timeIntervalSince(date))
        case let .paused(remaining, _): remaining
        case .awaitingChoice: 0
        }
    }

    /// 0...1
    public func progress(at date: Date) -> Double {
        switch state {
        case .idle: 0
        case .awaitingChoice: 1
        case let .running(_, total), let .paused(_, total):
            total > 0 ? min(1, max(0, 1 - remaining(at: date) / total)) : 1
        }
    }

    /// The break that follows the current cycle position.
    public var nextBreak: Phase { cyclePosition >= durations.cycleLength ? .longBreak : .shortBreak }

    // MARK: Actions

    public func startFocus() { start(.focus) }

    /// Starts a new session of `phase`. A session that runs now ends as `.reset` (not counted).
    public func start(_ phase: Phase) {
        endActiveSession(as: .reset)
        lastCompleted = nil
        rollDayIfNeeded()
        let now = time.now
        let total = durations.duration(of: phase)
        self.phase = phase
        session = Current(id: UUID(), phase: phase, startedAt: now, planned: total,
                          taskID: phase == .focus ? currentTaskID : nil,
                          intention: phase == .focus ? intention : nil)
        state = .running(endsAt: now.addingTimeInterval(total), total: total)
        scheduleWake()
    }

    /// Idle only: choose which phase starts next (Focus / Short / Long control).
    public func select(_ phase: Phase) {
        guard case .idle = state else { return }
        self.phase = phase
    }

    public func pause() {
        guard case let .running(endsAt, total) = state else { return }
        cancelWake()
        state = .paused(remaining: max(0, endsAt.timeIntervalSince(time.now)), total: total)
    }

    public func resume() {
        guard case let .paused(remaining, total) = state else { return }
        state = .running(endsAt: time.now.addingTimeInterval(remaining), total: total)
        scheduleWake()
    }

    public func togglePause() {
        if case .running = state { pause() } else if case .paused = state { resume() }
    }

    public func skip() {
        switch state {
        case .running, .paused:
            if phase == .focus {
                endActiveSession(as: .skipped)
                phase = .focus
                state = .idle
            } else {
                endActiveSession(as: .skipped)
                if phase == .longBreak { cyclePosition = 0; persistCycle() }
                start(.focus)
            }
        case .awaitingChoice(ended: .focus):
            skipBreak()
        case .awaitingChoice, .idle:
            break
        }
    }

    public func reset() {
        guard isActive else { return }
        endActiveSession(as: .reset)
        state = .idle
    }

    /// Only after focus reached 0:00 ("+5 min" choice). Continues the same session.
    public func extendFiveMinutes() {
        guard case .awaitingChoice(ended: .focus) = state, var s = lastCompleted else { return }
        s.extra += 5 * 60
        session = s
        lastCompleted = nil
        phase = .focus
        state = .running(endsAt: time.now.addingTimeInterval(5 * 60), total: 5 * 60)
        scheduleWake()
    }

    /// After focus: start the short or long break the cycle needs.
    public func startBreak() {
        guard case .awaitingChoice(ended: .focus) = state else { return }
        start(nextBreak)
    }

    /// After focus: skip the break. The pomodoro is already counted.
    public func skipBreak() {
        guard case .awaitingChoice(ended: .focus) = state else { return }
        if cyclePosition >= durations.cycleLength { cyclePosition = 0; persistCycle() }
        start(.focus)
    }

    public func stop() {
        endActiveSession(as: .stopped)
        lastCompleted = nil
        phase = .focus
        state = .idle
    }

    /// Check the wall clock now. The app calls this on wake from sleep; tests call it after moving time.
    public func reconcile() {
        guard case let .running(endsAt, _) = state, time.now >= endsAt, var s = session else { return }
        if s.phase == .focus && !s.isExtension {
            s.taskID = currentTaskID
            s.intention = intention
        }
        cancelWake()
        let summary = SessionSummary(
            id: s.id, phase: s.phase, startedAt: s.startedAt, endedAt: endsAt,
            plannedDuration: s.planned, actualDuration: s.planned + s.extra,
            end: .completed, counted: s.phase == .focus, taskID: s.taskID, intention: s.intention,
            isUpdate: s.isExtension)
        if s.phase == .focus {
            if !s.isExtension { cyclePosition = min(cyclePosition + 1, durations.cycleLength) }
            lastCompleted = s
        }
        if s.phase == .longBreak { cyclePosition = 0 }
        persistCycle()
        session = nil
        state = .awaitingChoice(ended: s.phase)
        onSessionEnded?(summary)
        onPhaseEnded?(s.phase)
    }

    // MARK: Debug

    #if DEBUG
    /// Debug builds only: force any state so the UI can be checked without waiting.
    public func debugForce(phase: Phase, state: TimerState, cyclePosition: Int) {
        cancelWake()
        self.phase = phase
        self.state = state
        self.cyclePosition = cyclePosition
        if case .running = state { scheduleWake() }
    }
    #endif

    // MARK: Helpers

    private var isActive: Bool {
        switch state {
        case .running, .paused: true
        default: false
        }
    }

    private func endActiveSession(as end: SessionEnd) {
        guard isActive, let s = session else { return }
        cancelWake()
        let now = time.now
        let remaining = self.remaining(at: now)
        let actual = s.planned + s.extra - remaining
        // An extension that is cut short still keeps the pomodoro that was already counted.
        let summary = SessionSummary(
            id: s.id, phase: s.phase, startedAt: s.startedAt, endedAt: now, plannedDuration: s.planned,
            actualDuration: max(0, actual), end: s.isExtension ? .completed : end,
            counted: s.isExtension, taskID: s.taskID, intention: s.intention, isUpdate: s.isExtension)
        session = nil
        onSessionEnded?(summary)
    }

    private func rollDayIfNeeded() {
        let today = Calendar.current.startOfDay(for: time.now)
        if cycleDay != today {
            cyclePosition = 0
            cycleDay = today
            persistCycle()
        }
    }

    private func persistCycle() {
        defaults.set(cyclePosition, forKey: Key.position)
        if let cycleDay { defaults.set(cycleDay, forKey: Key.day) }
    }

    private func scheduleWake() {
        cancelWake()
        guard case let .running(endsAt, _) = state else { return }
        let delay = max(0, endsAt.timeIntervalSince(time.now))
        wakeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    private func cancelWake() {
        wakeTask?.cancel()
        wakeTask = nil
    }
}
