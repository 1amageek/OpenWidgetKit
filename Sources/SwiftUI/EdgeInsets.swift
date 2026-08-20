import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct EdgeInsets: Equatable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    public init(
        top: CGFloat,
        leading: CGFloat,
        bottom: CGFloat,
        trailing: CGFloat
    ) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public init() {
        self.init(top: 0, leading: 0, bottom: 0, trailing: 0)
    }

    package var widgetValue: WidgetInsets {
        WidgetInsets(
            top: top,
            leading: leading,
            bottom: bottom,
            trailing: trailing
        )
    }
}
