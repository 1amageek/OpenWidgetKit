@MainActor
package protocol WidgetRuntimeBootstrap: AnyObject, Sendable {
    var diagnosticSink: WidgetRuntimeDiagnosticSink { get }

    func run(registry: RuntimeWidgetRegistry) async throws
}
