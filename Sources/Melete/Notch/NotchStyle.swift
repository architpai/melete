import MeleteCore
import SwiftUI

/// Notch-local style helpers on top of `Mono` (sizes from docs/mocks/src/style.css).
enum NotchFont {
    static let wing = Font.system(size: 13, weight: .semibold).monospacedDigit()
    static let tab = Font.system(size: 12.5, weight: .semibold).monospacedDigit()
    static let small = Font.system(size: 11.5)
    static let smallBold = Font.system(size: 11.5, weight: .semibold)
    static let button = Font.system(size: 12.5, weight: .semibold)
    static let big = Font.system(size: 30, weight: .semibold).monospacedDigit()
    static let huge = Font.system(size: 46, weight: .light).monospacedDigit()
    static let title = Font.system(size: 16, weight: .semibold)
    static let row = Font.system(size: 12.5)
}

/// Pill button (mock `.btn`, `.btn.pri`).
struct PillButtonStyle: ButtonStyle {
    var primary = false
    var height: CGFloat = 28
    var hPad: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NotchFont.button)
            .lineLimit(1)
            .padding(.horizontal, hPad)
            .frame(height: height)
            .foregroundStyle(primary ? Color.black : Mono.ink)
            .background(Capsule().fill(primary ? Mono.ink : Mono.fill))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// Round icon button (mock `.btn.ic`, 30 pt).
struct IconButton: View {
    let systemName: String
    var help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 11, weight: .bold))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Mono.fill))
                .foregroundStyle(Mono.ink)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Dots of the cycle (mock `.dots`): 5 pt, 3 pt gap, filled = white, empty = 28 %.
struct CycleDots: View {
    let count: Int
    let filled: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(i < filled ? Color.white : Color.white.opacity(0.28)).frame(width: 5, height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(filled) of \(count) focus sessions done")
    }
}

/// Progress bar (mock `.bar`): track 18 %, fill white; dashed for breaks, 45 % when paused.
struct ProgressBar: View {
    let progress: Double
    var style: CollapsedContent.Bar = .solid
    var height: CGFloat = 2

    var body: some View {
        GeometryReader { g in
            let w = g.size.width * min(1, max(0, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                fill.frame(width: w).clipShape(Capsule())
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var fill: some View {
        let color = (style == .dim || style == .dashedDim) ? Color.white.opacity(0.45) : Color.white
        if style == .dashed || style == .dashedDim {
            Canvas { ctx, size in
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: min(4, size.width - x), height: size.height)), with: .color(color))
                    x += 7
                }
            }
        } else {
            Rectangle().fill(color)
        }
    }
}

/// A schedule that fires every `interval` seconds aligned to `anchor` (e.g. a session end), or never.
struct AlignedSchedule: TimelineSchedule {
    var anchor: Date
    var interval: TimeInterval?

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        guard let interval, interval > 0 else {
            var once = false
            return AnyIterator { defer { once = true }; return once ? nil : startDate }
        }
        let k = ((startDate.timeIntervalSince(anchor)) / interval).rounded(.down)
        var next = anchor.addingTimeInterval(k * interval)
        var first = true
        return AnyIterator {
            if first { first = false; return startDate }
            next = next.addingTimeInterval(interval)
            return next
        }
    }
}

/// Slow blink (mock `.blink`: 1.6 s, two steps, 25 % opacity). Reduced motion: steady 50 %.
struct Blink: ViewModifier {
    let on: Bool
    let date: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if !on { content }
        else if reduceMotion { content.opacity(0.5) }
        else {
            let phase = Int((date.timeIntervalSinceReferenceDate / 0.8).rounded(.down)) % 2
            content.opacity(phase == 0 ? 1 : 0.25)
        }
    }
}
