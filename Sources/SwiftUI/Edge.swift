import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public enum Edge: Int8, CaseIterable {
    case top
    case leading
    case bottom
    case trailing

    public struct Set: OptionSet {
        public let rawValue: Int8

        public init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        // These values are immutable. The annotation keeps Apple's public
        // non-Sendable type while satisfying Swift 6 global-state checking.
        nonisolated(unsafe) public static let top = Set(rawValue: 1 << Edge.top.rawValue)
        nonisolated(unsafe) public static let leading = Set(rawValue: 1 << Edge.leading.rawValue)
        nonisolated(unsafe) public static let bottom = Set(rawValue: 1 << Edge.bottom.rawValue)
        nonisolated(unsafe) public static let trailing = Set(rawValue: 1 << Edge.trailing.rawValue)
        nonisolated(unsafe) public static let all: Set = [.top, .leading, .bottom, .trailing]
        nonisolated(unsafe) public static let horizontal: Set = [.leading, .trailing]
        nonisolated(unsafe) public static let vertical: Set = [.top, .bottom]

        public init(_ edge: Edge) {
            self.init(rawValue: 1 << edge.rawValue)
        }

        package var widgetValue: WidgetEdge {
            WidgetEdge(rawValue: rawValue)
        }
    }
}
