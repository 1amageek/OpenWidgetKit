@preconcurrency
public enum WidgetFamily: Int, CustomDebugStringConvertible, CustomStringConvertible, Sendable {
    case systemSmall
    case systemMedium
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
