package enum WidgetRuntimeFailureCode: String, Equatable, Sendable {
    case duplicateDefinition
    case duplicateInstance
    case unknownDefinition
    case unknownInstance
    case providerTimedOut
    case providerCancelled
    case providerFailed
    case invalidProviderTimeout
    case semanticFailure
    case invalidTimeline
    case compilationFailed
    case hostUnavailable
    case hostRejected
    case hostOperationFailed
    case bridgeUnavailable
    case unsupportedWidgetConfiguration
    case invalidWidgetKind
    case unsupportedFamily
    case invalidDisplaySize
    case missingEnvironmentVariants
    case providerTimelineOwnershipConsumed
    case generationExhausted
    case staleGeneration
    case identitySpaceExhausted
    case invalidSchedulerDeadline
    case unexpected

    package init(_ error: any Error) {
        guard let runtimeError = error as? WidgetRuntimeError else {
            if let convertible = error as? any WidgetRuntimeFailureConvertible {
                self = convertible.widgetRuntimeFailureCode
            } else {
                self = .unexpected
            }
            return
        }
        self.init(runtimeError)
    }

    package init(_ error: WidgetRuntimeError) {
        switch error {
        case .duplicateKind:
            self = .duplicateDefinition
        case .duplicateInstance:
            self = .duplicateInstance
        case .unknownKind:
            self = .unknownDefinition
        case .unknownInstance:
            self = .unknownInstance
        case .providerTimedOut:
            self = .providerTimedOut
        case .providerCancelled:
            self = .providerCancelled
        case .providerFailed:
            self = .providerFailed
        case .invalidProviderTimeout:
            self = .invalidProviderTimeout
        case .semantic:
            self = .semanticFailure
        case .invalidTimeline:
            self = .invalidTimeline
        case .hostUnavailable:
            self = .hostUnavailable
        case .hostRejected:
            self = .hostRejected
        case .hostOperationFailed:
            self = .hostOperationFailed
        case .unsupportedWidgetConfiguration:
            self = .unsupportedWidgetConfiguration
        case .invalidWidgetKind:
            self = .invalidWidgetKind
        case .unsupportedFamily:
            self = .unsupportedFamily
        case .invalidDisplaySize:
            self = .invalidDisplaySize
        case .missingEnvironmentVariants:
            self = .missingEnvironmentVariants
        case .providerTimelineOwnershipConsumed:
            self = .providerTimelineOwnershipConsumed
        case .generationExhausted:
            self = .generationExhausted
        case .staleGeneration:
            self = .staleGeneration
        case .identitySpaceExhausted:
            self = .identitySpaceExhausted
        case .invalidSchedulerDeadline:
            self = .invalidSchedulerDeadline
        }
    }
}
