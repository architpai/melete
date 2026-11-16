import Foundation

/// DEBUG-only log to /tmp/melete-notch.log (spike + visual checks). No-op in release.
enum NotchLog {
    #if DEBUG
    private static let url = URL(fileURLWithPath: "/tmp/melete-notch.log")
    nonisolated(unsafe) private static var handle: FileHandle? = {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try? FileHandle(forWritingTo: url)
    }()
    #endif

    static func log(_ s: @autoclosure () -> String) {
        #if DEBUG
        let line = "\(String(format: "%.3f", Date().timeIntervalSince1970)) \(s())\n"
        handle?.write(line.data(using: .utf8)!)
        #endif
    }
}
