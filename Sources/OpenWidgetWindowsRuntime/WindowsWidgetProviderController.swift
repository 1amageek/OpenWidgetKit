import OpenFoundation
import OpenWidgetRuntime

package actor WindowsWidgetProviderController {
    private let configuration: OpenWidgetProviderConfiguration
    private let service: WidgetRuntimeService
    private let bridge: any WindowsWidgetBridge
    private let diagnostics: @Sendable (WindowsWidgetBridgeDiagnostic) -> Void
    private var shutdownCompleted = false

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
            switch event {
            case .create(let instanceID, let kind, let family):
                try await service.createInstance(
                    id: instanceID,
                    kind: kind,
                    configuration: try instanceConfiguration(
                        kind: kind,
                        family: family
                    )
                )
            case .recover(let instanceID, let kind, let family, _):
                let existing = await service.currentConfigurations()
                    .contains { $0.instanceID == instanceID }
                if existing {
                    try await service.updateContext(
                        for: instanceID,
                        configuration: try instanceConfiguration(
                            kind: kind,
                            family: family
                        )
                    )
                } else {
                    try await service.createInstance(
                        id: instanceID,
                        kind: kind,
                        configuration: try instanceConfiguration(
                            kind: kind,
                            family: family
                        )
                    )
                }
            case .activate(let instanceID):
                guard await service.currentConfigurations().contains(where: {
                    $0.instanceID == instanceID
                }) else {
                    throw WindowsWidgetHostError.unknownInstance(instanceID)
                }
                await service.reload(instanceID: instanceID)
            case .deactivate:
                break
            case .contextChanged(let instanceID, let family):
                guard let current = await service.currentConfigurations()
                    .first(where: { $0.instanceID == instanceID }) else {
                    throw WindowsWidgetHostError.unknownInstance(instanceID)
                }
                try await service.updateContext(
                    for: instanceID,
                    configuration: try instanceConfiguration(
                        kind: current.kind,
                        family: family
                    )
                )
            case .delete(let instanceID, _):
                guard await service.currentConfigurations().contains(where: {
                    $0.instanceID == instanceID
                }) else {
                    throw WindowsWidgetHostError.unknownInstance(instanceID)
                }
                await service.deleteInstance(id: instanceID)
            case .actionInvoked(_, let verb, _, _):
                throw WindowsWidgetHostError.unsupportedAction(verb)
            case .shutdownRequested:
                try await completeShutdown()
            }
        } catch {
            diagnostics(
                WindowsWidgetBridgeDiagnostic(
                    code: -2,
                    message: String(describing: error)
                )
            )
        }
    }

    package func completeShutdown() async throws {
        guard !shutdownCompleted else { return }
        shutdownCompleted = true
        await service.shutdown()
        try bridge.completeShutdown()
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
