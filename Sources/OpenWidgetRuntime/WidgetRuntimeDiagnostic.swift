import OpenFoundation

package enum WidgetRuntimeDiagnostic: Equatable, Sendable {
    case duplicateProviderCompletion(kind: String)
    case lateProviderCompletion(kind: String)
    case staleGeneration(instanceID: String, generation: UInt64)
    case reloadRequestedForUnknownKind(String)
    case nonAdvancingReload(
        instanceID: String,
        scheduledDate: Date,
        currentDate: Date
    )
    case hostUpdateFailed(instanceID: String, message: String)
}

package typealias WidgetRuntimeDiagnosticSink = @Sendable (
    WidgetRuntimeDiagnostic
) -> Void
