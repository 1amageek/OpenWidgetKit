package enum WidgetRuntimeError: Error, Equatable, Sendable {
    case duplicateKind(String)
    case unknownKind(String)
    case unknownInstance(String)
    case providerTimedOut(kind: String)
    case providerCancelled(kind: String)
    case invalidProviderTimeout
    case semantic(WidgetSemanticError)
    case invalidTimeline(TimelineRuntimeError)
    case hostUnavailable
    case hostRejected(message: String)
    case unsupportedWidgetConfiguration(typeName: String)
    case invalidWidgetKind
    case unsupportedFamily(kind: String, family: RuntimeWidgetFamily)
    case invalidDisplaySize
}
