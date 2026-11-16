import Foundation

/// Source of "now". Named TimeSource so it does not shadow `Swift.Clock`.
public protocol TimeSource: AnyObject {
    var now: Date { get }
}

public final class SystemTimeSource: TimeSource {
    public init() {}
    public var now: Date { Date() }
}

/// For tests: move time by hand, then call `TimerEngine.reconcile()`.
public final class ManualTimeSource: TimeSource {
    public var now: Date
    public init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { now = start }
    public func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
