import OpenFoundation
import OpenWidgetRuntime

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
public struct TimelineReloadPolicy: Equatable {
    private enum Storage: Equatable, Sendable {
        case atEnd
        case after(Date)
        case never
    }

    private let storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    // These immutable values are safe to share. The annotation preserves Apple's
    // non-Sendable public type while satisfying Swift 6 global-state checking.
    nonisolated(unsafe) public static let atEnd = TimelineReloadPolicy(storage: .atEnd)
    nonisolated(unsafe) public static let never = TimelineReloadPolicy(storage: .never)

    public static func after(_ date: Date) -> TimelineReloadPolicy {
        TimelineReloadPolicy(storage: .after(date))
    }

    package var runtimeValue: RuntimeTimelineReloadPolicy {
        switch storage {
        case .atEnd:
            return .atEnd
        case .after(let date):
            return .after(date)
        case .never:
            return .never
        }
    }
}
