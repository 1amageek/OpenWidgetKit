import OpenWidgetRuntime

package struct CompiledWidgetPayload: Sendable {
    package let templateJSON: String
    package let dataJSON: String
    package let structureIdentity: String
    package let resourceReferences: [AdaptiveCardResourceReference]
    package let actionBindings: [AdaptiveCardActionBinding]
    package let templateCompilationWasSkipped: Bool

    package init(
        templateJSON: String,
        dataJSON: String,
        structureIdentity: String,
        resourceReferences: [AdaptiveCardResourceReference],
        actionBindings: [AdaptiveCardActionBinding],
        templateCompilationWasSkipped: Bool
    ) {
        self.templateJSON = templateJSON
        self.dataJSON = dataJSON
        self.structureIdentity = structureIdentity
        self.resourceReferences = resourceReferences
        self.actionBindings = actionBindings
        self.templateCompilationWasSkipped = templateCompilationWasSkipped
    }
}

package struct AdaptiveCardResourceReference: Equatable, Sendable {
    package let resource: WidgetResource
    package let uri: String

    package init(resource: WidgetResource, uri: String) {
        self.resource = resource
        self.uri = uri
    }
}
