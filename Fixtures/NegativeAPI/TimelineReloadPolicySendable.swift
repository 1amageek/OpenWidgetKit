import WidgetKit

private func requireSendable<T: Sendable>(_ value: T) {}

@available(macOS 11.0, iOS 14.0, watchOS 9.0, *)
private func rejectNonAppleConformance() {
    requireSendable(TimelineReloadPolicy.never)
}
