import Synchronization

package enum RuntimeProviderCallbackDisposition: Equatable, Sendable {
    case accepted
    case duplicate
    case late
}

package final class RuntimeProviderRequest<Value: Sendable>: Sendable {
    private struct State: Sendable {
        var continuation: CheckedContinuation<
            Result<Value, WidgetRuntimeError>,
            Never
        >?
        var timeoutTask: Task<Void, Never>?
        var callbackClaimed = false
        var terminalResult: Result<Value, WidgetRuntimeError>?
    }

    private let state = Mutex(State())
    private let kind: String
    private let diagnostics: WidgetRuntimeDiagnosticSink

    package init(
        kind: String,
        diagnostics: @escaping WidgetRuntimeDiagnosticSink
    ) {
        self.kind = kind
        self.diagnostics = diagnostics
    }

    @MainActor
    package static func perform(
        kind: String,
        timeout: Duration,
        diagnostics: @escaping WidgetRuntimeDiagnosticSink,
        start: (RuntimeProviderRequest<Value>) -> Void
    ) async throws -> Value {
        guard timeout > .zero else {
            throw WidgetRuntimeError.invalidProviderTimeout
        }
        let request = RuntimeProviderRequest(
            kind: kind,
            diagnostics: diagnostics
        )
        return try await withTaskCancellationHandler {
            let result = await withCheckedContinuation { continuation in
                guard request.install(continuation) else { return }
                start(request)
                request.startTimeout(after: timeout)
            }
            return try result.get()
        } onCancel: {
            request.cancel()
        }
    }

    package func claimProviderCallback() -> RuntimeProviderCallbackDisposition {
        let disposition: RuntimeProviderCallbackDisposition = state.withLock { state in
            guard state.terminalResult == nil else { return .late }
            guard !state.callbackClaimed else { return .duplicate }
            state.callbackClaimed = true
            return .accepted
        }
        switch disposition {
        case .accepted:
            break
        case .duplicate:
            diagnostics(.duplicateProviderCompletion(kind: kind))
        case .late:
            diagnostics(.lateProviderCompletion(kind: kind))
        }
        return disposition
    }

    package func succeed(_ value: Value) {
        guard complete(.success(value)) else {
            diagnostics(.lateProviderCompletion(kind: kind))
            return
        }
    }

    package func fail(_ error: WidgetRuntimeError) {
        guard complete(.failure(error)) else {
            diagnostics(.lateProviderCompletion(kind: kind))
            return
        }
    }

    private func install(
        _ continuation: CheckedContinuation<
            Result<Value, WidgetRuntimeError>,
            Never
        >
    ) -> Bool {
        let terminalResult: Result<Value, WidgetRuntimeError>? = state.withLock { state in
            if let result = state.terminalResult {
                return result
            }
            state.continuation = continuation
            return nil
        }
        if let terminalResult {
            continuation.resume(returning: terminalResult)
            return false
        }
        return true
    }

    private func startTimeout(after duration: Duration) {
        let task = Task { [self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            _ = complete(.failure(.providerTimedOut(kind: kind)))
        }
        let shouldCancel = state.withLock { state in
            guard state.terminalResult == nil else { return true }
            state.timeoutTask = task
            return false
        }
        if shouldCancel {
            task.cancel()
        }
    }

    private func cancel() {
        _ = complete(.failure(.providerCancelled(kind: kind)))
    }

    @discardableResult
    private func complete(_ result: Result<Value, WidgetRuntimeError>) -> Bool {
        let action = state.withLock { state -> (
            CheckedContinuation<Result<Value, WidgetRuntimeError>, Never>?,
            Task<Void, Never>?
        )? in
            guard state.terminalResult == nil else { return nil }
            state.terminalResult = result
            defer {
                state.continuation = nil
                state.timeoutTask = nil
            }
            return (state.continuation, state.timeoutTask)
        }
        guard let action else { return false }
        action.1?.cancel()
        action.0?.resume(returning: result)
        return true
    }
}
