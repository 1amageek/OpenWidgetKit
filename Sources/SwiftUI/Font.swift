import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct Font: Hashable, Sendable {
    package let widgetValue: WidgetFont

    private init(_ value: WidgetFont) {
        widgetValue = value
    }

    public static let largeTitle = Font(.largeTitle)
    public static let title = Font(.title)

    @available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
    public static let title2 = Font(.title2)

    @available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
    public static let title3 = Font(.title3)

    public static let headline = Font(.headline)
    public static let subheadline = Font(.subheadline)
    public static let body = Font(.body)
    public static let callout = Font(.callout)
    public static let footnote = Font(.footnote)
    public static let caption = Font(.caption)

    @available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
    public static let caption2 = Font(.caption2)
}
