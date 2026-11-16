import AppKit
import SwiftUI
import MeleteCore

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        #if DEBUG
        if ProcessInfo.processInfo.environment["MELETE_OPEN"] == "settings" {
            DispatchQueue.main.async { [weak self] in self?.show() }
        }
        #endif
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Melete Settings"
            WindowStyle.configure(w)
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    let model: AppModel
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var loginError: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var settings = model.settings
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                section("Timer")
                settingsRow("Focus") {
                    minuteControl("Focus", value: $settings.focusMinutes)
                }
                settingsRow("Short break") {
                    minuteControl("Short break", value: $settings.shortBreakMinutes)
                }
                settingsRow("Long break") {
                    minuteControl("Long break", value: $settings.longBreakMinutes)
                }
                settingsRow("Long break after") {
                    numberControl("Long break after", value: $settings.cycleLength, range: 2...6, unit: "sessions")
                }
                section("Session end").padding(.top, 16)
                settingsRow("Sound") {
                    Picker("Sound", selection: $settings.chimeName) {
                        ForEach(MeleteSettings.chimeChoices, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 120)
                    .onChange(of: settings.chimeName) { _, name in
                        model.chime.play(name: name, volume: settings.chimeVolume)
                    }
                    Image(systemName: "speaker.wave.1").font(.system(size: 11)).foregroundStyle(Mono.ink2)
                    Slider(value: $settings.chimeVolume, in: 0...1)
                        .frame(width: 110).accessibilityLabel("Chime volume")
                }
                section("General").padding(.top, 16)
                settingsRow("Launch at login") {
                    Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: setLoginEnabled))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                if let loginError {
                    Text(loginError).font(.system(size: 11)).foregroundStyle(Mono.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                        .accessibilityLabel("Launch at login error: \(loginError)")
                }
            }
            .padding(18)
            Spacer(minLength: 0)
            HStack {
                Text("Melete 0.1 · GPL-3.0").font(.system(size: 11)).foregroundStyle(Mono.ink2)
                Spacer()
                Button("Quit Melete") { model.quit() }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(.white.opacity(0.025))
            .overlay(alignment: .top) { WindowStyle.separator.frame(height: 1) }
        }
        .frame(minHeight: 430)
        .background(WindowStyle.background)
        .foregroundStyle(Mono.ink)
        .preferredColorScheme(.dark)
        .tint(.white)
        .onAppear { loginEnabled = LoginItem.isEnabled }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { loginEnabled = LoginItem.isEnabled }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 11, weight: .semibold))
            .tracking(0.7).foregroundStyle(Mono.ink2).padding(.bottom, 6)
    }

    private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(Mono.ink2).frame(width: 142, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .frame(minHeight: 37)
        .overlay(alignment: .top) { WindowStyle.separator.frame(height: 1) }
    }

    private func minuteControl(_ title: String, value: Binding<Int>) -> some View {
        numberControl(title, value: value, range: 1...240, unit: "min")
    }

    private func numberControl(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        HStack(spacing: 0) {
            Text("\(value.wrappedValue) \(unit)")
                .monospacedDigit().frame(minWidth: 80).padding(.horizontal, 10)
            adjustmentButton("minus", title: "Decrease \(title)", disabled: value.wrappedValue <= range.lowerBound) {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
            }
            adjustmentButton("plus", title: "Increase \(title)", disabled: value.wrappedValue >= range.upperBound) {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
            }
        }
        .frame(height: 25)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
    }

    private func adjustmentButton(_ symbol: String, title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                .frame(width: 26, height: 25).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(disabled)
        .overlay(alignment: .leading) { WindowStyle.separator.frame(width: 1) }
        .accessibilityLabel(title).help(title)
    }

    private func setLoginEnabled(_ enabled: Bool) {
        loginError = nil
        do {
            try LoginItem.setEnabled(enabled)
            loginEnabled = LoginItem.isEnabled
            if enabled && !loginEnabled {
                loginError = "Allow Melete in System Settings → General → Login Items to finish enabling launch at login."
            }
        } catch {
            loginEnabled = LoginItem.isEnabled
            loginError = "Could not change launch at login. \(error.localizedDescription)"
        }
    }
}
