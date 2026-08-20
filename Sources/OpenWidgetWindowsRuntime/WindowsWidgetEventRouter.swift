import Synchronization

package final class WindowsWidgetEventRouter: Sendable {
    private struct State: Sendable {
        var controller: WindowsWidgetProviderController?
        var events: [WindowsWidgetProviderEvent] = []
        var isDraining = false
    }

    private let state = Mutex(State())
    private let diagnostics: @Sendable (WindowsWidgetBridgeDiagnostic) -> Void

    package init(
        diagnostics: @escaping @Sendable (WindowsWidgetBridgeDiagnostic) -> Void
    ) {
        self.diagnostics = diagnostics
    }

    package func install(_ controller: WindowsWidgetProviderController) {
        let shouldDrain = state.withLock { state in
            state.controller = controller
            guard !state.events.isEmpty, !state.isDraining else { return false }
            state.isDraining = true
            return true
        }
        if shouldDrain {
            startDrain()
        }
    }

    package func enqueue(_ event: WindowsWidgetProviderEvent) {
        let shouldDrain = state.withLock { state in
            state.events.append(event)
            guard state.controller != nil, !state.isDraining else { return false }
            state.isDraining = true
            return true
        }
        if shouldDrain {
            startDrain()
        }
    }

    package func report(_ diagnostic: WindowsWidgetBridgeDiagnostic) {
        diagnostics(diagnostic)
    }

    package func uninstall() {
        state.withLock {
            $0.controller = nil
            $0.events.removeAll(keepingCapacity: false)
        }
    }

    private func startDrain() {
        Task { [self] in
            while let next = state.withLock({ state -> (
                WindowsWidgetProviderEvent,
                WindowsWidgetProviderController
            )? in
                guard let controller = state.controller,
                      !state.events.isEmpty else {
                    state.isDraining = false
                    return nil
                }
                return (state.events.removeFirst(), controller)
            }) {
                await next.1.handle(next.0)
            }
        }
    }
}
