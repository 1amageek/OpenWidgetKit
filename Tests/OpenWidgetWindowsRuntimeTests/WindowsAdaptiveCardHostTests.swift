import OpenFoundation
import OpenWidgetAdaptiveCards
import OpenWidgetRuntime
@testable import OpenWidgetWindowsRuntime
import Synchronization
import Testing

private struct EmptyResourceResolver: AdaptiveCardResourceResolving {
    func resolve(_ resource: WidgetResource) throws -> String {
        throw AdaptiveCardCompilationError.unresolvedResource(
            "The text-only fixture does not contain resources."
        )
    }
}

private final class RecordingWindowsBridge: WindowsWidgetBridge, Sendable {
    struct Update: Equatable, Sendable {
        let instanceID: String
        let generation: UInt64
        let templateJSON: String?
        let dataJSON: String
        let customState: String
    }

    private let updates = Mutex<[Update]>([])

    var recordedUpdates: [Update] {
        updates.withLock { $0 }
    }

    func runBlocking() throws {}
    func requestShutdown() throws {}
    func completeShutdown() throws {}
    func invalidate(instanceID: String, generation: UInt64) throws {}
    func remove(instanceID: String, generation: UInt64) throws {}

    func update(
        instanceID: String,
        generation: UInt64,
        templateJSON: String?,
        dataJSON: String,
        customState: String
    ) throws {
        updates.withLock {
            $0.append(
                Update(
                    instanceID: instanceID,
                    generation: generation,
                    templateJSON: templateJSON,
                    dataJSON: dataJSON,
                    customState: customState
                )
            )
        }
    }
}

private final class RejectingTransitionWindowsBridge: WindowsWidgetBridge, Sendable {
    private struct State: Sendable {
        var shouldRejectInvalidation = false
        var shouldRejectRemoval = true
    }

    private let state = Mutex(State())

    func runBlocking() throws {}
    func requestShutdown() throws {}
    func completeShutdown() throws {}
    func invalidate(instanceID: String, generation: UInt64) throws {
        let rejects = state.withLock { state in
            defer { state.shouldRejectInvalidation = false }
            return state.shouldRejectInvalidation
        }
        if rejects {
            throw WindowsWidgetHostError.hostRejected(
                code: 5,
                message: "The invalidation transition was rejected."
            )
        }
    }
    func update(
        instanceID: String,
        generation: UInt64,
        templateJSON: String?,
        dataJSON: String,
        customState: String
    ) throws {}

    func remove(instanceID: String, generation: UInt64) throws {
        let rejects = state.withLock { state in
            defer { state.shouldRejectRemoval = false }
            return state.shouldRejectRemoval
        }
        if rejects {
            throw WindowsWidgetHostError.hostRejected(
                code: 5,
                message: "The removal transition was rejected."
            )
        }
    }

    func rejectNextInvalidation() {
        state.withLock { $0.shouldRejectInvalidation = true }
    }
}

private final class RejectingUpdateWindowsBridge: WindowsWidgetBridge, Sendable {
    private struct State: Sendable {
        var rejectsNextUpdate = true
        var requestedCustomStates: [String] = []
        var acceptedCustomStates: [String] = []
    }

    private let state = Mutex(State())

    var requestedCustomStates: [String] {
        state.withLock { $0.requestedCustomStates }
    }

    var acceptedCustomStates: [String] {
        state.withLock { $0.acceptedCustomStates }
    }

    func runBlocking() throws {}
    func requestShutdown() throws {}
    func completeShutdown() throws {}
    func invalidate(instanceID: String, generation: UInt64) throws {}
    func remove(instanceID: String, generation: UInt64) throws {}

    func update(
        instanceID: String,
        generation: UInt64,
        templateJSON: String?,
        dataJSON: String,
        customState: String
    ) throws {
        let rejects = state.withLock { state in
            state.requestedCustomStates.append(customState)
            guard state.rejectsNextUpdate else {
                state.acceptedCustomStates.append(customState)
                return false
            }
            state.rejectsNextUpdate = false
            return true
        }
        if rejects {
            throw WindowsWidgetHostError.hostRejected(
                code: 5,
                message: "The update was rejected."
            )
        }
    }
}

