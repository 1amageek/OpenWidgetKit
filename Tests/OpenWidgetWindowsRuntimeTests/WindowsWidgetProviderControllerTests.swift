import OpenFoundation
import OpenWidgetRuntime
@testable import OpenWidgetWindowsRuntime
import Synchronization
import Testing

@MainActor
struct WindowsWidgetProviderControllerTests {
    @Test
    func inactiveRecoveryDefersOnlyWhenTheHostRetainedContent() async throws {
        let source = ControllerTimelineSource()
        let registry = try RuntimeWidgetRegistry(
            definitions: [makeControllerDefinition(source: source)]
        )
        let host = ControllerHost()
        let service = WidgetRuntimeService(registry: registry, host: host)
        let bridge = ControllerBridge()
        let controller = WindowsWidgetProviderController(
            configuration: controllerConfiguration(),
            service: service,
            bridge: bridge,
            diagnostics: { _ in }
        )

        await controller.handle(
            .recover(
                instanceID: "instance",
                kind: "fixture",
                family: .systemSmall,
                isActive: false,
                hasRetainedHostContent: true
            )
        )
        for _ in 0..<20 { await Task.yield() }
        let recoveredRequestCount = await source.requestCount
        #expect(recoveredRequestCount == 0)

        await controller.handle(.activate(instanceID: "instance"))
        try await waitForControllerCondition { await source.requestCount == 1 }
        await controller.handle(.deactivate(instanceID: "instance"))

        await controller.handle(
            .recover(
                instanceID: "missing-content",
                kind: "fixture",
                family: .systemSmall,
                isActive: false,
                hasRetainedHostContent: false
            )
        )
        try await waitForControllerCondition { await source.requestCount == 2 }

        let invalidations = await host.invalidations
        #expect(invalidations == [1, 2, 1])
        await service.shutdown()
    }

    @Test
    func shutdownCompletionIsRetryableUntilTheBridgeAcceptsIt() async throws {
        let source = ControllerTimelineSource()
        let registry = try RuntimeWidgetRegistry(
            definitions: [makeControllerDefinition(source: source)]
        )
        let service = WidgetRuntimeService(
            registry: registry,
            host: ControllerHost()
        )
        let bridge = ControllerBridge(failFirstShutdownCompletion: true)
        let controller = WindowsWidgetProviderController(
            configuration: controllerConfiguration(),
            service: service,
            bridge: bridge,
            diagnostics: { _ in }
        )

        await #expect(throws: WindowsWidgetHostError.self) {
            try await controller.completeShutdown()
        }
        try await controller.completeShutdown()
        try await controller.completeShutdown()

        #expect(bridge.shutdownCompletionCount == 2)
    }

    @Test
    func concurrentShutdownRequestsShareTheSameCleanup() async throws {
        let source = ControllerTimelineSource()
        let registry = try RuntimeWidgetRegistry(
            definitions: [makeControllerDefinition(source: source)]
        )
        let host = SuspendingRemovalControllerHost()
        let service = WidgetRuntimeService(registry: registry, host: host)
        try await service.createInstance(
            id: "instance",
            kind: "fixture",
            configuration: controllerInstanceConfiguration(),
            isActive: false
        )
        let bridge = ControllerBridge()
        let controller = WindowsWidgetProviderController(
            configuration: controllerConfiguration(),
            service: service,
            bridge: bridge,
            diagnostics: { _ in }
        )

        let first = Task { try await controller.completeShutdown() }
        try await waitForControllerCondition { await host.hasSuspendedRemoval }
        let second = Task { try await controller.completeShutdown() }
        for _ in 0..<20 { await Task.yield() }
        #expect(bridge.shutdownCompletionCount == 0)

        await host.releaseRemoval()
        try await first.value
        try await second.value
        #expect(bridge.shutdownCompletionCount == 1)
    }

    private func makeControllerDefinition(
        source: ControllerTimelineSource
    ) -> RuntimeWidgetDefinition {
        RuntimeWidgetDefinition(kind: "fixture") { _, _, _ in
            try await source.timeline()
        }
    }

    private func controllerConfiguration() -> OpenWidgetProviderConfiguration {
        OpenWidgetProviderConfiguration(
            schemaVersion: 3,
            build: WindowsWidgetBuildConfiguration(
                swiftSnapshot: "snapshot",
                swiftToolchainIdentifier: "toolchain",
                windowsAppSDKVersion: "2.3.1",
                widgetsPackageVersion: "2.0.5",
                cppWinRTVersion: "2.0.230706.1",
                visualCToolset: "v143",
                windowsSDKVersion: "10.0.26100.0",
                foundationLinkMode: "dynamic"
            ),
            provider: WindowsWidgetProviderIdentity(
                packageName: "OpenWidgetKit.Tests",
                publisher: "CN=Tests",
                version: "1.0.0.0",
                architecture: "x64",
                applicationID: "Tests",
                executable: "Tests.exe",
                bridgeDLL: "Bridge.dll",
                classID: "{E7B2A965-16F5-49D8-9F30-3541DAA57131}",
                extensionID: "Tests",
                displayName: "Tests",
                square44Logo: "Assets/44.png",
                square150Logo: "Assets/150.png",
                storeLogo: "Assets/Store.png"
            ),
            definitions: [
                WindowsWidgetDefinitionConfiguration(
                    kind: "fixture",
                    displayName: "Fixture",
                    description: "Fixture",
                    icon: "Assets/Icon.png",
                    screenshot: "Assets/Screenshot.png",
                    families: [
                        WindowsWidgetFamilyConfiguration(
                            name: "small",
                            displayWidth: 158,
                            displayHeight: 158,
                            displayScale: 1
                        )
                    ]
                )
            ],
            resources: []
        )
    }

    private func controllerInstanceConfiguration() -> RuntimeWidgetInstanceConfiguration {
        RuntimeWidgetInstanceConfiguration(
            family: .systemSmall,
            isPreview: false,
            displaySize: CGSize(width: 158, height: 158),
            environment: WidgetEnvironmentSnapshot(family: .systemSmall)
        )
    }

    private func waitForControllerCondition(
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<2_000 {
            if await condition() { return }
            await Task.yield()
        }
        throw ControllerTestFailure.conditionNotReached
    }
}

