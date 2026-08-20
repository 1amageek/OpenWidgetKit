import OpenWidgetRuntime

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@preconcurrency
public struct WidgetInfo: Identifiable, Hashable, Sendable,
    CustomDebugStringConvertible {
    private let instanceID: String

    public let family: WidgetFamily
    public let kind: String

    public var id: WidgetInfo { self }

    public var debugDescription: String {
        "WidgetInfo(kind: \(kind), family: \(family), instanceID: \(instanceID))"
    }

    package init(runtimeValue: RuntimeWidgetInfo) {
        instanceID = runtimeValue.instanceID
        family = WidgetFamily(runtimeValue: runtimeValue.family)
        kind = runtimeValue.kind
    }
}
