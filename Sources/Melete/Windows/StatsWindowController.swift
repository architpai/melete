import AppKit
import Charts
import SwiftData
import SwiftUI
import MeleteCore

@MainActor
final class StatsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
        #if DEBUG
        if ProcessInfo.processInfo.environment["MELETE_OPEN"] == "stats" {
            DispatchQueue.main.async { [weak self] in self?.show() }
        }
        #endif
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Melete Stats"
            w.minSize = NSSize(width: 620, height: 460)
            WindowStyle.configure(w)
            w.delegate = self
            w.contentView = nil
            w.center()
            window = w
        }
        if let w = window, w.contentView == nil {
            var store = model.store
            #if DEBUG
            if ProcessInfo.processInfo.environment["MELETE_STATS_FIXTURE"] == "1" {
                store = (try? WindowStyle.statsFixture()) ?? store
            }
            #endif
            w.contentView = NSHostingView(rootView: StatsView().modelContainer(store.container))
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        #if DEBUG
        if ProcessInfo.processInfo.environment["MELETE_STATS_REOPEN_CHECK"] == "1", !checkedReopen {
            checkedReopen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak previousContent = window?.contentView] in
                self?.window?.close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak previousContent] in
                    NSLog("Stats close check: content cleared = %@, hosting view released = %@",
                          self?.window?.contentView == nil ? "yes" : "no", previousContent == nil ? "yes" : "no")
                    self?.show()
                    NSLog("Stats reopen check: content rebuilt = %@", self?.window?.contentView != nil ? "yes" : "no")
                }
            }
        }
        #endif
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window?.toolbar = nil
    }

    #if DEBUG
    private var checkedReopen = false
    #endif
}

