import OpenWidgetRuntime

package enum WindowsWidgetProviderEvent: Equatable, Sendable {
    case create(instanceID: String, kind: String, family: RuntimeWidgetFamily)
    case recover(
        instanceID: String,
        kind: String,
        family: RuntimeWidgetFamily,
        isActive: Bool
    )
    case activate(instanceID: String)
    case deactivate(instanceID: String)
    case contextChanged(instanceID: String, family: RuntimeWidgetFamily)
    case delete(instanceID: String, customState: String)
    case actionInvoked(
        instanceID: String,
        verb: String,
        data: String,
        customState: String
    )
    case shutdownRequested
}

package struct WindowsWidgetBridgeDiagnostic: Equatable, Sendable {
    package let code: Int32
    package let message: String

    package init(code: Int32, message: String) {
        self.code = code
        self.message = message
    }
}
