@MainActor
package protocol WidgetRuntimeBootstrap: AnyObject, Sendable {
    func run(registry: RuntimeWidgetRegistry) async throws
}
