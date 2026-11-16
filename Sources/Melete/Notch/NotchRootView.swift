import MeleteCore
import SwiftData
import SwiftUI

/// Draws the island for the current presentation, top centered in the fixed panel.
struct NotchRootView: View {
    @Bindable var vm: NotchViewModel

    var body: some View {
        let p = vm.presentation
        let size = vm.layout.shapeSize(p)
        let flare = p == .hidden ? 0 : vm.layout.metrics.flare
        ZStack(alignment: .top) {
            NotchShape(flare: flare, radius: radius(p))
                .fill(Color.black)
                .frame(width: size.width + 2 * flare, height: size.height)
                .contentShape(NotchShape(flare: flare, radius: radius(p)))
                .onTapGesture { vm.send(.clickShape) }
            content(p)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(NotchShape(flare: 0, radius: radius(p)))
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
                .id(kind(p))
        }
        .opacity(p == .hidden ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: p)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: vm.layout)
        .foregroundStyle(Mono.ink)
        .environment(\.colorScheme, .dark)
        .modelContainer(vm.taskStore.container)
    }

    private func radius(_ p: NotchPresentation) -> CGFloat {
        switch p {
        case .hidden: 8
        case .collapsed: vm.layout.hasNotch ? 11 : 10
        case .idleHover: 18
        case .peek: 22
        case .full: 26
        case .choices: 24
        }
    }

    private func kind(_ p: NotchPresentation) -> String {
        switch p {
        case .hidden: "hidden"
        case .collapsed: "collapsed"
        case .idleHover: "idleHover"
        case .peek: "peek"
        case .full: "full"
        case let .choices(ph): "choices-\(ph.rawValue)"
        }
    }

    @ViewBuilder private func content(_ p: NotchPresentation) -> some View {
        switch p {
        case .hidden: Color.clear
        case .collapsed: CollapsedView(vm: vm)
        case .idleHover: IdleHoverView(vm: vm)
        case .peek: PeekView(vm: vm)
        case let .full(firstRun): FullPanelView(vm: vm, firstRun: firstRun)
        case let .choices(ended): ChoicesView(vm: vm, ended: ended)
        }
    }
}

/// Redraws once per second while a countdown shows, every 0.8 s while something blinks, else never.
struct EngineTimeline<Content: View>: View {
    let engine: TimerEngine
    var blinks = false
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        TimelineView(schedule) { ctx in content(ctx.date) }
    }

    private var schedule: AlignedSchedule {
        if case let .running(endsAt, _) = engine.state { return AlignedSchedule(anchor: endsAt, interval: 1) }
        return AlignedSchedule(anchor: Date(timeIntervalSinceReferenceDate: 0), interval: blinks ? 0.8 : nil)
    }
}
