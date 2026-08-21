package struct WidgetDocument: Sendable {
    package let root: WidgetNode
    package let environment: WidgetEnvironmentSnapshot
    package let resources: [WidgetResourceID: WidgetResource]
    package let actions: [WidgetActionID: WidgetAction]

    package init(
        root: WidgetNode,
        environment: WidgetEnvironmentSnapshot,
        resources: [WidgetResourceID: WidgetResource] = [:],
        actions: [WidgetActionID: WidgetAction] = [:]
    ) {
        self.root = root
        self.environment = environment
        self.resources = resources
        self.actions = actions
    }
}
