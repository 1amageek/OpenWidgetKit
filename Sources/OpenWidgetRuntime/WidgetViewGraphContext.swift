@MainActor
package struct WidgetViewGraphContext {
    package var path: WidgetNodeID
    package var environment: WidgetEnvironmentSnapshot
    package let identityStore: WidgetIdentityStore
    package private(set) var resources: [WidgetResourceID: WidgetResource]

    package init(
        path: WidgetNodeID = WidgetNodeID(),
        environment: WidgetEnvironmentSnapshot = WidgetEnvironmentSnapshot(),
        identityStore: WidgetIdentityStore,
        resources: [WidgetResourceID: WidgetResource] = [:]
    ) {
        self.path = path
        self.environment = environment
        self.identityStore = identityStore
        self.resources = resources
    }

    package mutating func withPath<Result>(
        _ component: WidgetNodeID.Component,
        _ body: (inout WidgetViewGraphContext) throws -> Result
    ) rethrows -> Result {
        let previousPath = path
        path = path.appending(component)
        defer { path = previousPath }
        return try body(&self)
    }

    package mutating func register(_ resource: WidgetResource) -> WidgetResourceID {
        let id = resource.id
        resources[id] = resource
        return id
    }
}