struct WindowsAdaptiveCardHostTests {
    @Test
    func rejectsStaleUpdateBeforeCallingTheBridge() async throws {
        let bridge = RecordingWindowsBridge()
        let host = try makeHost(bridge: bridge)
        try await host.invalidate(instanceID: "instance", generation: 2)

        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.apply(makeUpdate(generation: 1))
        }
        #expect(bridge.recordedUpdates.isEmpty)

        try await host.apply(makeUpdate(generation: 2))
        #expect(bridge.recordedUpdates.map(\.generation) == [2])
    }

    @Test
    func deletionFencesOldLifetimeAndRecreationSendsACompleteTemplate() async throws {
        let bridge = RecordingWindowsBridge()
        let host = try makeHost(bridge: bridge)
        try await host.invalidate(instanceID: "instance", generation: 1)
        try await host.apply(makeUpdate(generation: 1))
        try await host.remove(instanceID: "instance", generation: 2)

        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.invalidate(instanceID: "instance", generation: 2)
        }
        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.apply(makeUpdate(generation: 1))
        }
        try await host.invalidate(instanceID: "instance", generation: 3)
        try await host.apply(makeUpdate(generation: 3))

        #expect(bridge.recordedUpdates.map(\.generation) == [1, 3])
        #expect(bridge.recordedUpdates.allSatisfy { $0.templateJSON != nil })
    }

    @Test
    func rejectedRemovalKeepsTheSwiftFenceFailClosed() async throws {
        let bridge = RejectingTransitionWindowsBridge()
        let host = WindowsAdaptiveCardHost(
            compiler: try AdaptiveCardCompiler(
                resourceResolver: EmptyResourceResolver()
            ),
            bridge: bridge
        )
        try await host.invalidate(instanceID: "instance", generation: 1)

        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.remove(instanceID: "instance", generation: 2)
        }
        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.apply(makeUpdate(generation: 1))
        }
        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.invalidate(instanceID: "instance", generation: 2)
        }
        try await host.remove(instanceID: "instance", generation: 2)
    }

    @Test
    func rejectedRecreationInvalidationDoesNotOpenTheSwiftFence() async throws {
        let bridge = RejectingTransitionWindowsBridge()
        let host = WindowsAdaptiveCardHost(
            compiler: try AdaptiveCardCompiler(
                resourceResolver: EmptyResourceResolver()
            ),
            bridge: bridge
        )
        try await host.invalidate(instanceID: "instance", generation: 1)
        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.remove(instanceID: "instance", generation: 2)
        }
        try await host.remove(instanceID: "instance", generation: 2)
        bridge.rejectNextInvalidation()

        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.invalidate(instanceID: "instance", generation: 3)
        }
        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.apply(makeUpdate(generation: 3))
        }
        try await host.invalidate(instanceID: "instance", generation: 3)
    }

    @Test
    func sendsDataOnlyAfterTheInstanceAcceptsTheSameStructure() async throws {
        let bridge = RecordingWindowsBridge()
        let host = try makeHost(bridge: bridge)
        try await host.invalidate(instanceID: "instance", generation: 1)
        try await host.apply(
            makeUpdate(generation: 1, lightText: "First", darkText: "First dark")
        )
        try await host.invalidate(instanceID: "instance", generation: 2)
        try await host.apply(
            makeUpdate(generation: 2, lightText: "Second", darkText: "Second dark")
        )

        let updates = bridge.recordedUpdates
        #expect(updates.count == 2)
        let first = try #require(updates.first)
        let second = try #require(updates.last)
        #expect(first.templateJSON != nil)
        #expect(second.templateJSON == nil)
        #expect(first.dataJSON != second.dataJSON)
    }

    @Test
    func publishesActionsOnlyAfterUpdateAcceptanceAndNeverReusesARevision() async throws {
        let bridge = RejectingUpdateWindowsBridge()
        let host = WindowsAdaptiveCardHost(
            compiler: try AdaptiveCardCompiler(
                resourceResolver: EmptyResourceResolver()
            ),
            bridge: bridge
        )
        let counter = ActionCounter()
        let fixture = makeActionUpdate(generation: 1) {
            await counter.increment()
        }
        try await host.invalidate(instanceID: "instance", generation: 1)

        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.apply(fixture.update)
        }
        let rejectedState = try #require(bridge.requestedCustomStates.last)
        await #expect(throws: WindowsWidgetHostError.staleAction(
            instanceID: "instance",
            verb: fixture.verb
        )) {
            try await host.performAction(
                instanceID: "instance",
                verb: fixture.verb,
                data: fixture.dataJSON,
                customState: rejectedState
            )
        }
        #expect(await counter.value == 0)

        try await host.apply(fixture.update)
        let acceptedState = try #require(bridge.acceptedCustomStates.last)
        #expect(acceptedState != rejectedState)
        _ = try await host.performAction(
            instanceID: "instance",
            verb: fixture.verb,
            data: fixture.dataJSON,
            customState: acceptedState
        )
        #expect(await counter.value == 1)
    }

    @Test
    func scopesAcceptedActionStateToItsWidgetInstance() async throws {
        let bridge = RecordingWindowsBridge()
        let host = try makeHost(
            bridge: bridge,
            actionSessionID: "fixture-session"
        )
        let first = makeActionUpdate(instanceID: "first", generation: 1) {}
        let second = makeActionUpdate(instanceID: "second", generation: 1) {}
        try await host.invalidate(instanceID: "first", generation: 1)
        try await host.invalidate(instanceID: "second", generation: 1)
        try await host.apply(first.update)
        try await host.apply(second.update)
        let firstState = try #require(
            bridge.recordedUpdates.first { $0.instanceID == "first" }?.customState
        )
        let secondState = try #require(
            bridge.recordedUpdates.first { $0.instanceID == "second" }?.customState
        )

        #expect(firstState != secondState)
        await #expect(throws: WindowsWidgetHostError.staleAction(
            instanceID: "second",
            verb: second.verb
        )) {
            try await host.performAction(
                instanceID: "second",
                verb: second.verb,
                data: second.dataJSON,
                customState: firstState
            )
        }
    }

    @Test
    func scopesAcceptedActionStateToItsProviderSession() async throws {
        let bridge = RecordingWindowsBridge()
        let firstHost = try makeHost(
            bridge: bridge,
            actionSessionID: "first-session"
        )
        let fixture = makeActionUpdate(generation: 1) {}
        try await firstHost.invalidate(instanceID: "instance", generation: 1)
        try await firstHost.apply(fixture.update)
        let firstState = try #require(bridge.recordedUpdates.last?.customState)

        let restartedHost = try makeHost(
            bridge: bridge,
            actionSessionID: "second-session"
        )
        try await restartedHost.invalidate(instanceID: "instance", generation: 1)
        try await restartedHost.apply(fixture.update)
        let restartedState = try #require(bridge.recordedUpdates.last?.customState)

        #expect(firstState != restartedState)
        await #expect(throws: WindowsWidgetHostError.staleAction(
            instanceID: "instance",
            verb: fixture.verb
        )) {
            try await restartedHost.performAction(
                instanceID: "instance",
                verb: fixture.verb,
                data: fixture.dataJSON,
                customState: firstState
            )
        }
    }

    @Test
    func executesOnlyTheActionAcceptedForTheCurrentGeneration() async throws {
        let bridge = RecordingWindowsBridge()
        let host = try makeHost(bridge: bridge)
        let counter = ActionCounter()
        let fixture = makeActionUpdate(generation: 1) {
            await counter.increment()
        }
        try await host.invalidate(instanceID: "instance", generation: 1)
        try await host.apply(fixture.update)
        let acceptedState = try #require(bridge.recordedUpdates.last?.customState)

        let generation = try await host.performAction(
            instanceID: "instance",
            verb: fixture.verb,
            data: #"{ "openWidgetActionID" : "\#(fixture.verb)" }"#,
            customState: acceptedState
        )

        #expect(generation == 1)
        #expect(await counter.value == 1)
        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.performAction(
                instanceID: "instance",
                verb: "unknown",
                data: fixture.dataJSON,
                customState: acceptedState
            )
        }
        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.performAction(
                instanceID: "instance",
                verb: fixture.verb,
                data: "{}",
                customState: acceptedState
            )
        }
        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.performAction(
                instanceID: "instance",
                verb: fixture.verb,
                data: fixture.dataJSON,
                customState: "stale-state"
            )
        }

        try await host.apply(fixture.update)
        let nextEntryState = try #require(
            bridge.recordedUpdates.last?.customState
        )
        #expect(nextEntryState != acceptedState)
        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.performAction(
                instanceID: "instance",
                verb: fixture.verb,
                data: fixture.dataJSON,
                customState: acceptedState
            )
        }
        _ = try await host.performAction(
            instanceID: "instance",
            verb: fixture.verb,
            data: fixture.dataJSON,
            customState: nextEntryState
        )
        #expect(await counter.value == 2)
    }

    @Test
    func rejectsDuplicateAndGenerationChangingActionReentrancy() async throws {
        let bridge = RecordingWindowsBridge()
        let host = try makeHost(bridge: bridge)
        let gate = SuspendingActionGate()
        let fixture = makeActionUpdate(generation: 1) {
            await gate.wait()
        }
        try await host.invalidate(instanceID: "instance", generation: 1)
        try await host.apply(fixture.update)
        let acceptedState = try #require(bridge.recordedUpdates.last?.customState)
        let first = Task {
            try await host.performAction(
                instanceID: "instance",
                verb: fixture.verb,
                data: fixture.dataJSON,
                customState: acceptedState
            )
        }
        try await waitForHostCondition { await gate.isWaiting }

        await #expect(throws: WindowsWidgetHostError.self) {
            try await host.performAction(
                instanceID: "instance",
                verb: fixture.verb,
                data: fixture.dataJSON,
                customState: acceptedState
            )
        }
        await #expect(throws: WindowsWidgetHostError.duplicateAction(
            instanceID: "instance",
            verb: fixture.alternateVerb
        )) {
            try await host.performAction(
                instanceID: "instance",
                verb: fixture.alternateVerb,
                data: fixture.alternateDataJSON,
                customState: acceptedState
            )
        }
        try await host.invalidate(instanceID: "instance", generation: 2)
        await gate.release()
        await #expect(throws: WindowsWidgetHostError.self) {
            try await first.value
        }
    }

    @Test
    func suspendedActionExecutionDoesNotRetainTheProviderHost() async throws {
        let bridge = RecordingWindowsBridge()
        var host: WindowsAdaptiveCardHost? = try makeHost(bridge: bridge)
        let gate = SuspendingActionGate()
        let fixture = makeActionUpdate(generation: 1) {
            await gate.wait()
        }
        try await host?.invalidate(instanceID: "instance", generation: 1)
        try await host?.apply(fixture.update)
        let acceptedState = try #require(bridge.recordedUpdates.last?.customState)
        let execution = try await host?.beginAction(
            instanceID: "instance",
            verb: fixture.verb,
            data: fixture.dataJSON,
            customState: acceptedState
        )
        let acceptedExecution = try #require(execution)
        try await waitForHostCondition { await gate.isWaiting }
        weak let retainedHost = host

        host = nil

        #expect(retainedHost == nil)
        await gate.release()
        await #expect(throws: WindowsWidgetHostError.shuttingDown) {
            try await acceptedExecution.value()
        }
    }

    @Test
    func failedActionCanBeRetriedWithoutReportingSuccess() async throws {
        let bridge = RecordingWindowsBridge()
        let host = try makeHost(bridge: bridge)
        let attempts = FailingActionAttempts()
        let fixture = makeActionUpdate(generation: 1) {
            try await attempts.reject()
        }
        try await host.invalidate(instanceID: "instance", generation: 1)
        try await host.apply(fixture.update)
        let acceptedState = try #require(bridge.recordedUpdates.last?.customState)

        for _ in 0..<2 {
            await #expect(throws: FixtureActionFailure.self) {
                try await host.performAction(
                    instanceID: "instance",
                    verb: fixture.verb,
                    data: fixture.dataJSON,
                    customState: acceptedState
                )
            }
        }

        #expect(await attempts.count == 2)
    }

    private func makeHost(
        bridge: RecordingWindowsBridge,
        actionSessionID: String = "fixture-session"
    ) throws -> WindowsAdaptiveCardHost {
        WindowsAdaptiveCardHost(
            compiler: try AdaptiveCardCompiler(
                resourceResolver: EmptyResourceResolver()
            ),
            bridge: bridge,
            actionSessionID: actionSessionID
        )
    }

    private func makeUpdate(
        generation: UInt64,
        lightText: String = "Light",
        darkText: String = "Dark"
    ) -> RuntimeWidgetUpdate {
        let light = makeDocument(theme: .light, text: lightText)
        let dark = makeDocument(theme: .dark, text: darkText)
        return RuntimeWidgetUpdate(
            instanceID: "instance",
            kind: "fixture",
            family: .systemSmall,
            generation: generation,
            entry: RuntimeTimelineEntry(
                date: Date(timeIntervalSince1970: 0),
                document: light,
                additionalDocuments: [dark]
            )
        )
    }

    private func makeDocument(
        theme: WidgetEnvironmentSnapshot.ColorScheme,
        text: String
    ) -> WidgetDocument {
        let textNode = WidgetNode(
            id: WidgetNodeID(components: [.role("text")]),
            kind: .text(WidgetText(storage: .verbatim(text)))
        )
        return WidgetDocument(
            root: WidgetNode(
                id: WidgetNodeID(components: [.role("root")]),
                kind: .group,
                children: [textNode]
            ),
            environment: WidgetEnvironmentSnapshot(
                colorScheme: theme,
                family: .systemSmall
            )
        )
    }

    private func makeActionUpdate(
        instanceID: String = "instance",
        generation: UInt64,
        operation: @escaping @Sendable () async throws -> Void
    ) -> (
        update: RuntimeWidgetUpdate,
        verb: String,
        dataJSON: String,
        alternateVerb: String,
        alternateDataJSON: String
    ) {
        let nodeID = WidgetNodeID(components: [.role("action")])
        let actionID = WidgetActionID(nodeID: nodeID)
        let action = WidgetAction(
            id: actionID,
            handlerIdentity: "FixtureIntent",
            operation: operation
        )
        let light = makeActionDocument(
            theme: .light,
            nodeID: nodeID,
            action: action
        )
        let dark = makeActionDocument(
            theme: .dark,
            nodeID: nodeID,
            action: action
        )
        let lightVerb = "\(actionID.rawValue)|theme:light"
        let darkVerb = "\(actionID.rawValue)|theme:dark"
        return (
            RuntimeWidgetUpdate(
                instanceID: instanceID,
                kind: "fixture",
                family: .systemSmall,
                generation: generation,
                entry: RuntimeTimelineEntry(
                    date: Date(timeIntervalSince1970: 0),
                    document: light,
                    additionalDocuments: [dark]
                )
            ),
            lightVerb,
            #"{"openWidgetActionID":"\#(lightVerb)"}"#,
            darkVerb,
            #"{"openWidgetActionID":"\#(darkVerb)"}"#
        )
    }

    private func makeActionDocument(
        theme: WidgetEnvironmentSnapshot.ColorScheme,
        nodeID: WidgetNodeID,
        action: WidgetAction
    ) -> WidgetDocument {
        WidgetDocument(
            root: WidgetNode(
                id: WidgetNodeID(components: [.role("root")]),
                kind: .group,
                children: [
                    WidgetNode(
                        id: nodeID,
                        kind: .action(
                            WidgetActionDescriptor(
                                id: action.id,
                                title: WidgetText(storage: .verbatim("Run")),
                                role: .standard
                            )
                        )
                    )
                ]
            ),
            environment: WidgetEnvironmentSnapshot(
                colorScheme: theme,
                family: .systemSmall
            ),
            actions: [action.id: action]
        )
    }

    private func waitForHostCondition(
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<2_000 {
            if await condition() { return }
            await Task.yield()
        }
        throw HostTestFailure.conditionNotReached
    }
}

private actor ActionCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private actor SuspendingActionGate {
    private var continuation: CheckedContinuation<Void, Never>?

    var isWaiting: Bool { continuation != nil }

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor FailingActionAttempts {
    private(set) var count = 0

    func reject() throws {
        count += 1
        throw FixtureActionFailure.rejected
    }
}

private enum FixtureActionFailure: Error {
    case rejected
}

private enum HostTestFailure: Error {
    case conditionNotReached
}
