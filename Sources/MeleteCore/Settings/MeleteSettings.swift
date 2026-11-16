import Foundation
import Observation

/// User settings in UserDefaults. Launch at login is NOT here: read SMAppService status instead.
@MainActor
@Observable
public final class MeleteSettings {
    @ObservationIgnored private let defaults: UserDefaults

    public var focusMinutes: Int { didSet { save() } }
    public var shortBreakMinutes: Int { didSet { save() } }
    public var longBreakMinutes: Int { didSet { save() } }
    /// 2...6
    public var cycleLength: Int { didSet { if !(2...6).contains(cycleLength) { cycleLength = min(6, max(2, cycleLength)) }; save() } }
    /// An NSSound system sound name, e.g. "Glass".
    public var chimeName: String { didSet { save() } }
    /// 0...1
    public var chimeVolume: Double { didSet { save() } }
    public var hasCompletedFirstRun: Bool { didSet { save() } }

    public static let chimeChoices = ["Glass", "Hero", "Ping", "Purr", "Submarine", "Tink", "Blow", "Pop"]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func int(_ k: String, _ d: Int) -> Int { defaults.object(forKey: k) as? Int ?? d }
        focusMinutes = int("settings.focus", 25)
        shortBreakMinutes = int("settings.short", 5)
        longBreakMinutes = int("settings.long", 15)
        cycleLength = min(6, max(2, int("settings.cycle", 4)))
        chimeName = defaults.string(forKey: "settings.chime") ?? "Glass"
        chimeVolume = defaults.object(forKey: "settings.volume") as? Double ?? 0.7
        hasCompletedFirstRun = defaults.bool(forKey: "settings.firstRunDone")
    }

    public var durations: TimerDurations {
        TimerDurations(focus: TimeInterval(focusMinutes * 60), shortBreak: TimeInterval(shortBreakMinutes * 60),
                       longBreak: TimeInterval(longBreakMinutes * 60), cycleLength: cycleLength)
    }

    private func save() {
        defaults.set(focusMinutes, forKey: "settings.focus")
        defaults.set(shortBreakMinutes, forKey: "settings.short")
        defaults.set(longBreakMinutes, forKey: "settings.long")
        defaults.set(cycleLength, forKey: "settings.cycle")
        defaults.set(chimeName, forKey: "settings.chime")
        defaults.set(chimeVolume, forKey: "settings.volume")
        defaults.set(hasCompletedFirstRun, forKey: "settings.firstRunDone")
    }
}
