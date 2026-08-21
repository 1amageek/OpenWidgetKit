import Synchronization

package final class WindowsWidgetEventRouter: Sendable {
    private struct EventQueue: Sendable {
        private var storage: [WindowsWidgetProviderEvent?]
        private var readIndex = 0
        private var writeIndex = 0
        private(set) var count = 0

        init(capacity: Int) {
            storage = Array(repeating: nil, count: capacity)
        }

        mutating func enqueue(_ event: WindowsWidgetProviderEvent) -> Bool {
            guard count < storage.count else { return false }
            storage[writeIndex] = event
            writeIndex = (writeIndex + 1) % storage.count
            count += 1
            return true
        }

        mutating func dequeue() -> WindowsWidgetProviderEvent? {
            guard count > 0 else { return nil }
            let event = storage[readIndex]
            storage[readIndex] = nil
            readIndex = (readIndex + 1) % storage.count
            count -= 1
            return event
        }

        mutating func removeAll() {
            for index in storage.indices {
                storage[index] = nil
            }
            readIndex = 0
            writeIndex = 0
            count = 0
        }
    }

    private struct State: Sendable {
        var controller: WindowsWidgetProviderController?
        var events: EventQueue
        var pendingShutdown = false
        var isAcceptingEvents = true
        var didOverflow = false
        var isDraining = false
        var overflowHandler: (@Sendable () -> Void)?
        var didInvokeOverflowHandler = false
    }

    private struct EnqueueResult {
        let shouldDrain: Bool
        let diagnostic: WindowsWidgetDiagnostic?
        let overflowHandler: (@Sendable () -> Void)?
    }

    private let maximumPendingEventCount: Int
    private let state: Mutex<State>
    private let diagnostics: @Sendable (WindowsWidgetDiagnostic) -> Void

    package init(
        maximumPendingEventCount: Int = 256,
        diagnostics: @escaping @Sendable (WindowsWidgetDiagnostic) -> Void
    ) throws {
        guard maximumPendingEventCount > 0 else {
            throw WindowsWidgetHostError.invalidEventQueueCapacity(
                maximumPendingEventCount
            )
        }
        self.maximumPendingEventCount = maximumPendingEventCount
        state = Mutex(
            State(events: EventQueue(capacity: maximumPendingEventCount))
        )
        self.diagnostics = diagnostics
    }

    package func install(_ controller: WindowsWidgetProviderController) {
        let shouldDrain = state.withLock { state in
            state.controller = controller
            guard (state.events.count > 0 || state.pendingShutdown),
                  !state.isDraining else { return false }
            state.isDraining = true
            return true
        }
        if shouldDrain {
            startDrain()
        }
    }

    package func installOverflowHandler(
        _ handler: @escaping @Sendable () -> Void
    ) {
        let pendingHandler = state.withLock { state -> (@Sendable () -> Void)? in
            state.overflowHandler = handler
            guard state.didOverflow,
                  !state.didInvokeOverflowHandler else { return nil }
            state.didInvokeOverflowHandler = true
            return handler
        }
        pendingHandler?()
    }

    package func enqueue(_ event: WindowsWidgetProviderEvent) {
        let result = state.withLock { state -> EnqueueResult in
            if event == .shutdownRequested {
                state.isAcceptingEvents = false
                state.pendingShutdown = true
                return EnqueueResult(
                    shouldDrain: Self.beginDrainingIfPossible(state: &state),
                    diagnostic: nil,
                    overflowHandler: nil
                )
            }
            guard state.isAcceptingEvents else {
                return EnqueueResult(
                    shouldDrain: false,
                    diagnostic: nil,
                    overflowHandler: nil
                )
            }
            guard state.events.enqueue(event) else {
                state.isAcceptingEvents = false
                state.didOverflow = true
                state.pendingShutdown = true
                let handler: (@Sendable () -> Void)?
                if !state.didInvokeOverflowHandler,
                   let installedHandler = state.overflowHandler {
                    state.didInvokeOverflowHandler = true
                    handler = installedHandler
                } else {
                    handler = nil
                }
                return EnqueueResult(
                    shouldDrain: Self.beginDrainingIfPossible(state: &state),
                    diagnostic: .eventQueueOverflow(
                        capacity: maximumPendingEventCount
                    ),
                    overflowHandler: handler
                )
            }
            return EnqueueResult(
                shouldDrain: Self.beginDrainingIfPossible(state: &state),
                diagnostic: nil,
                overflowHandler: nil
            )
        }
        if let diagnostic = result.diagnostic {
            diagnostics(diagnostic)
        }
        result.overflowHandler?()
        if result.shouldDrain {
            startDrain()
        }
    }

    package func report(_ diagnostic: WindowsWidgetDiagnostic) {
        diagnostics(diagnostic)
    }

    package func uninstall() {
        state.withLock {
            $0.controller = nil
            $0.events.removeAll()
            $0.pendingShutdown = false
            $0.isAcceptingEvents = false
            $0.didOverflow = false
            $0.isDraining = false
            $0.overflowHandler = nil
        }
    }

    private static func beginDrainingIfPossible(state: inout State) -> Bool {
        guard state.controller != nil, !state.isDraining else { return false }
        state.isDraining = true
        return true
    }

    private func startDrain() {
        Task { [self] in
            while let next = state.withLock({ state -> (
                WindowsWidgetProviderEvent,
                WindowsWidgetProviderController
            )? in
                guard let controller = state.controller else {
                    state.isDraining = false
                    return nil
                }
                if let event = state.events.dequeue() {
                    return (event, controller)
                }
                if state.pendingShutdown {
                    state.pendingShutdown = false
                    return (.shutdownRequested, controller)
                }
                state.isDraining = false
                return nil
            }) {
                await next.1.handle(next.0)
            }
        }
    }
}
