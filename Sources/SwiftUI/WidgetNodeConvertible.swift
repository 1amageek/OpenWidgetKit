import OpenWidgetRuntime

@MainActor
package protocol WidgetNodeConvertible {
    func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode]
}

@MainActor
package func lowerWidgetView<Content: View>(
    _ content: Content,
    in context: inout WidgetViewGraphContext
) throws -> [WidgetNode] {
    if let convertible = content as? any WidgetNodeConvertible {
        return try WidgetEnvironmentContext.$snapshot.withValue(context.environment) {
            try convertible.makeWidgetNodes(in: &context)
        }
    }

    guard Content.Body.self != Never.self else {
        throw WidgetSemanticError.unsupportedView(
            typeName: String(reflecting: Content.self)
        )
    }

    return try WidgetEnvironmentContext.$snapshot.withValue(context.environment) {
        try lowerWidgetView(content.body, in: &context)
    }
}

@MainActor
package func makeWidgetDocument<Content: View>(
    _ content: Content,
    environment: EnvironmentValues = EnvironmentValues(),
    identityStore: WidgetIdentityStore = WidgetIdentityStore()
) throws -> WidgetDocument {
    try identityStore.withEvaluation {
        guard environment.displayScale.isFinite, environment.displayScale > 0 else {
            throw WidgetSemanticError.invalidDisplayScale
        }
        var context = WidgetViewGraphContext(
            environment: environment.widgetSnapshot,
            identityStore: identityStore
        )
        let children = try context.withPath(.role("content")) {
            try lowerWidgetView(content, in: &$0)
        }
        let root = WidgetNode(
            id: WidgetNodeID().appending(.role("root")),
            kind: .group,
            children: children
        )
        return WidgetDocument(
            root: root,
            environment: context.environment,
            resources: context.resources,
            actions: context.actions
        )
    }
}
