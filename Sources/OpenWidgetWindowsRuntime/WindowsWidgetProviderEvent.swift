import OpenWidgetRuntime

package enum WindowsWidgetProviderEvent: Equatable, Sendable {
    case create(
        instanceID: String,
        kind: String,
        family: RuntimeWidgetFamily,
        isActive: Bool
    )
    case recover(
        instanceID: String,
        kind: String,
        family: RuntimeWidgetFamily,
        isActive: Bool,
        hasRetainedHostContent: Bool
    )
    case activate(instanceID: String)
    case deactivate(instanceID: String)
    case contextChanged(
        instanceID: String,
        family: RuntimeWidgetFamily,
        isActive: Bool
    )
    case delete(instanceID: String, customState: String)
    case actionInvoked(
        instanceID: String,
        verb: String,
        data: String,
        customState: String
    )
    case shutdownRequested
}

extension WindowsWidgetProviderEvent {
    package var operationName: String {
        switch self {
        case .create: "create"
        case .recover: "recover"
        case .activate: "activate"
        case .deactivate: "deactivate"
        case .contextChanged: "contextChanged"
        case .delete: "delete"
        case .actionInvoked: "actionInvoked"
        case .shutdownRequested: "shutdown"
        }
    }

    package var instanceID: String? {
        switch self {
        case .create(let instanceID, _, _, _),
             .recover(let instanceID, _, _, _, _),
             .activate(let instanceID),
             .deactivate(let instanceID),
             .contextChanged(let instanceID, _, _),
             .delete(let instanceID, _),
             .actionInvoked(let instanceID, _, _, _):
            instanceID
        case .shutdownRequested:
            nil
        }
    }

    package var widgetKind: String? {
        switch self {
        case .create(_, let kind, _, _), .recover(_, let kind, _, _, _):
            kind
        default:
            nil
        }
    }
}
