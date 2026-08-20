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
                    dataJSON: dataJSON
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

    private func makeHost(
        bridge: RecordingWindowsBridge
    ) throws -> WindowsAdaptiveCardHost {
        WindowsAdaptiveCardHost(
            compiler: try AdaptiveCardCompiler(
                resourceResolver: EmptyResourceResolver()
            ),
            bridge: bridge
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
}
