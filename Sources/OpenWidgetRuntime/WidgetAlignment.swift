package struct WidgetAlignment: Equatable, Sendable {
    package let horizontal: WidgetHorizontalAlignment
    package let vertical: WidgetVerticalAlignment

    package init(
        horizontal: WidgetHorizontalAlignment,
        vertical: WidgetVerticalAlignment
    ) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}
