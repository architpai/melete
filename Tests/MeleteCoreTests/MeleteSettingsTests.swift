import Foundation
import Testing
@testable import MeleteCore

@MainActor
struct MeleteSettingsTests {
    private let suite = TestDefaults()

    @Test func defaults() {
        let settings = MeleteSettings(defaults: suite.defaults)
        #expect(settings.focusMinutes == 25)
        #expect(settings.shortBreakMinutes == 5)
        #expect(settings.longBreakMinutes == 15)
        #expect(settings.cycleLength == 4)
        #expect(settings.chimeName == "Glass")
        #expect(settings.chimeVolume == 0.7)
        #expect(!settings.hasCompletedFirstRun)
    }

    @Test func cycleLengthClampsOnLoadAndAssignment() {
        suite.defaults.set(9, forKey: "settings.cycle")
        let settings = MeleteSettings(defaults: suite.defaults)
        #expect(settings.cycleLength == 6)
        settings.cycleLength = 1
        #expect(settings.cycleLength == 2)
        #expect(MeleteSettings(defaults: suite.defaults).cycleLength == 2)
        settings.cycleLength = 9
        #expect(settings.cycleLength == 6)
        #expect(MeleteSettings(defaults: suite.defaults).cycleLength == 6)
        suite.defaults.set(1, forKey: "settings.cycle")
        #expect(MeleteSettings(defaults: suite.defaults).cycleLength == 2)
    }

    @Test func persistenceRoundTrip() {
        let settings = MeleteSettings(defaults: suite.defaults)
        settings.focusMinutes = 40
        settings.shortBreakMinutes = 8
        settings.longBreakMinutes = 20
        settings.cycleLength = 6
        settings.chimeName = "Purr"
        settings.chimeVolume = 0.25
        settings.hasCompletedFirstRun = true
        let restored = MeleteSettings(defaults: suite.defaults)
        #expect(restored.focusMinutes == 40)
        #expect(restored.shortBreakMinutes == 8)
        #expect(restored.longBreakMinutes == 20)
        #expect(restored.cycleLength == 6)
        #expect(restored.chimeName == "Purr")
        #expect(restored.chimeVolume == 0.25)
        #expect(restored.hasCompletedFirstRun)
    }

    @Test func durationsMapMinutesToSeconds() {
        let settings = MeleteSettings(defaults: suite.defaults)
        #expect(settings.durations == TimerDurations(focus: 1500, shortBreak: 300, longBreak: 900, cycleLength: 4))
        settings.focusMinutes = 45
        settings.shortBreakMinutes = 7
        settings.longBreakMinutes = 22
        settings.cycleLength = 3
        #expect(settings.durations == TimerDurations(focus: 2700, shortBreak: 420, longBreak: 1320, cycleLength: 3))
    }
}
