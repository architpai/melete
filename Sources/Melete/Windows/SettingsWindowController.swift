import AppKit
import SwiftUI
import MeleteCore
import Observation

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private let login = SettingsLoginState()

    init(model: AppModel) {
        self.model = model
        super.init()
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
            w.delegate = self
            w.contentView = NSHostingView(rootView: SettingsView(model: model, login: login) { [weak self] in
                self?.resizeForLoginMessage()
            })
            w.center()
            window = w
        }
        refreshLogin()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) { refreshLogin() }

    private func refreshLogin() {
        login.refresh()
        resizeForLoginMessage()
    }

    private func resizeForLoginMessage() {
        window?.setContentSize(NSSize(width: 520, height: login.hasMessage ? 490 : 430))
    }
}

@MainActor
@Observable
private final class SettingsLoginState {
    private(set) var enabled = false
    private(set) var pending = false
    private(set) var error: String?
    var hasMessage: Bool { pending || error != nil }

    func refresh() {
        let status = LoginItem.status
        enabled = status == .enabled || status == .requiresApproval
        pending = status == .requiresApproval
        if status == .enabled { error = nil }
        #if DEBUG
        if ProcessInfo.processInfo.environment["MELETE_DEBUG_LOGIN"] == "error" {
            error = "Could not change launch at login. The operation couldn’t be completed. Try again in System Settings → General → Login Items."
        }
        #endif
    }

    func setEnabled(_ enabled: Bool) {
        error = nil
        do {
            try LoginItem.setEnabled(enabled)
            refresh()
        } catch {
            refresh()
            self.error = "Could not change launch at login. \(error.localizedDescription)"
        }
    }
}

private struct SettingsView: View {
    let model: AppModel
    let login: SettingsLoginState
    let onLoginChange: () -> Void

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
                    Toggle("Launch at login", isOn: Binding(get: { login.enabled }, set: { enabled in
                        login.setEnabled(enabled)
                        onLoginChange()
                    }))
                    .labelsHidden().toggleStyle(MonochromeSwitchStyle())
                    if login.pending {
                        Text("Pending approval").font(.system(size: 11)).foregroundStyle(Mono.ink2)
                    }
                }
                if login.pending {
                    Button("Open Login Items in System Settings") { LoginItem.openSettings() }
                        .font(.system(size: 11)).padding(.top, 6)
                }
                if let loginError = login.error {
                    Text(loginError).font(.system(size: 11)).foregroundStyle(Mono.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                        .accessibilityLabel("Launch at login error: \(loginError)")
                }
            }
            .padding(18)
            .layoutPriority(1)
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
        .frame(minHeight: login.hasMessage ? 490 : 430)
        .background(WindowStyle.background)
        .foregroundStyle(Mono.ink)
        .preferredColorScheme(.dark)
        .tint(.white)
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

}

private struct MonochromeSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color.white : Color.white.opacity(0.18))
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(configuration.isOn ? Color.black : Color.white)
                        .frame(width: 15, height: 15).padding(2)
                }
                .frame(width: 32, height: 19)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}
