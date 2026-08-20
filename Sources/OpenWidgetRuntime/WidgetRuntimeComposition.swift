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
    package static func run(definitions: [RuntimeWidgetDefinition]) async throws {
        let bootstrap = state.withLock { $0.bootstrap }
        guard let bootstrap else {
            throw WidgetRuntimeError.hostUnavailable
        }
        try await bootstrap.run(
            registry: RuntimeWidgetRegistry(definitions: definitions)
        )
    }
}
