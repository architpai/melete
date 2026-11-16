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
    }
}
