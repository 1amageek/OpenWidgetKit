import OpenFoundation

package struct RuntimeProviderContext: Sendable {
    package let family: RuntimeWidgetFamily
    package let isPreview: Bool
    package let displaySize: CGSize
    package let environment: WidgetEnvironmentSnapshot
    package let additionalEnvironments: [WidgetEnvironmentSnapshot]
    package let identityStore: WidgetIdentityStore

    package var environmentVariants: [WidgetEnvironmentSnapshot] {
        [environment] + additionalEnvironments
    }

    package init(
        family: RuntimeWidgetFamily,
        isPreview: Bool,
        displaySize: CGSize,
        environment: WidgetEnvironmentSnapshot,
        additionalEnvironments: [WidgetEnvironmentSnapshot] = [],
        identityStore: WidgetIdentityStore
    ) {
        self.family = family
        self.isPreview = isPreview
        self.displaySize = displaySize
        self.environment = environment
        self.additionalEnvironments = additionalEnvironments
        self.identityStore = identityStore
    }
}
