import MeleteCore
import SwiftData
import SwiftUI

/// State 8: mode, time, controls, intention, tasks, Stats and Settings icons.
struct FullPanelView: View {
    let vm: NotchViewModel
    let firstRun: Bool

    var body: some View {
        let e = vm.engine
        let status = vm.status
        ExpandedFrame(topInset: vm.layout.topInset, spacing: 12) {
            if firstRun {
                Text("Melete lives here. Hover the notch any time.")
                    .font(NotchFont.smallBold).foregroundStyle(Mono.ink)
                    .frame(height: 14)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack {
                ModeControl(engine: e)
                Spacer()
                HStack(spacing: 14) {
                    HeaderIcon(systemName: "chart.bar", help: "Statistics") { vm.send(.actionDone); vm.model.openStats() }
                    HeaderIcon(systemName: "gearshape", help: "Settings") { vm.send(.actionDone); vm.model.openSettings() }
                }
            }
            HStack {
                EngineTimeline(engine: e, blinks: { if case .paused = status { return true }; return false }()) { date in
                    Text(Mono.clock(status == .idle ? e.durations.duration(of: e.phase) : e.remaining(at: date)))
                        .font(NotchFont.huge).tracking(-1.4)
                        .modifier(Blink(on: { if case .paused = status { return true }; return false }(), date: date))
                }
                Spacer()
                switch status {
                case .idle:
                    HStack(spacing: 7) {
                        IconButton(systemName: "arrow.counterclockwise", help: "Reset") {}.disabled(true).opacity(0.4)
                        Button { vm.act { $0.start($0.phase) } } label: {
                            HStack(spacing: 6) { Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)); Text("Start") }
                        }
                        .buttonStyle(PillButtonStyle(primary: true, height: 30, hPad: 16))
                        .keyboardShortcut(.defaultAction)
                    }
                case .running, .paused:
                    RunControls(engine: e)
                case let .awaiting(p):
                    ChoiceButtons(vm: vm, ended: p)
                }
            }
            IntentionField(engine: e)
            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
            HStack { Text("Tasks"); Spacer(); Text("pomodoros") }
                .font(NotchFont.small).foregroundStyle(Mono.ink2)
            TaskListView(vm: vm).padding(.top, -6)
        }
    }
}

private struct HeaderIcon: View {
    let systemName: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 13, weight: .medium)).opacity(0.8)
                .frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}

/// Focus / Short / Long. Selectable only when idle; read-only while a session runs.
struct ModeControl: View {
    let engine: TimerEngine

    var body: some View {
        let idle = engine.state == .idle
        HStack(spacing: 0) {
            ForEach([Phase.focus, .shortBreak, .longBreak], id: \.self) { p in
                let on = engine.phase == p
                Text(label(p))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(on ? Color.white.opacity(0.18) : .clear))
                    .foregroundStyle(on ? Color.white : Mono.ink2)
                    .contentShape(Capsule())
                    .onTapGesture { if idle { engine.select(p) } }
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .font(NotchFont.smallBold)
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .opacity(idle ? 1 : 0.75)
        .help(idle ? "Next session" : "Current session")
    }

    private func label(_ p: Phase) -> String {
        switch p { case .focus: "Focus"; case .shortBreak: "Short"; case .longBreak: "Long" }
    }
}

struct IntentionField: View {
    let engine: TimerEngine

    var body: some View {
        TextField("", text: Binding(get: { engine.intention ?? "" },
                                    set: { engine.intention = $0.isEmpty ? nil : $0 }),
                  prompt: Text("Intention for this session (optional)").foregroundStyle(Color.white.opacity(0.38)))
            .textFieldStyle(.plain)
            .font(NotchFont.row)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.08)))
    }
}
