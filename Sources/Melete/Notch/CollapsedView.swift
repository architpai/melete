import MeleteCore
import SwiftUI

/// Running, collapsed (B), break (3), paused (4), done (4b) — and the no-notch tab (5).
struct CollapsedView: View {
    let vm: NotchViewModel

    var body: some View {
        let e = vm.engine
        let status = vm.status
        let blinks: Bool = { if case .running = status { return false }; return true }()
        EngineTimeline(engine: e, blinks: blinks) { date in
            if let c = CollapsedContent.make(status: status, cyclePosition: e.cyclePosition,
                                             cycleLength: e.durations.cycleLength,
                                             remaining: e.remaining(at: date), progress: e.progress(at: date)) {
                if vm.layout.hasNotch { wings(c, date) } else { tab(c, date) }
            }
        }
    }

    private func wings(_ c: CollapsedContent, _ date: Date) -> some View {
        let wing = vm.layout.metrics.wing
        let notchH = vm.layout.notchSize.height
        return ZStack(alignment: .top) {
            HStack(spacing: 0) {
                CycleDots(count: c.dots, filled: c.filledDots)
                    .frame(width: wing - 6).padding(.leading, 6)
                Spacer(minLength: 0)
                RightWingLabel(c: c, date: date, font: NotchFont.wing)
                    .frame(width: wing - 6).padding(.trailing, 6)
            }
            .frame(height: notchH)
            // The bar sits under the hardware notch (the notch area has no pixels).
            ProgressBar(progress: c.progress, style: c.bar, height: Mono.barHeight)
                .padding(.horizontal, 14)
                .padding(.top, notchH + 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func tab(_ c: CollapsedContent, _ date: Date) -> some View {
        ZStack(alignment: .top) {
            RightWingLabel(c: c, date: date, font: NotchFont.tab)
                .frame(maxWidth: .infinity)
                .frame(height: vm.layout.metrics.noNotchTab.height - 6)
            ProgressBar(progress: c.progress, style: c.bar, height: Mono.barHeight)
                .padding(.horizontal, 12)
                .padding(.top, vm.layout.metrics.noNotchTab.height - 4 - Mono.barHeight)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Right wing: optional icon + time (or "Done"). Same rules on the tab.
struct RightWingLabel: View {
    let c: CollapsedContent
    let date: Date
    let font: Font

    var body: some View {
        HStack(spacing: 6) {
            switch c.icon {
            case .none: EmptyView()
            case .cup: Image(systemName: "cup.and.saucer").font(.system(size: 11, weight: .semibold))
            case .pause: Image(systemName: "pause.fill").font(.system(size: 10, weight: .bold))
            }
            Group {
                switch c.label {
                case let .time(t): Text(Mono.clock(t))
                case .done: Text("Done")
                }
            }
            .modifier(Blink(on: c.blink, date: date))
        }
        .font(font)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .foregroundStyle(c.dimText ? Mono.ink2 : Mono.ink)
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        switch c.label {
        case let .time(t): (c.icon == .pause ? "Paused, " : c.icon == .cup ? "Break, " : "") + Mono.clock(t) + " left"
        case .done: "Session done"
        }
    }
}
