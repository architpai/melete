import ServiceManagement

/// OWNER: sol. The source of truth is SMAppService, not a stored setting.
@MainActor
enum LoginItem {
    static var status: SMAppService.Status {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["MELETE_DEBUG_LOGIN"] {
        case "on": return .enabled
        case "pending": return .requiresApproval
        case "off", "error": return .notRegistered
        default: break
        }
        #endif
        return SMAppService.mainApp.status
    }

    static var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    static func setEnabled(_ on: Bool) throws {
        #if DEBUG
        if ["on", "pending", "off", "error"].contains(ProcessInfo.processInfo.environment["MELETE_DEBUG_LOGIN"]) {
            return
        }
        #endif
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