private struct StatsView: View {
    @Query(sort: \SessionRecord.startedAt, order: .reverse) private var records: [SessionRecord]
    @State private var range: StatsRange = {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["MELETE_STATS_RANGE"], let range = StatsRange(rawValue: value) {
            return range
        }
        #endif
        return .week
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let stats = StatsCalculator(sessions: records.map(\.snapshot), now: context.date)
            let todaySessions = stats.todaySessions
            let todayFocus = todaySessions.filter { $0.phase == .focus }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        tile("Today", value: "\(todayFocus.filter(\.counted).count)", unit: "pomodoros")
                        tile("Focus today", value: WindowStyle.duration(todayFocus.reduce(0) { $0 + $1.actualDuration }))
                        tile("Streak", value: "\(stats.streakDays)", unit: stats.streakDays == 1 ? "day" : "days")
                        tile("This week", value: "\(stats.last7DaysPomodoros)", unit: "pomodoros")
                    }
                    VStack(spacing: 12) {
                        WindowSectionTitle(title: range == .year ? "Pomodoros per month" : "Pomodoros per day")
                        pomodoroChart(stats.perDay(range), now: context.date)
                    }
                    VStack(spacing: 8) {
                        WindowSectionTitle(title: "By task")
                        let tasks = stats.perTask(range)
                        if tasks.isEmpty {
                            emptyMessage("Your focus sessions will appear here.")
                        } else {
                            ForEach(tasks) { task in
                                taskRow(task, maximum: tasks.map(\.pomodoros).max() ?? 1)
                            }
                        }
                    }
                    VStack(spacing: 0) {
                        WindowSectionTitle(title: "Today").padding(.bottom, 8)
                        if todaySessions.isEmpty {
                            emptyMessage("No sessions today. A fresh start awaits.")
                        } else {
                            ForEach(todaySessions) { session in
                                sessionRow(session)
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .background(WindowStyle.background)
        .foregroundStyle(Mono.ink)
        .preferredColorScheme(.dark)
        .tint(.white)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Range", selection: $range) {
                    ForEach(StatsRange.allCases, id: \.self) { range in
                        Text(range.rawValue.capitalized).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .accessibilityLabel("Statistics range")
            }
        }
    }

    private func tile(_ label: String, value: String, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11)).foregroundStyle(Mono.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                if let unit { Text(unit).font(.system(size: 11)).foregroundStyle(Mono.ink2) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func pomodoroChart(_ buckets: [DayCount], now: Date) -> some View {
        let calendar = Calendar.current
        let labelIndices = Array(Set(stride(from: 0, to: buckets.count, by: range == .month ? 5 : 1))
            .union([buckets.count - 1])).sorted()
        return Chart(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
            let current = calendar.isDate(bucket.date, equalTo: now, toGranularity: range == .year ? .month : .day)
            BarMark(x: .value("Date", String(index)), y: .value("Pomodoros", bucket.pomodoros), width: .ratio(0.62))
                .foregroundStyle(current ? Mono.ink : Color.white.opacity(0.35))
                .cornerRadius(3)
                .annotation(position: .top, spacing: 4) {
                    if range != .month || bucket.pomodoros > 0 {
                        Text("\(bucket.pomodoros)").font(.system(size: 10)).foregroundStyle(Mono.ink2).fixedSize()
                    }
                }
                .accessibilityLabel(bucket.date.formatted(date: .abbreviated, time: .omitted))
                .accessibilityValue("\(bucket.pomodoros) pomodoros")
        }
        .chartXScale(domain: buckets.indices.map(String.init), range: .plotDimension(padding: range == .month ? 18 : 0))
        .chartYScale(domain: 0...max(1, Double(buckets.map(\.pomodoros).max() ?? 0) * 1.2))
        .chartPlotStyle { plot in
            plot.overlay(alignment: .bottom) { WindowStyle.separator.frame(height: 1) }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: labelIndices.map(String.init)) { value in
                AxisValueLabel {
                    if let label = value.as(String.self), let index = Int(label), buckets.indices.contains(index) {
                        Text(bucketLabel(buckets[index].date, now: now))
                            .font(.system(size: 10)).foregroundStyle(Mono.ink2).fixedSize()
                    }
                }
            }
        }
        .frame(height: 160)
    }

    private func bucketLabel(_ date: Date, now: Date) -> String {
        if range != .year && Calendar.current.isDate(date, inSameDayAs: now) { return "Today" }
        switch range {
        case .week: return date.formatted(.dateTime.weekday(.abbreviated))
        case .month: return date.formatted(.dateTime.month(.abbreviated).day())
        case .year: return date.formatted(.dateTime.month(.abbreviated))
        }
    }

    private func taskRow(_ task: TaskStat, maximum: Int) -> some View {
        HStack(spacing: 12) {
            Text(task.title)
                .foregroundStyle(task.taskID == nil ? Mono.ink2 : Mono.ink)
                .lineLimit(1).help(task.title)
                .frame(width: 150, alignment: .leading)
            GeometryReader { proxy in
                Capsule().fill(.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Mono.ink)
                            .frame(width: proxy.size.width * CGFloat(task.pomodoros) / CGFloat(max(1, maximum)))
                    }
            }
            .frame(height: 6)
            Text("\(task.pomodoros) · \(WindowStyle.duration(task.focusSeconds))")
                .foregroundStyle(Mono.ink2).monospacedDigit()
                .frame(width: 112, alignment: .trailing)
        }
        .font(.system(size: 12))
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func sessionRow(_ session: SessionSnapshot) -> some View {
        HStack(spacing: 12) {
            Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                .foregroundStyle(Mono.ink2).monospacedDigit()
                .frame(width: 72, alignment: .leading)
            Text(sessionTitle(session))
                .foregroundStyle(session.taskTitle == nil ? Mono.ink2 : Mono.ink)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                .help(sessionTitle(session))
            Text(sessionDetail(session)).foregroundStyle(Mono.ink2).monospacedDigit()
        }
        .font(.system(size: 12))
        .padding(.vertical, 8)
        .overlay(alignment: .top) { WindowStyle.separator.frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func sessionTitle(_ session: SessionSnapshot) -> String {
        if session.phase == .shortBreak { return "Short break" }
        if session.phase == .longBreak { return "Long break" }
        if let title = session.taskTitle { return title }
        if let intention = session.intention, !intention.isEmpty { return "“\(intention)”" }
        return "Focus"
    }

    private func sessionDetail(_ session: SessionSnapshot) -> String {
        var detail = (session.phase == .focus ? "Focus " : "") + Mono.clock(session.actualDuration)
        if session.end != .completed { detail += " · \(session.end.rawValue)" }
        if session.counted, session.actualDuration > session.plannedDuration {
            let extra = session.actualDuration - session.plannedDuration
            let label = extra.truncatingRemainder(dividingBy: 60) == 0 ? "\(Int(extra / 60))" : Mono.clock(extra)
            detail += " (+\(label))"
        }
        return detail
    }

    private func emptyMessage(_ message: String) -> some View {
        Text(message).font(.system(size: 12)).foregroundStyle(Mono.ink3)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
    }
}
