import OpenFoundation
import OpenWidgetAdaptiveCards
import OpenWidgetRuntime

@MainActor
package final class WindowsWidgetRuntimeBootstrap: WidgetRuntimeBootstrap, Sendable {
    private let configurationURL: URL
    private let diagnostics: @Sendable (WindowsWidgetBridgeDiagnostic) -> Void

    package init(
        configurationURL: URL,
        diagnostics: @escaping @Sendable (WindowsWidgetBridgeDiagnostic) -> Void = {
            print("[OpenWidgetKit] bridge diagnostic \($0.code): \($0.message)")
        }
    ) {
        self.configurationURL = configurationURL
        self.diagnostics = diagnostics
    }

    package static func defaultBootstrap() throws -> WindowsWidgetRuntimeBootstrap {
        guard let executableURL = Bundle.main.executableURL else {
            throw WindowsWidgetHostError.configurationReadFailed(
                "The provider executable directory could not be resolved."
            )
        }
        return WindowsWidgetRuntimeBootstrap(
            configurationURL: executableURL
                .deletingLastPathComponent()
                .appendingPathComponent("OpenWidgetProvider.json")
        )
    }

    package func run(registry: RuntimeWidgetRegistry) async throws {
        let packageRoot = configurationURL.deletingLastPathComponent()
        let configuration = try OpenWidgetProviderConfiguration.load(
            from: configurationURL
        )
        try configuration.validate(registry: registry, packageRoot: packageRoot)

        let router = WindowsWidgetEventRouter(diagnostics: diagnostics)
        let bridge = try DynamicWindowsWidgetBridge(
            libraryPath: packageRoot
                .appendingPathComponent(configuration.provider.bridgeDLL)
                .path,
            classID: configuration.provider.classID,
            eventSink: { [router] in router.enqueue($0) },
            diagnosticSink: { [router] in router.report($0) }
        )
        let compiler = try AdaptiveCardCompiler(
            resourceResolver: ConfiguredAdaptiveCardResourceResolver(
                configuration: configuration
            )
        )
        let host = WindowsAdaptiveCardHost(compiler: compiler, bridge: bridge)
        let service = WidgetRuntimeService(
            registry: registry,
            host: host,
            diagnostics: { [diagnostics] diagnostic in
                diagnostics(
                    WindowsWidgetBridgeDiagnostic(
                        code: -3,
                        message: String(describing: diagnostic)
                    )
                )
            }
        )
        let controller = WindowsWidgetProviderController(
            configuration: configuration,
            service: service,
            bridge: bridge,
            diagnostics: diagnostics
        )
        router.install(controller)
        WidgetRuntimeComposition.installControl(service)
        defer {
            router.uninstall()
            WidgetRuntimeComposition.uninstall()
        }
        do {
            try await withTaskCancellationHandler {
                try await Task.detached {
                    try bridge.runBlocking()
                }.value
            } onCancel: { [bridge, diagnostics] in
                do {
                    try bridge.requestShutdown()
                } catch {
                    diagnostics(
                        WindowsWidgetBridgeDiagnostic(
                            code: -4,
                            message: String(describing: error)
                        )
                    )
                }
            }
        } catch {
            await service.shutdown()
            throw error
        }
        await service.shutdown()
    }
}
