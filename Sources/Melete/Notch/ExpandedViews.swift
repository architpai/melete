import MeleteCore
import SwiftData
import SwiftUI

/// Content inset of the expanded shapes (mock `.xc`: 18 at the sides, 14 at the bottom, 8 under the notch).
struct ExpandedFrame<Content: View>: View {
    let topInset: CGFloat
    var spacing: CGFloat = 10
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing, content: content)
            .padding(.top, topInset + 8)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// State 2: Start button + duration.
struct IdleHoverView: View {
    let vm: NotchViewModel

    var body: some View {
        let e = vm.engine
        // The button sits fully below the notch (the mock puts its top 6 pt inside the camera housing).
        VStack(spacing: 0) {
            Color.clear.frame(height: vm.layout.topInset + 4)
            HStack(spacing: 10) {
                Button { vm.act { $0.start($0.phase) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                        Text(e.phase == .focus ? "Start focus" : "Start \(NotchFormat.phaseName(e.phase).lowercased())")
                    }
                }
                .buttonStyle(PillButtonStyle(primary: true))
                Text(Mono.clock(e.durations.duration(of: e.phase)))
                    .font(NotchFont.small).monospacedDigit().foregroundStyle(Mono.ink2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            Spacer(minLength: 0)
        }
    }
}

/// Pause / resume, skip, reset (peek and full panel).
struct RunControls: View {
    let engine: TimerEngine

    var body: some View {
        HStack(spacing: 7) {
            if case .paused = engine.state {
                IconButton(systemName: "play.fill", help: "Resume") { engine.resume() }
            } else {
                IconButton(systemName: "pause.fill", help: "Pause") { engine.pause() }
            }
            IconButton(systemName: "forward.end.fill", help: "Skip") { engine.skip() }
            IconButton(systemName: "arrow.counterclockwise", help: "Reset") { engine.reset() }
        }
    }
}

/// State 7: current task, large time, controls, bar, dots.
struct PeekView: View {
    let vm: NotchViewModel
    @Query(sort: [SortDescriptor(\TaskItem.sortIndex), SortDescriptor(\TaskItem.createdAt)]) private var tasks: [TaskItem]

    var body: some View {
        let e = vm.engine
        let status = vm.status
        let paused: Bool = { if case .paused = status { return true }; return false }()
        let task = e.currentTaskID.flatMap { id in tasks.first { $0.id == id } }
        ExpandedFrame(topInset: vm.layout.topInset) {
            EngineTimeline(engine: e, blinks: paused) { date in
                VStack(spacing: 10) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(PeekCopy.subtitle(phase: e.phase, taskTitle: task?.title, done: task?.completedPomodoros ?? 0,
                                                   planned: task?.plannedPomodoros ?? 0, intention: e.intention))
                                .font(NotchFont.small).foregroundStyle(Mono.ink2).lineLimit(1)
                            Text(Mono.clock(e.remaining(at: date))).font(NotchFont.big).tracking(-0.6)
                                .foregroundStyle(e.phase.isBreak ? Mono.ink2 : Mono.ink)
                                .modifier(Blink(on: paused, date: date))
                        }
                        Spacer(minLength: 8)
                        RunControls(engine: e)
                    }
                    HStack(spacing: 10) {
                        ProgressBar(progress: e.progress(at: date),
                                    style: e.phase.isBreak ? (paused ? .dashedDim : .dashed) : (paused ? .dim : .solid),
                                    height: 3)
                        CycleDots(count: e.durations.cycleLength, filled: e.cyclePosition)
                        Text("to long break").font(NotchFont.small).foregroundStyle(Mono.ink2)
                    }
                }
            }
        }
    }
}

/// Session-end buttons (9 / 10). Also used in the full panel while a choice waits.
struct ChoiceButtons: View {
    let vm: NotchViewModel
    let ended: Phase

    var body: some View {
        let e = vm.engine
        HStack(spacing: 6) {
            if ended == .focus {
                Button(copy.primary) { vm.act { $0.startBreak() } }.buttonStyle(PillButtonStyle(primary: true))
                Button("+5 min") { vm.act { $0.extendFiveMinutes() } }.buttonStyle(PillButtonStyle())
                Button("Skip") { vm.act { $0.skipBreak() } }.buttonStyle(PillButtonStyle())
            } else {
                Button(copy.primary) { vm.act { $0.startFocus() } }.buttonStyle(PillButtonStyle(primary: true))
                Button("Stop") { vm.act { $0.stop() } }.buttonStyle(PillButtonStyle())
            }
        }
        .id(e.cyclePosition)
    }

    var copy: SessionEndCopy {
        let e = vm.engine
        return ended == .focus
            ? SessionEndCopy.focusEnded(who: vm.who, cyclePosition: e.cyclePosition, cycleLength: e.durations.cycleLength,
                                        nextBreak: e.nextBreak, breakDuration: e.durations.duration(of: e.nextBreak))
            : SessionEndCopy.breakEnded(who: vm.who, focusDuration: e.durations.focus)
    }
}

/// States 9 and 10.
struct ChoicesView: View {
    let vm: NotchViewModel
    let ended: Phase

    var body: some View {
        let e = vm.engine
        let copy = ChoiceButtons(vm: vm, ended: ended).copy
        ExpandedFrame(topInset: vm.layout.topInset, spacing: 8) {
            Text(copy.title).font(NotchFont.title)
            HStack(spacing: 8) {
                Text(copy.detail).lineLimit(1)
                if let note = copy.cycleNote {
                    Spacer(minLength: 4)
                    CycleDots(count: e.durations.cycleLength, filled: e.cyclePosition)
                    Text(note).lineLimit(1)
                }
            }
            .font(NotchFont.small).foregroundStyle(Mono.ink2)
            ChoiceButtons(vm: vm, ended: ended).padding(.top, 4)
        }
    }
}
