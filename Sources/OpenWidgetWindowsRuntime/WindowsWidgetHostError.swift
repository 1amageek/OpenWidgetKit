import OpenWidgetRuntime

package enum WindowsWidgetHostError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case configurationReadFailed(String)
    case bridgeUnavailable(String)
    case invalidBridgeUTF8
    case unsupportedBridgeWidgetSize(Int32)
    case hostRejected(code: Int32, message: String)
    case staleGeneration(instanceID: String, generation: UInt64)
    case unknownInstance(String)
    case shuttingDown
    case unknownAction(instanceID: String, verb: String)
    case duplicateAction(instanceID: String, verb: String)
    case staleAction(instanceID: String, verb: String)
    case invalidActionPayload(instanceID: String, verb: String)
    case actionRevisionExhausted(instanceID: String)
    case invalidEventQueueCapacity(Int)
    case packagingFailed(String)
}

extension WindowsWidgetHostError: WidgetRuntimeFailureConvertible {
    package var widgetRuntimeFailureCode: WidgetRuntimeFailureCode {
        switch self {
        case .bridgeUnavailable:
            .bridgeUnavailable
        case .staleGeneration:
            .staleGeneration
        case .unknownInstance:
            .unknownInstance
        case .shuttingDown:
            .hostUnavailable
        case .invalidConfiguration,
             .configurationReadFailed,
             .invalidBridgeUTF8,
             .unsupportedBridgeWidgetSize,
             .hostRejected,
             .unknownAction,
             .duplicateAction,
             .staleAction,
             .invalidActionPayload,
             .actionRevisionExhausted,
             .invalidEventQueueCapacity,
             .packagingFailed:
            .hostRejected
        }
    }
}
