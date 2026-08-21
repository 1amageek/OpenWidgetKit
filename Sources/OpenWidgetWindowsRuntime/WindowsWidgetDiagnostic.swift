import OpenWidgetRuntime

package struct WindowsWidgetDiagnostic: Equatable, Sendable {
    package enum Domain: String, Equatable, Sendable {
        case bridge
        case runtime
        case providerEvent
        case eventIngress
        case shutdown
    }

    package enum RuntimeCauseCode: String, Equatable, Sendable {
        case duplicateProviderCompletion
        case lateProviderCompletion
        case staleGeneration
        case reloadRequestedForUnknownKind
        case nonAdvancingReload
        case controlUnavailable
        case diagnosticBufferOverflow
    }

    package enum HostFailureCode: String, Equatable, Sendable {
        case invalidConfiguration
        case configurationReadFailed
        case bridgeUnavailable
        case invalidBridgeUTF8
        case unsupportedBridgeWidgetSize
        case hostRejected
        case staleGeneration
        case unknownInstance
        case shuttingDown
        case unknownAction
        case duplicateAction
        case staleAction
        case invalidActionPayload
        case actionRevisionExhausted
        case invalidEventQueueCapacity
        case packagingFailed

        package init(_ error: WindowsWidgetHostError) {
            switch error {
            case .invalidConfiguration:
                self = .invalidConfiguration
            case .configurationReadFailed:
                self = .configurationReadFailed
            case .bridgeUnavailable:
                self = .bridgeUnavailable
            case .invalidBridgeUTF8:
                self = .invalidBridgeUTF8
            case .unsupportedBridgeWidgetSize:
                self = .unsupportedBridgeWidgetSize
            case .hostRejected:
                self = .hostRejected
            case .staleGeneration:
                self = .staleGeneration
            case .unknownInstance:
                self = .unknownInstance
            case .shuttingDown:
                self = .shuttingDown
            case .unknownAction:
                self = .unknownAction
            case .duplicateAction:
                self = .duplicateAction
            case .staleAction:
                self = .staleAction
            case .invalidActionPayload:
                self = .invalidActionPayload
            case .actionRevisionExhausted:
                self = .actionRevisionExhausted
            case .invalidEventQueueCapacity:
                self = .invalidEventQueueCapacity
            case .packagingFailed:
                self = .packagingFailed
            }
        }
    }

    package enum Cause: Equatable, Sendable {
        case runtime(RuntimeCauseCode)
        case runtimeFailure(WidgetRuntimeFailureCode)
        case host(HostFailureCode)
        case bridgeStatus(Int32)
        case unknownBridgeEventKind(Int32)
        case eventQueueOverflow(capacity: Int)
        case shutdownRequestFailed
        case unexpected
    }

    package let code: Int32
    package let domain: Domain
    package let operation: String
    package let kind: String?
    package let instanceID: String?
    package let generation: UInt64?
    package let cause: Cause

    package var renderedMessage: String {
        var components = [
            "code=\(code)",
            "domain=\(domain.rawValue)",
            "operation=\(operation)",
            "cause=\(causeName)"
        ]
        if let kind {
            components.append("kind=\(Self.encodedField(kind))")
        }
        if let instanceID {
            components.append("instance=\(Self.encodedField(instanceID))")
        }
        if let generation {
            components.append("generation=\(generation)")
        }
        return components.joined(separator: " ")
    }

    package static func runtime(
        _ diagnostic: WidgetRuntimeDiagnostic
    ) -> WindowsWidgetDiagnostic {
        switch diagnostic {
        case .duplicateProviderCompletion(let kind, let instanceID, let generation):
            return WindowsWidgetDiagnostic(
                code: -3,
                domain: .runtime,
                operation: WidgetRuntimeOperation.timelineRequest.rawValue,
                kind: kind,
                instanceID: instanceID,
                generation: generation,
                cause: .runtime(.duplicateProviderCompletion)
            )
        case .lateProviderCompletion(let kind, let instanceID, let generation):
            return WindowsWidgetDiagnostic(
                code: -3,
                domain: .runtime,
                operation: WidgetRuntimeOperation.timelineRequest.rawValue,
                kind: kind,
                instanceID: instanceID,
                generation: generation,
                cause: .runtime(.lateProviderCompletion)
            )
        case .staleGeneration(let instanceID, let generation):
            return WindowsWidgetDiagnostic(
                code: -3,
                domain: .runtime,
                operation: WidgetRuntimeOperation.timelineRequest.rawValue,
                kind: nil,
                instanceID: instanceID,
                generation: generation,
                cause: .runtime(.staleGeneration)
            )
        case .reloadRequestedForUnknownKind(let kind):
            return WindowsWidgetDiagnostic(
                code: -3,
                domain: .runtime,
                operation: WidgetRuntimeOperation.reloadTimelines.rawValue,
                kind: kind,
                instanceID: nil,
                generation: nil,
                cause: .runtime(.reloadRequestedForUnknownKind)
            )
        case .nonAdvancingReload(let instanceID, let generation, _, _):
            return WindowsWidgetDiagnostic(
                code: -3,
                domain: .runtime,
                operation: WidgetRuntimeOperation.timelineRequest.rawValue,
                kind: nil,
                instanceID: instanceID,
                generation: generation,
                cause: .runtime(.nonAdvancingReload)
            )
        case .controlUnavailable(let operation, let kind):
            return WindowsWidgetDiagnostic(
                code: -3,
                domain: .runtime,
                operation: operation.rawValue,
                kind: kind,
                instanceID: nil,
                generation: nil,
                cause: .runtime(.controlUnavailable)
            )
        case .operationFailed(
            let instanceID,
            let kind,
            let generation,
            let operation,
            let cause
        ):
            return WindowsWidgetDiagnostic(
                code: -3,
                domain: .runtime,
                operation: operation.rawValue,
                kind: kind,
                instanceID: instanceID,
                generation: generation,
                cause: .runtimeFailure(cause)
            )
        case .diagnosticBufferOverflow:
            return WindowsWidgetDiagnostic(
                code: -3,
                domain: .runtime,
                operation: WidgetRuntimeOperation.startup.rawValue,
                kind: nil,
                instanceID: nil,
                generation: nil,
                cause: .runtime(.diagnosticBufferOverflow)
            )
        }
    }

    package static func bridgeStatus(_ code: Int32) -> WindowsWidgetDiagnostic {
        WindowsWidgetDiagnostic(
            code: code,
            domain: .bridge,
            operation: "bridgeCallback",
            kind: nil,
            instanceID: nil,
            generation: nil,
            cause: .bridgeStatus(code)
        )
    }

    package static func bridgeEventFailure(
        eventKind: Int32,
        error: any Error
    ) -> WindowsWidgetDiagnostic {
        let cause: Cause
        if let hostError = error as? WindowsWidgetHostError {
            cause = .host(HostFailureCode(hostError))
        } else {
            cause = .unexpected
        }
        return WindowsWidgetDiagnostic(
            code: -1,
            domain: .bridge,
            operation: "decodeEvent.\(eventKind)",
            kind: nil,
            instanceID: nil,
            generation: nil,
            cause: cause
        )
    }

    package static func unknownBridgeEventKind(
        _ eventKind: Int32
    ) -> WindowsWidgetDiagnostic {
        WindowsWidgetDiagnostic(
            code: -1,
            domain: .bridge,
            operation: "decodeEvent",
            kind: nil,
            instanceID: nil,
            generation: nil,
            cause: .unknownBridgeEventKind(eventKind)
        )
    }

    package static func providerEventFailure(
        event: WindowsWidgetProviderEvent,
        kind: String?,
        generation: UInt64?,
        error: any Error
    ) -> WindowsWidgetDiagnostic {
        let cause: Cause
        if let runtimeError = error as? WidgetRuntimeError {
            cause = .runtimeFailure(WidgetRuntimeFailureCode(runtimeError))
        } else if let hostError = error as? WindowsWidgetHostError {
            cause = .host(HostFailureCode(hostError))
        } else {
            cause = .unexpected
        }
        return WindowsWidgetDiagnostic(
            code: -2,
            domain: .providerEvent,
            operation: event.operationName,
            kind: event.widgetKind ?? kind,
            instanceID: event.instanceID,
            generation: generation,
            cause: cause
        )
    }

    package static func eventQueueOverflow(
        capacity: Int
    ) -> WindowsWidgetDiagnostic {
        WindowsWidgetDiagnostic(
            code: -5,
            domain: .eventIngress,
            operation: "enqueue",
            kind: nil,
            instanceID: nil,
            generation: nil,
            cause: .eventQueueOverflow(capacity: capacity)
        )
    }

    package static func shutdownRequestFailed() -> WindowsWidgetDiagnostic {
        WindowsWidgetDiagnostic(
            code: -4,
            domain: .shutdown,
            operation: WidgetRuntimeOperation.shutdown.rawValue,
            kind: nil,
            instanceID: nil,
            generation: nil,
            cause: .shutdownRequestFailed
        )
    }

    private var causeName: String {
        switch cause {
        case .runtime(let code):
            "runtime.\(code.rawValue)"
        case .runtimeFailure(let code):
            "runtimeFailure.\(code.rawValue)"
        case .host(let code):
            "host.\(code.rawValue)"
        case .bridgeStatus(let status):
            "bridgeStatus.\(status)"
        case .unknownBridgeEventKind(let eventKind):
            "unknownBridgeEventKind.\(eventKind)"
        case .eventQueueOverflow(let capacity):
            "eventQueueOverflow.capacity.\(capacity)"
        case .shutdownRequestFailed:
            "shutdownRequestFailed"
        case .unexpected:
            "unexpected"
        }
    }

    private static func encodedField(_ value: String) -> String {
        var result = ""
        var scalarCount = 0
        for scalar in value.unicodeScalars {
            guard scalarCount < 128 else {
                result += "..."
                break
            }
            scalarCount += 1
            switch scalar.value {
            case 48...57, 65...90, 97...122, 45, 46, 95:
                result.unicodeScalars.append(scalar)
            default:
                result += "\\u{\(String(scalar.value, radix: 16))}"
            }
        }
        return result
    }
}
