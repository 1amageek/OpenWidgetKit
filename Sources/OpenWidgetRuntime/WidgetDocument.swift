package struct WidgetDocument: Equatable, Sendable {
    package let root: WidgetNode
    package let environment: WidgetEnvironmentSnapshot
    package let resources: [WidgetResourceID: WidgetResource]

    package init(
        root: WidgetNode,
        environment: WidgetEnvironmentSnapshot,
        resources: [WidgetResourceID: WidgetResource] = [:]
    ) {
        self.root = root
        self.environment = environment
        self.resources = resources
    }
}
