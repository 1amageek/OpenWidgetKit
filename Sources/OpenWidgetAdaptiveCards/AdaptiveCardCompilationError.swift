import OpenWidgetRuntime

package enum AdaptiveCardCompilationError: Error, Equatable, Sendable {
    case invalidCacheCapacity(Int)
    case unsupportedHostCapabilities(String)
    case invalidDocument(String)
    case missingThemeVariant(String)
    case duplicateThemeVariant(String)
    case unsupportedNode(String)
    case unsupportedModifier(String)
    case unsupportedColor(String)
    case unresolvedResource(String)
    case invalidLocalizedString(String)
    case serializationFailed(String)
}

extension AdaptiveCardCompilationError: WidgetRuntimeFailureConvertible {
    package var widgetRuntimeFailureCode: WidgetRuntimeFailureCode {
        .compilationFailed
    }
}
