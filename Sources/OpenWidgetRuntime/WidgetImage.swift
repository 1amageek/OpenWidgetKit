package struct WidgetImage: Equatable, Sendable {
    package let resourceID: WidgetResourceID
    package let label: WidgetText?
    package let isDecorative: Bool

    package init(
        resourceID: WidgetResourceID,
        label: WidgetText?,
        isDecorative: Bool
    ) {
        self.resourceID = resourceID
        self.label = label
        self.isDecorative = isDecorative
    }
}
