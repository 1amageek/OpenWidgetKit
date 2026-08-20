import OpenFoundation

package struct RuntimeProviderContext: Sendable {
    package let family: RuntimeWidgetFamily
    package let isPreview: Bool
    package let displaySize: CGSize
    package let environment: WidgetEnvironmentSnapshot
    package let identityStore: WidgetIdentityStore

    package init(
        family: RuntimeWidgetFamily,
        isPreview: Bool,
        displaySize: CGSize,
        environment: WidgetEnvironmentSnapshot,
        identityStore: WidgetIdentityStore
    ) {
        self.family = family
        self.isPreview = isPreview
        self.displaySize = displaySize
        self.environment = environment
        self.identityStore = identityStore
    }
}
