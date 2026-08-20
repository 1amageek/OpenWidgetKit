import OpenFoundation

package struct WidgetInsets: Equatable, Sendable {
    package let top: CGFloat
    package let leading: CGFloat
    package let bottom: CGFloat
    package let trailing: CGFloat

    package init(
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
}
