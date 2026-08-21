import OpenFoundation

package enum WidgetRuntimeDiagnostic: Equatable, Sendable {
    case duplicateProviderCompletion(
        kind: String,
        instanceID: String?,
        generation: UInt64?
    )
    case lateProviderCompletion(
        kind: String,
        instanceID: String?,
        generation: UInt64?
    )
    case staleGeneration(instanceID: String, generation: UInt64)
    case reloadRequestedForUnknownKind(String)
    case nonAdvancingReload(
        instanceID: String,
        generation: UInt64,
        scheduledDate: Date,
        currentDate: Date
    )
    case controlUnavailable(
        operation: WidgetRuntimeOperation,
        kind: String?
    )
    case operationFailed(
        instanceID: String?,
        kind: String?,
        generation: UInt64?,
        operation: WidgetRuntimeOperation,
        cause: WidgetRuntimeFailureCode
    )
    case diagnosticBufferOverflow(droppedCount: Int)
}

package typealias WidgetRuntimeDiagnosticSink = @Sendable (
    WidgetRuntimeDiagnostic
) -> Void

extension WidgetRuntimeDiagnostic {
    package func correlated(
        instanceID: String,
        generation: UInt64
    ) -> WidgetRuntimeDiagnostic {
        switch self {
        case .duplicateProviderCompletion(let kind, nil, nil):
            .duplicateProviderCompletion(
                kind: kind,
                instanceID: instanceID,
                generation: generation
            )
        case .lateProviderCompletion(let kind, nil, nil):
            .lateProviderCompletion(
                kind: kind,
                instanceID: instanceID,
                generation: generation
            )
        default:
            self
        }
    }
}
