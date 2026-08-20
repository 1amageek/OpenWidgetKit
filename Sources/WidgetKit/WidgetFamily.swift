@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@preconcurrency
public enum WidgetFamily: Int, CustomDebugStringConvertible, CustomStringConvertible, Sendable {
    @available(iOS 14.0, macOS 11.0, visionOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    case systemSmall

    @available(iOS 14.0, macOS 11.0, visionOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    case systemMedium

    @available(iOS 14.0, macOS 11.0, visionOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    case systemLarge

    public var debugDescription: String { description }

    public var description: String {
        switch self {
        case .systemSmall:
            return "systemSmall"
        case .systemMedium:
            return "systemMedium"
        case .systemLarge:
            return "systemLarge"
        }
    }
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
extension WidgetFamily: Hashable {}
