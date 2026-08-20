import OpenFoundation

package struct RuntimeWidgetInstanceConfiguration: Sendable {
    package let family: RuntimeWidgetFamily
    package let isPreview: Bool
    package let displaySize: CGSize
    package let environment: WidgetEnvironmentSnapshot

    package init(
        family: RuntimeWidgetFamily,
        isPreview: Bool,
        displaySize: CGSize,
        environment: WidgetEnvironmentSnapshot
    ) {
        self.family = family
        self.isPreview = isPreview
        self.displaySize = displaySize
        self.environment = environment
    }
}
