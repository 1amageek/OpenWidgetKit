import OpenFoundation

package struct WidgetFrame: Equatable, Sendable {
    package let minWidth: CGFloat?
    package let idealWidth: CGFloat?
    package let maxWidth: CGFloat?
    package let minHeight: CGFloat?
    package let idealHeight: CGFloat?
    package let maxHeight: CGFloat?
    package let alignment: WidgetAlignment

    package init(
        minWidth: CGFloat? = nil,
        idealWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        idealHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        alignment: WidgetAlignment
    ) {
        self.minWidth = minWidth
        self.idealWidth = idealWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.idealHeight = idealHeight
        self.maxHeight = maxHeight
        self.alignment = alignment
    }
}
