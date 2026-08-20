package enum WindowsWidgetHostError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case configurationReadFailed(String)
    case bridgeUnavailable(String)
    case invalidBridgeUTF8
    case hostRejected(code: Int32, message: String)
    case staleGeneration(instanceID: String, generation: UInt64)
    case unknownInstance(String)
    case shuttingDown
    case unsupportedAction(String)
    case packagingFailed(String)
}
