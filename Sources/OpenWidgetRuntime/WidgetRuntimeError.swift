package enum WidgetRuntimeError: Error, Equatable, Sendable {
    case duplicateKind(String)
    case duplicateInstance(String)
    case unknownKind(String)
    case unknownInstance(String)
    case providerTimedOut(kind: String)
    case providerCancelled(kind: String)
    case providerFailed
    case invalidProviderTimeout
    case semantic(WidgetSemanticError)
    case invalidTimeline(TimelineRuntimeError)
    case hostUnavailable
    case hostRejected(message: String)
    case hostOperationFailed
    case unsupportedWidgetConfiguration(typeName: String)
    case invalidWidgetKind
    case unsupportedFamily(kind: String, family: RuntimeWidgetFamily)
    case invalidDisplaySize
    case missingEnvironmentVariants
    case providerTimelineOwnershipConsumed
    case generationExhausted(instanceID: String)
    case staleGeneration(instanceID: String, generation: UInt64)
    case identitySpaceExhausted
    case invalidSchedulerDeadline
}
