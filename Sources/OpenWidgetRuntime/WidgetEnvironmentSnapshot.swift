import OpenFoundation

package struct WidgetEnvironmentSnapshot: Equatable, Sendable {
    package enum ColorScheme: Equatable, Sendable {
        case light
        case dark
    }

    package var colorScheme: ColorScheme
    package var family: RuntimeWidgetFamily?
    package var displayScale: CGFloat

    package init(
        colorScheme: ColorScheme = .light,
        family: RuntimeWidgetFamily? = nil,
        displayScale: CGFloat = 1
    ) {
        self.colorScheme = colorScheme
        self.family = family
        self.displayScale = displayScale
    }
}
