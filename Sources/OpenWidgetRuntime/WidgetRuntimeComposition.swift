import Synchronization

package enum WidgetRuntimeComposition {
    private static let diagnosticBufferCapacity = 64

    private struct State: Sendable {
        var control: (any WidgetRuntimeControl)?
        var bootstrap: (any WidgetRuntimeBootstrap)?
        var diagnosticSink: WidgetRuntimeDiagnosticSink?
        var pendingDiagnostics: [WidgetRuntimeDiagnostic] = []
        var droppedDiagnosticCount = 0
        var isDeliveringDiagnostics = false
    }

    private static let state = Mutex(State())

    package static func installControl(_ control: any WidgetRuntimeControl) {
        state.withLock { $0.control = control }
    }

    @MainActor
    package static func installBootstrap(_ bootstrap: any WidgetRuntimeBootstrap) {
        let shouldDeliver = state.withLock { state in
            state.bootstrap = bootstrap
            state.diagnosticSink = bootstrap.diagnosticSink
            return beginDiagnosticDeliveryIfNeeded(state: &state)
        }
        if shouldDeliver {
            deliverPendingDiagnostics()
        }
    }

    package static func report(_ diagnostic: WidgetRuntimeDiagnostic) {
        let shouldDeliver = state.withLock { state in
            if state.pendingDiagnostics.count < diagnosticBufferCapacity {
                state.pendingDiagnostics.append(diagnostic)
            } else if state.droppedDiagnosticCount < Int.max {
                state.droppedDiagnosticCount += 1
            }
            return beginDiagnosticDeliveryIfNeeded(state: &state)
        }
        if shouldDeliver {
            deliverPendingDiagnostics()
        }
    }

    package static func uninstall() {
        state.withLock {
            $0.control = nil
            $0.bootstrap = nil
            $0.diagnosticSink = nil
            $0.pendingDiagnostics.removeAll(keepingCapacity: false)
            $0.droppedDiagnosticCount = 0
        }
    }

    package static func uninstallControl() {
        state.withLock { $0.control = nil }
    }

    package static func currentControl() -> (any WidgetRuntimeControl)? {
        state.withLock { $0.control }
    }

    private static func beginDiagnosticDeliveryIfNeeded(
        state: inout State
    ) -> Bool {
        guard state.diagnosticSink != nil,
              !state.isDeliveringDiagnostics,
              (!state.pendingDiagnostics.isEmpty
                || state.droppedDiagnosticCount > 0) else {
            return false
        }
        state.isDeliveringDiagnostics = true
        return true
    }

    private static func deliverPendingDiagnostics() {
        while let delivery = state.withLock({ state -> (
            WidgetRuntimeDiagnosticSink,
            [WidgetRuntimeDiagnostic]
        )? in
            guard let sink = state.diagnosticSink else {
                state.isDeliveringDiagnostics = false
                return nil
            }
            guard (!state.pendingDiagnostics.isEmpty
                    || state.droppedDiagnosticCount > 0) else {
                state.isDeliveringDiagnostics = false
                return nil
            }
            var diagnostics = state.pendingDiagnostics
            if state.droppedDiagnosticCount > 0 {
                diagnostics.append(
                    .diagnosticBufferOverflow(
                        droppedCount: state.droppedDiagnosticCount
                    )
                )
            }
            state.pendingDiagnostics.removeAll(keepingCapacity: true)
            state.droppedDiagnosticCount = 0
            return (sink, diagnostics)
        }) {
            for diagnostic in delivery.1 {
                delivery.0(diagnostic)
            }
        }
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
