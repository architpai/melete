import AppKit
import SwiftUI

/// The regular windows share the mock's neutral surfaces and native window controls.
enum WindowStyle {
    static let background = Color(white: 0.12)
    static let separator = Color.white.opacity(0.08)

    static func configure(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.12, alpha: 1)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

struct WindowSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Mono.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
import MeleteCore

extension WindowStyle {
    /// Opt-in sample data stays in memory and never touches the user's store.
    @MainActor static func statsFixture() throws -> MeleteStore {
        let store = try MeleteStore(inMemory: true)
        let tasks = [store.addTask(title: "Write README"), store.addTask(title: "Review PR #12"),
                     store.addTask(title: "Plan sprint")]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        for (offset, count) in [4, 6, 3, 5, 0, 3, 6].enumerated() {
            let day = calendar.date(byAdding: .day, value: offset - 6, to: today)!
            for index in 0..<count {
                let task = index % 4 < 3 ? tasks[index % 4] : nil
                let start = day.addingTimeInterval(TimeInterval(9 * 3600 + index * 1800))
                let duration: TimeInterval = offset == 6 && index == 2 ? 1800 : 1500
                store.record(SessionSummary(id: UUID(), phase: .focus, startedAt: start,
                    endedAt: start.addingTimeInterval(duration), plannedDuration: 1500,
                    actualDuration: duration, end: .completed, counted: true, taskID: task?.id,
                    intention: task == nil ? "Fix the build" : nil, isUpdate: false))
            }
        }
        let breakStart = today.addingTimeInterval(10 * 3600 + 25 * 60)
        store.record(SessionSummary(id: UUID(), phase: .shortBreak, startedAt: breakStart,
            endedAt: breakStart.addingTimeInterval(300), plannedDuration: 300, actualDuration: 300,
            end: .completed, counted: false, taskID: nil, intention: nil, isUpdate: false))
        if ProcessInfo.processInfo.environment["MELETE_STATS_LIVE_CHECK"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                let start = Date()
                store.record(SessionSummary(id: UUID(), phase: .focus, startedAt: start,
                    endedAt: start.addingTimeInterval(60), plannedDuration: 60, actualDuration: 60,
                    end: .completed, counted: true, taskID: nil, intention: "Live refresh check", isUpdate: false))
            }
        }
        return store
    }
}
#endif
