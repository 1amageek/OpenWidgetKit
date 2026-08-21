package enum WidgetSemanticError: Error, Equatable, Sendable {
    case unsupportedView(typeName: String)
    case unsupportedEnvironmentKey
    case duplicateStableID(typeName: String)
    case duplicateActionID(String)
    case unsupportedAppIntentMode(typeName: String)
    case unsupportedAppIntentResult(typeName: String)
    case nonFiniteLayoutValue(field: String)
    case invalidFrameRange(axis: String)
    case invalidLineLimit(Int)
    case invalidColorComponent(component: String)
    case invalidDisplayScale
    case invalidResourceName
}
