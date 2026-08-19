import OpenFoundation
import OpenWidgetRuntime

public struct TimelineReloadPolicy: Equatable, Sendable {
    private enum Storage: Equatable, Sendable {
        case atEnd
        case after(Date)
        case never
    }

    private let storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    public static let atEnd = TimelineReloadPolicy(storage: .atEnd)
    public static let never = TimelineReloadPolicy(storage: .never)

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
