@MainActor
package struct WidgetViewGraphContext {
    package var path: WidgetNodeID
    package var environment: WidgetEnvironmentSnapshot
    package let identityStore: WidgetIdentityStore
    package private(set) var resources: [WidgetResourceID: WidgetResource]
    package private(set) var actions: [WidgetActionID: WidgetAction]

    package init(
        path: WidgetNodeID = WidgetNodeID(),
        environment: WidgetEnvironmentSnapshot = WidgetEnvironmentSnapshot(),
        identityStore: WidgetIdentityStore,
        resources: [WidgetResourceID: WidgetResource] = [:],
        actions: [WidgetActionID: WidgetAction] = [:]
    ) {
        self.path = path
        self.environment = environment
        self.identityStore = identityStore
        self.resources = resources
        self.actions = actions
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

    package mutating func register(_ action: WidgetAction) throws {
        guard actions[action.id] == nil else {
            throw WidgetSemanticError.duplicateActionID(action.id.rawValue)
        }
        actions[action.id] = action
    }
}
