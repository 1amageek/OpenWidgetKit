import OpenFoundation
import OpenWidgetRuntime

package actor WindowsWidgetProviderController {
    private enum ShutdownState {
        case running
        case draining
        case completed
    }

    private final class ShutdownOperation: Sendable {
        let task: Task<Void, Error>

        init(
            service: WidgetRuntimeService,
            bridge: any WindowsWidgetBridge
        ) {
            task = Task {
                await service.shutdown()
                try bridge.completeShutdown()
            }
        }
    }

    private let configuration: OpenWidgetProviderConfiguration
    private let service: WidgetRuntimeService
    private let bridge: any WindowsWidgetBridge
    private let diagnostics: @Sendable (WindowsWidgetBridgeDiagnostic) -> Void
    private var shutdownState = ShutdownState.running
    private var shutdownOperation: ShutdownOperation?

    package init(
        configuration: OpenWidgetProviderConfiguration,
        service: WidgetRuntimeService,
        bridge: any WindowsWidgetBridge,
        diagnostics: @escaping @Sendable (WindowsWidgetBridgeDiagnostic) -> Void
    ) {
        self.configuration = configuration
        self.service = service
        self.bridge = bridge
        self.diagnostics = diagnostics
    }

    package func handle(_ event: WindowsWidgetProviderEvent) async {
        do {
            if shutdownState != .running, event != .shutdownRequested {
                throw WindowsWidgetHostError.shuttingDown
            }
            switch event {
            case .create(let instanceID, let kind, let family, let isActive):
                try await service.createInstance(
                    id: instanceID,
                    kind: kind,
                    configuration: try instanceConfiguration(
                        kind: kind,
                        family: family
                    ),
                    isActive: isActive
                )
            case .recover(
                let instanceID,
                let kind,
                let family,
                let isActive,
                let hasRetainedHostContent
            ):
                try await service.createInstance(
                    id: instanceID,
                    kind: kind,
                    configuration: try instanceConfiguration(
                        kind: kind,
                        family: family
                    ),
                    isActive: isActive,
                    hasRetainedHostContent: hasRetainedHostContent
                )
            case .activate(let instanceID):
                try await service.activateInstance(id: instanceID)
            case .deactivate(let instanceID):
                try await service.deactivateInstance(id: instanceID)
            case .contextChanged(let instanceID, let family, let isActive):
                guard let current = await service.currentConfigurations()
                    .first(where: { $0.instanceID == instanceID }) else {
                    throw WindowsWidgetHostError.unknownInstance(instanceID)
                }
                try await service.updateContext(
                    for: instanceID,
                    configuration: try instanceConfiguration(
                        kind: current.kind,
                        family: family
                    ),
                    isActive: isActive
                )
            case .delete(let instanceID, _):
                guard await service.currentConfigurations().contains(where: {
                    $0.instanceID == instanceID
                }) else {
                    throw WindowsWidgetHostError.unknownInstance(instanceID)
                }
                await service.deleteInstance(id: instanceID)
            // FIXME(INCOMPLETE_IMPLEMENTATION): The production WinRT
            // OnActionInvoked path currently terminates with a typed unsupported
            // failure. M7 is complete only when validated action identities,
            // payloads, handlers, stale-generation rejection, and reload behavior
            // are implemented and exercised in the real Widgets Board.
            case .actionInvoked(_, let verb, _, _):
                throw WindowsWidgetHostError.unsupportedAction(verb)
            case .shutdownRequested:
                try await completeShutdown()
            }
        } catch {
            let instanceID = event.instanceID
            let runtimeInfo: RuntimeWidgetInfo? = if let instanceID {
                await service.currentConfigurations().first {
                    $0.instanceID == instanceID
                }
            } else {
                nil
            }
            let generation: UInt64? = if let instanceID {
                await service.currentGeneration(for: instanceID)
            } else {
                nil
            }
            diagnostics(
                WindowsWidgetBridgeDiagnostic(
                    code: -2,
                    message: [
                        "operation=\(event.operationName)",
                        "kind=\(event.widgetKind ?? runtimeInfo?.kind ?? "-")",
                        "instance=\(instanceID ?? "-")",
                        "generation=\(generation.map { String($0) } ?? "-")",
                        "cause=\(String(reflecting: type(of: error))): \(error)"
                    ].joined(separator: " ")
                )
            )
        }
    }

    package func completeShutdown() async throws {
        guard shutdownState != .completed else { return }
        let operation: ShutdownOperation
        if let currentOperation = shutdownOperation {
            operation = currentOperation
        } else {
            shutdownState = .draining
            operation = ShutdownOperation(service: service, bridge: bridge)
            shutdownOperation = operation
        }
        do {
            try await operation.task.value
            if shutdownOperation === operation {
                shutdownOperation = nil
                shutdownState = .completed
            }
        } catch {
            if shutdownOperation === operation {
                shutdownOperation = nil
            }
            throw error
        }
    }

    private func instanceConfiguration(
        kind: String,
        family: RuntimeWidgetFamily
    ) throws -> RuntimeWidgetInstanceConfiguration {
        guard let definition = configuration.definition(kind: kind) else {
            throw WindowsWidgetHostError.invalidConfiguration(
                "Windows requested unknown widget kind '\(kind)'."
            )
        }
        let configuredFamily = try definition.family(family)
        let scale = CGFloat(configuredFamily.displayScale)
        let size = CGSize(
            width: CGFloat(configuredFamily.displayWidth),
            height: CGFloat(configuredFamily.displayHeight)
        )
        return RuntimeWidgetInstanceConfiguration(
            family: family,
            isPreview: false,
            displaySize: size,
            environment: WidgetEnvironmentSnapshot(
                colorScheme: .light,
                family: family,
                displayScale: scale
            ),
            additionalEnvironments: [
                WidgetEnvironmentSnapshot(
                    colorScheme: .dark,
                    family: family,
                    displayScale: scale
                )
            ]
        )
    }
}
