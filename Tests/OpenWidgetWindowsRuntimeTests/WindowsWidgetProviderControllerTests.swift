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
        let service = WidgetRuntimeService(
            registry: registry,
            host: host,
            diagnostics: { _ in }
        )
        let bridge = ControllerBridge()
        let controller = WindowsWidgetProviderController(
            configuration: controllerConfiguration(),
            service: service,
            bridge: bridge,
            actionHost: ControllerActionHost(),
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
            host: ControllerHost(),
            diagnostics: { _ in }
        )
        let bridge = ControllerBridge(failFirstShutdownCompletion: true)
        let controller = WindowsWidgetProviderController(
            configuration: controllerConfiguration(),
            service: service,
            bridge: bridge,
            actionHost: ControllerActionHost(),
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
        let service = WidgetRuntimeService(
            registry: registry,
            host: host,
            diagnostics: { _ in }
        )
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
            actionHost: ControllerActionHost(),
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

    @Test
    func successfulActionRequestsTheNextTimelineGeneration() async throws {
        let source = ControllerTimelineSource()
        let registry = try RuntimeWidgetRegistry(
            definitions: [makeControllerDefinition(source: source)]
        )
        let host = ControllerHost()
        let service = WidgetRuntimeService(
            registry: registry,
            host: host,
            diagnostics: { _ in }
        )
        let actionHost = ControllerActionHost(generation: 1)
        let controller = WindowsWidgetProviderController(
            configuration: controllerConfiguration(),
            service: service,
            bridge: ControllerBridge(),
            actionHost: actionHost,
            diagnostics: { _ in }
        )

        await controller.handle(
            .create(
                instanceID: "instance",
                kind: "fixture",
                family: .systemSmall,
                isActive: true
            )
        )
        try await waitForControllerCondition { await source.requestCount == 1 }
        await controller.handle(
            .actionInvoked(
                instanceID: "instance",
                verb: "action",
                data: #"{"openWidgetActionID":"action"}"#,
                customState: "state"
            )
        )
        try await waitForControllerCondition { await source.requestCount == 2 }

        #expect(await actionHost.invocationCount == 1)
        #expect(await host.invalidations == [1, 2])
        await service.shutdown()
    }

    @Test
    func failedActionDoesNotRequestAnotherTimeline() async throws {
        let source = ControllerTimelineSource()
        let registry = try RuntimeWidgetRegistry(
            definitions: [makeControllerDefinition(source: source)]
        )
        let host = ControllerHost()
        let service = WidgetRuntimeService(
            registry: registry,
            host: host,
            diagnostics: { _ in }
        )
        let actionHost = FailingControllerActionHost()
        let controller = WindowsWidgetProviderController(
            configuration: controllerConfiguration(),
            service: service,
            bridge: ControllerBridge(),
            actionHost: actionHost,
            diagnostics: { _ in }
        )

        await controller.handle(
            .create(
                instanceID: "instance",
                kind: "fixture",
                family: .systemSmall,
                isActive: true
            )
        )
        try await waitForControllerCondition { await source.requestCount == 1 }
        await controller.handle(
            .actionInvoked(
                instanceID: "instance",
                verb: "action",
                data: #"{"openWidgetActionID":"action"}"#,
                customState: "state"
            )
        )

        try await waitForControllerCondition {
            await actionHost.completionCount == 1
        }
        #expect(await actionHost.invocationCount == 1)
        #expect(await source.requestCount == 1)
        #expect(await host.invalidations == [1])
        await service.shutdown()
    }

    @Test
    func suspendedActionDoesNotBlockAFollowingDelete() async throws {
        let source = ControllerTimelineSource()
        let registry = try RuntimeWidgetRegistry(
            definitions: [makeControllerDefinition(source: source)]
        )
        let host = ControllerHost()
        let service = WidgetRuntimeService(
            registry: registry,
            host: host,
            diagnostics: { _ in }
        )
        let actionHost = SuspendingControllerActionHost()
        let controller = WindowsWidgetProviderController(
            configuration: controllerConfiguration(),
            service: service,
            bridge: ControllerBridge(),
            actionHost: actionHost,
            diagnostics: { _ in }
        )
        await controller.handle(
            .create(
                instanceID: "instance",
                kind: "fixture",
                family: .systemSmall,
                isActive: true
            )
        )
        try await waitForControllerCondition { await source.requestCount == 1 }

        await controller.handle(
            .actionInvoked(
                instanceID: "instance",
                verb: "action",
                data: #"{"openWidgetActionID":"action"}"#,
                customState: "state"
            )
        )
        try await waitForControllerCondition { await actionHost.isWaiting }
        await controller.handle(
            .delete(instanceID: "instance", customState: "state")
        )

        #expect(await service.currentConfigurations().isEmpty)
        #expect(await host.removals == [2])
        await actionHost.release()
        try await waitForControllerCondition { await actionHost.didComplete }
        #expect(await source.requestCount == 1)
        #expect(await host.invalidations == [1])
    }

    @Test
    func suspendedActionDoesNotBlockAFollowingShutdown() async throws {
        let source = ControllerTimelineSource()
        let registry = try RuntimeWidgetRegistry(
            definitions: [makeControllerDefinition(source: source)]
        )
        let host = ControllerHost()
        let service = WidgetRuntimeService(
            registry: registry,
            host: host,
            diagnostics: { _ in }
        )
        let actionHost = SuspendingControllerActionHost()
        let bridge = ControllerBridge()
        let controller = WindowsWidgetProviderController(
            configuration: controllerConfiguration(),
            service: service,
            bridge: bridge,
            actionHost: actionHost,
            diagnostics: { _ in }
        )
        await controller.handle(
            .create(
                instanceID: "instance",
                kind: "fixture",
                family: .systemSmall,
                isActive: true
            )
        )
        try await waitForControllerCondition { await source.requestCount == 1 }
        await controller.handle(
            .actionInvoked(
                instanceID: "instance",
                verb: "action",
                data: #"{"openWidgetActionID":"action"}"#,
                customState: "state"
            )
        )
        try await waitForControllerCondition { await actionHost.isWaiting }

        await controller.handle(.shutdownRequested)

        #expect(bridge.shutdownCompletionCount == 1)
        #expect(await service.currentConfigurations().isEmpty)
        #expect(await host.removals == [2])
        await actionHost.release()
        try await waitForControllerCondition { await actionHost.didComplete }
        #expect(await source.requestCount == 1)
        #expect(await host.invalidations == [1])
    }

    @Test
    func eventIngressOverflowRejectsFurtherEventsAndDrainsToShutdown() async throws {
        let source = ControllerTimelineSource()
        let registry = try RuntimeWidgetRegistry(
            definitions: [makeControllerDefinition(source: source)]
        )
        let host = ControllerHost()
        let diagnostics = WindowsDiagnosticRecorder()
        let service = WidgetRuntimeService(
            registry: registry,
            host: host,
            diagnostics: { diagnostic in
                diagnostics.record(.runtime(diagnostic))
            }
        )
        let bridge = ControllerBridge()
        let overflowCounter = OverflowCounter()
        let router = try WindowsWidgetEventRouter(
            maximumPendingEventCount: 1,
            diagnostics: diagnostics.record
        )
        router.installOverflowHandler(overflowCounter.increment)
        router.enqueue(
            .recover(
                instanceID: "instance",
                kind: "fixture",
                family: .systemSmall,
                isActive: false,
                hasRetainedHostContent: true
            )
        )
        router.enqueue(.activate(instanceID: "rejected"))
        router.enqueue(.delete(instanceID: "also-rejected", customState: ""))

        let controller = WindowsWidgetProviderController(
            configuration: controllerConfiguration(),
            service: service,
            bridge: bridge,
            actionHost: ControllerActionHost(),
            diagnostics: diagnostics.record
        )
        router.install(controller)
        defer { router.uninstall() }
        try await waitForControllerCondition {
            bridge.shutdownCompletionCount == 1
        }

        #expect(overflowCounter.value == 1)
        #expect(diagnostics.values.count == 1)
        #expect(
            diagnostics.values.first?.cause == .eventQueueOverflow(
                capacity: 1
            )
        )
        #expect(await source.requestCount == 0)
        #expect(await service.currentConfigurations().isEmpty)
    }

    @Test
    func diagnosticRenderingNeverIncludesHostMessagesOrActionPayloads() {
        let diagnostic = WindowsWidgetDiagnostic.providerEventFailure(
            event: .actionInvoked(
                instanceID: "instance",
                verb: "private-verb",
                data: "private-data",
                customState: "private-state"
            ),
            kind: "fixture",
            generation: 7,
            error: WindowsWidgetHostError.hostRejected(
                code: 19,
                message: "private-host-message"
            )
        )

        #expect(diagnostic.cause == .host(.hostRejected))
        #expect(!diagnostic.renderedMessage.contains("private-verb"))
        #expect(!diagnostic.renderedMessage.contains("private-data"))
        #expect(!diagnostic.renderedMessage.contains("private-state"))
        #expect(!diagnostic.renderedMessage.contains("private-host-message"))
        #expect(diagnostic.renderedMessage.contains("instance=instance"))
        #expect(diagnostic.renderedMessage.contains("generation=7"))
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
            schemaVersion: 5,
            build: WindowsWidgetBuildConfiguration(
                swiftSnapshot: "snapshot",
                swiftToolchainIdentifier: "toolchain",
                windowsAppSDKVersion: "2.3.1",
                widgetsPackageVersion: "2.0.5",
                cppWinRTVersion: "2.0.230706.1",
                wixToolsetSDKVersion: "4.0.5",
                windowsAppRuntimePackageName: "Microsoft.WindowsAppRuntime.2",
                windowsAppRuntimePublisher: "CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US",
                windowsAppRuntimeMinVersion: "2.3.1.0",
                visualCToolset: "v145",
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
    private(set) var removals: [UInt64] = []

    func invalidate(instanceID: String, generation: UInt64) {
        invalidations.append(generation)
    }

    func apply(_ update: RuntimeWidgetUpdate) {}

    func remove(instanceID: String, generation: UInt64) {
        removals.append(generation)
    }
}

private actor ControllerActionHost: WindowsWidgetActionHost {
    private let generation: UInt64
    private(set) var invocationCount = 0

    init(generation: UInt64 = 1) {
        self.generation = generation
    }

    func beginAction(
        instanceID: String,
        verb: String,
        data: String,
        customState: String
    ) -> WindowsWidgetActionExecution {
        invocationCount += 1
        let acceptedGeneration = generation
        return WindowsWidgetActionExecution { acceptedGeneration }
    }
}

private actor FailingControllerActionHost: WindowsWidgetActionHost {
    private(set) var invocationCount = 0
    private(set) var completionCount = 0

    func beginAction(
        instanceID: String,
        verb: String,
        data: String,
        customState: String
    ) -> WindowsWidgetActionExecution {
        invocationCount += 1
        return WindowsWidgetActionExecution { [self] in
            await recordCompletion()
            throw ControllerActionFailure.rejected
        }
    }

    private func recordCompletion() {
        completionCount += 1
    }
}

private actor SuspendingControllerActionHost: WindowsWidgetActionHost {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var didComplete = false

    var isWaiting: Bool { continuation != nil }

    func beginAction(
        instanceID: String,
        verb: String,
        data: String,
        customState: String
    ) -> WindowsWidgetActionExecution {
        WindowsWidgetActionExecution { [self] in
            await waitForRelease()
            await recordCompletion()
            return 1
        }
    }

    private func waitForRelease() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    private func recordCompletion() {
        didComplete = true
    }
}

private enum ControllerActionFailure: Error {
    case rejected
}

private final class WindowsDiagnosticRecorder: Sendable {
    private let storage = Mutex<[WindowsWidgetDiagnostic]>([])

    var values: [WindowsWidgetDiagnostic] {
        storage.withLock { $0 }
    }

    func record(_ diagnostic: WindowsWidgetDiagnostic) {
        storage.withLock { $0.append(diagnostic) }
    }
}

private final class OverflowCounter: Sendable {
    private let storage = Mutex(0)

    var value: Int {
        storage.withLock { $0 }
    }

    func increment() {
        storage.withLock { $0 += 1 }
    }
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