private actor ControllerTimelineSource {
    private(set) var requestCount = 0

    func timeline() throws -> RuntimeTimeline {
        requestCount += 1
        let document = WidgetDocument(
            root: WidgetNode(
                id: WidgetNodeID(components: [.role("text")]),
                kind: .text(WidgetText(storage: .verbatim("value")))
            ),
            environment: WidgetEnvironmentSnapshot(family: .systemSmall)
        )
        return try RuntimeTimeline(
            entries: [
                RuntimeTimelineEntry(
                    date: Date(timeIntervalSince1970: 0),
                    document: document
                )
            ],
            reloadPolicy: .never
        )
    }
}

private actor ControllerHost: RuntimeWidgetHost {
    private(set) var invalidations: [UInt64] = []

    func invalidate(instanceID: String, generation: UInt64) {
        invalidations.append(generation)
    }

    func apply(_ update: RuntimeWidgetUpdate) {}

    func remove(instanceID: String, generation: UInt64) {}
}

private actor SuspendingRemovalControllerHost: RuntimeWidgetHost {
    private var removalContinuation: CheckedContinuation<Void, Never>?

    var hasSuspendedRemoval: Bool {
        removalContinuation != nil
    }

    func invalidate(instanceID: String, generation: UInt64) {}
    func apply(_ update: RuntimeWidgetUpdate) {}

    func remove(instanceID: String, generation: UInt64) async {
        await withCheckedContinuation { continuation in
            removalContinuation = continuation
        }
    }

    func releaseRemoval() {
        removalContinuation?.resume()
        removalContinuation = nil
    }
}

private final class ControllerBridge: WindowsWidgetBridge, Sendable {
    private struct State: Sendable {
        var shutdownCompletionCount = 0
        var failFirstShutdownCompletion: Bool
    }

    private let state: Mutex<State>

    var shutdownCompletionCount: Int {
        state.withLock { $0.shutdownCompletionCount }
    }

    init(failFirstShutdownCompletion: Bool = false) {
        state = Mutex(
            State(
                failFirstShutdownCompletion: failFirstShutdownCompletion
            )
        )
    }

    func runBlocking() throws {}
    func requestShutdown() throws {}

    func completeShutdown() throws {
        let shouldFail = state.withLock { state in
            state.shutdownCompletionCount += 1
            guard state.failFirstShutdownCompletion else { return false }
            state.failFirstShutdownCompletion = false
            return true
        }
        if shouldFail {
            throw WindowsWidgetHostError.hostRejected(
                code: 5,
                message: "The shutdown signal failed."
            )
        }
    }

    func invalidate(instanceID: String, generation: UInt64) throws {}

    func update(
        instanceID: String,
        generation: UInt64,
        templateJSON: String?,
        dataJSON: String,
        customState: String
    ) throws {}

    func remove(instanceID: String, generation: UInt64) throws {}
}

private enum ControllerTestFailure: Error {
    case conditionNotReached
}
