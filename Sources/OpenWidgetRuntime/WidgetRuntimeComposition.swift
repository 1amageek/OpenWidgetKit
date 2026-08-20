import Synchronization

package enum WidgetRuntimeComposition {
    private struct State: Sendable {
        var control: (any WidgetRuntimeControl)?
        var bootstrap: (any WidgetRuntimeBootstrap)?
    }

    private static let state = Mutex(State())

    package static func installControl(_ control: any WidgetRuntimeControl) {
        state.withLock { $0.control = control }
    }

    @MainActor
    package static func installBootstrap(_ bootstrap: any WidgetRuntimeBootstrap) {
        state.withLock { $0.bootstrap = bootstrap }
    }

    package static func uninstall() {
        state.withLock {
            $0.control = nil
            $0.bootstrap = nil
        }
    }

    package static func currentControl() -> (any WidgetRuntimeControl)? {
        state.withLock { $0.control }
    }

    @MainActor
    package static func run(definitions: [RuntimeWidgetDefinition]) throws {
        let bootstrap = state.withLock { $0.bootstrap }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Widget.main() reaches this branch when no M5
        // platform host has installed the production bootstrap. A real Windows provider
        // composition and blocking host lifecycle are required before startup may succeed.
        guard let bootstrap else {
            throw WidgetRuntimeError.hostUnavailable
        }
        try bootstrap.run(registry: RuntimeWidgetRegistry(definitions: definitions))
    }
}
