import OpenFoundation

package protocol WidgetRuntimeClock: Sendable {
    func now() async -> Date
    func sleep(until date: Date) async throws
}

package struct SystemWidgetRuntimeClock: WidgetRuntimeClock {
    package init() {}

    package func now() async -> Date {
        Date()
    }

    package func sleep(until date: Date) async throws {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }
        let nanoseconds = interval * 1_000_000_000
        guard nanoseconds.isFinite, nanoseconds <= Double(UInt64.max) else {
            throw WidgetRuntimeError.invalidSchedulerDeadline
        }
        try await Task.sleep(nanoseconds: UInt64(nanoseconds.rounded(.up)))
    }
}
