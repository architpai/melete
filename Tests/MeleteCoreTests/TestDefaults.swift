import Foundation

final class TestDefaults {
    private let name = "melete.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
        defaults.synchronize()
        // macOS can persist an empty domain as a plist after removing its values.
        let preferences = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences", isDirectory: true)
        try? FileManager.default.removeItem(at: preferences.appendingPathComponent(name).appendingPathExtension("plist"))
    }
}
