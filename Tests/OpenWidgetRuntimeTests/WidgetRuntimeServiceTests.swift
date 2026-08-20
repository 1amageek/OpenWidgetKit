@testable import OpenWidgetRuntime
import OpenFoundation
import Synchronization
import Testing

@MainActor
@Suite
struct WidgetRuntimeServiceTests {
    @Test
    func registryRejectsDuplicateKinds() throws {
        let first = makeDefinition(kind: "duplicate", timelines: [
            try makeTimeline(marker: "first", policy: .never)
        ])
        let second = makeDefinition(kind: "duplicate", timelines: [
            try makeTimeline(marker: "second", policy: .never)
        ])

        #expect(throws: WidgetRuntimeError.duplicateKind("duplicate")) {
            try RuntimeWidgetRegistry(definitions: [first, second])
        }
    }

    @Test
    func neverPolicyPublishesDueEntryWithoutReloading() async throws {
        let now = Date(timeIntervalSince1970: 100)
        let clock = ManualWidgetClock(now: now)
        let source = TimelineSource(timelines: [
            try makeTimeline(marker: "current", date: now, policy: .never)
        ])
        let (service, host) = try makeServiceAndHost(
            source: source,
            clock: clock
        )

        try await service.createInstance(
            id: "instance",
            kind: "kind",
            configuration: makeConfiguration()
        )
        try await waitUntil { await source.requestCount == 1 }
        try await waitUntil { await host.updates.count == 1 }

        await clock.advance(to: now.addingTimeInterval(100))
        for _ in 0..<20 { await Task.yield() }
        let requestCount = await source.requestCount
        let markers = await host.markers
        #expect(requestCount == 1)
        #expect(markers == ["current"])
        await service.shutdown()
    }

    @Test
    func atEndPublishesLastEntryThenRequestsNextTimeline() async throws {
        let now = Date(timeIntervalSince1970: 200)
        let deadline = now.addingTimeInterval(10)
        let clock = ManualWidgetClock(now: now)
        let first = try RuntimeTimeline(
            entries: [
                makeEntry(marker: "initial", date: now),
                makeEntry(marker: "last", date: deadline)
            ],
            reloadPolicy: .atEnd
        )
        let second = try makeTimeline(
            marker: "reloaded",
            date: deadline,
            policy: .never
        )
        let source = TimelineSource(timelines: [first, second])
        let (service, host) = try makeServiceAndHost(
            source: source,
            clock: clock
        )

        try await service.createInstance(
            id: "instance",
            kind: "kind",
            configuration: makeConfiguration()
        )
        try await waitUntil { await host.markers == ["initial"] }
        await clock.advance(to: deadline)
        try await waitUntil { await source.requestCount == 2 }
        try await waitUntil {
            await host.markers == ["initial", "last", "reloaded"]
        }
        await service.shutdown()
    }

    @Test
    func afterPolicyReloadsBeforeLaterEntry() async throws {
        let now = Date(timeIntervalSince1970: 300)
        let reloadDate = now.addingTimeInterval(5)
        let futureDate = now.addingTimeInterval(10)
        let clock = ManualWidgetClock(now: now)
        let first = try RuntimeTimeline(
            entries: [
                makeEntry(marker: "initial", date: now),
                makeEntry(marker: "obsolete", date: futureDate)
            ],
            reloadPolicy: .after(reloadDate)
        )
        let second = try makeTimeline(
            marker: "reloaded",
            date: reloadDate,
            policy: .never
        )
        let source = TimelineSource(timelines: [first, second])
        let (service, host) = try makeServiceAndHost(
            source: source,
            clock: clock
        )

        try await service.createInstance(
            id: "instance",
            kind: "kind",
            configuration: makeConfiguration()
        )
        try await waitUntil { await host.markers == ["initial"] }
        await clock.advance(to: reloadDate)
        try await waitUntil { await host.markers == ["initial", "reloaded"] }
        await clock.advance(to: futureDate)
        for _ in 0..<20 { await Task.yield() }
        let markers = await host.markers
        #expect(markers == ["initial", "reloaded"])
        await service.shutdown()
    }

    @Test
    func equalFutureEntryDatesPreserveProviderOrder() async throws {
        let now = Date(timeIntervalSince1970: 350)
        let deadline = now.addingTimeInterval(10)
        let clock = ManualWidgetClock(now: now)
        let source = TimelineSource(timelines: [
            try RuntimeTimeline(
                entries: [
                    makeEntry(marker: "first", date: deadline),
                    makeEntry(marker: "second", date: deadline)
                ],
                reloadPolicy: .never
            )
        ])
        let (service, host) = try makeServiceAndHost(
            source: source,
            clock: clock
        )

        try await service.createInstance(
            id: "instance",
            kind: "kind",
            configuration: makeConfiguration()
        )
        try await waitUntil { await clock.pendingSleeperCount == 1 }
        await clock.advance(to: deadline)
        try await waitUntil { await host.markers.count == 2 }

        let markers = await host.markers
        #expect(markers == ["first", "second"])
        await service.shutdown()
    }

    @Test
    func reloadCancelsOldGenerationBeforeHostUpdate() async throws {
        let now = Date(timeIntervalSince1970: 400)
        let clock = ManualWidgetClock(now: now)
        let source = SlowThenFastTimelineSource(
            fastTimeline: try makeTimeline(
                marker: "fresh",
                date: now,
                policy: .never
            )
        )
        let (service, host) = try makeServiceAndHost(
            source: source,
            clock: clock
        )

        try await service.createInstance(
            id: "instance",
            kind: "kind",
            configuration: makeConfiguration()
        )
        try await waitUntil { await source.requestCount == 1 }
        await service.reload(instanceID: "instance")
        try await waitUntil { await host.markers == ["fresh"] }
        let requestCount = await source.requestCount
        #expect(requestCount == 2)
        await service.shutdown()
    }

    @Test
    func deletionCancelsInFlightProviderResult() async throws {
        let now = Date(timeIntervalSince1970: 500)
        let clock = ManualWidgetClock(now: now)
        let source = SlowThenFastTimelineSource(
            fastTimeline: try makeTimeline(
                marker: "must-not-publish",
                date: now,
                policy: .never
            )
        )
        let (service, host) = try makeServiceAndHost(
            source: source,
            clock: clock
        )

        try await service.createInstance(
            id: "instance",
            kind: "kind",
            configuration: makeConfiguration()
        )
        try await waitUntil { await source.requestCount == 1 }
        await service.deleteInstance(id: "instance")
        for _ in 0..<50 { await Task.yield() }
        let updates = await host.updates
        let configurations = await service.currentConfigurations()
        #expect(updates.isEmpty)
        #expect(configurations.isEmpty)
        await service.shutdown()
    }

    @Test
    func nonAdvancingAutomaticReloadStopsWithoutSpinning() async throws {
        let now = Date(timeIntervalSince1970: 600)
        let clock = ManualWidgetClock(now: now)
        let diagnostics = RuntimeDiagnosticRecorder()
        let source = TimelineSource(timelines: [
            try makeTimeline(marker: "current", date: now, policy: .atEnd),
            try makeTimeline(marker: "must-not-request", date: now, policy: .never)
        ])
        let host = RecordingHost()
        let definition = RuntimeWidgetDefinition(kind: "kind") { _, _, _ in
            try await source.nextTimeline()
        }
        let registry = try RuntimeWidgetRegistry(definitions: [definition])
        let service = WidgetRuntimeService(
            registry: registry,
            host: host,
            clock: clock,
            diagnostics: diagnostics.record
        )

        try await service.createInstance(
            id: "instance",
            kind: "kind",
            configuration: makeConfiguration()
        )
        try await waitUntil { await host.markers == ["current"] }
        try await waitUntil {
            diagnostics.values.contains {
                guard case .nonAdvancingReload = $0 else { return false }
                return true
            }
        }

        let requestCount = await source.requestCount
        #expect(requestCount == 1)
        await service.shutdown()
    }

    @Test
    func deleteFencesAnApplyAlreadySuspendedInsideHost() async throws {
        let now = Date(timeIntervalSince1970: 700)
        let clock = ManualWidgetClock(now: now)
        let source = TimelineSource(timelines: [
            try makeTimeline(marker: "stale", date: now, policy: .never)
        ])
        let host = SuspendingHost()
        let definition = RuntimeWidgetDefinition(kind: "kind") { _, _, _ in
            try await source.nextTimeline()
        }
        let registry = try RuntimeWidgetRegistry(definitions: [definition])
        let service = WidgetRuntimeService(
            registry: registry,
            host: host,
            clock: clock
        )

        try await service.createInstance(
            id: "instance",
            kind: "kind",
            configuration: makeConfiguration()
        )
        try await waitUntil { await host.hasSuspendedApply }
        await service.deleteInstance(id: "instance")
        await host.releaseSuspendedApply()
        for _ in 0..<20 { await Task.yield() }

        let committedUpdates = await host.committedUpdates
        #expect(committedUpdates.isEmpty)
        await service.shutdown()
    }

    @Test
    func invalidCreationInputsFailWithoutRegisteringAnInstance() async throws {
        let now = Date(timeIntervalSince1970: 800)
        let clock = ManualWidgetClock(now: now)
        let host = RecordingHost()
        let definition = makeDefinition(
            kind: "kind",
            timelines: [
                try makeTimeline(marker: "valid", date: now, policy: .never)
            ]
        ).withSupportedFamilies([.systemSmall])
        let registry = try RuntimeWidgetRegistry(definitions: [definition])
        let service = WidgetRuntimeService(
            registry: registry,
            host: host,
            clock: clock
        )

        await #expect(throws: WidgetRuntimeError.unknownKind("unknown")) {
            try await service.createInstance(
                id: "unknown",
                kind: "unknown",
                configuration: makeConfiguration()
            )
        }
        await #expect(
            throws: WidgetRuntimeError.unsupportedFamily(
                kind: "kind",
                family: .systemMedium
            )
        ) {
            var configuration = makeConfiguration()
            configuration = RuntimeWidgetInstanceConfiguration(
                family: .systemMedium,
                isPreview: configuration.isPreview,
                displaySize: configuration.displaySize,
                environment: configuration.environment
            )
            try await service.createInstance(
                id: "family",
                kind: "kind",
                configuration: configuration
            )
        }
        await #expect(throws: WidgetRuntimeError.invalidDisplaySize) {
            try await service.createInstance(
                id: "size",
                kind: "kind",
                configuration: RuntimeWidgetInstanceConfiguration(
                    family: .systemSmall,
                    isPreview: false,
                    displaySize: CGSize(width: 0, height: 0),
                    environment: WidgetEnvironmentSnapshot()
                )
            )
        }

        let configurations = await service.currentConfigurations()
        #expect(configurations.isEmpty)
        await service.shutdown()
    }

    @Test
    func hostInvalidationFailureRollsBackCreation() async throws {
        let now = Date(timeIntervalSince1970: 900)
        let definition = makeDefinition(
            kind: "kind",
            timelines: [
                try makeTimeline(marker: "unused", date: now, policy: .never)
            ]
        )
        let registry = try RuntimeWidgetRegistry(definitions: [definition])
        let service = WidgetRuntimeService(
            registry: registry,
            host: RejectingHost(),
            clock: ManualWidgetClock(now: now)
        )

        await #expect(
            throws: WidgetRuntimeError.hostRejected(
                message: "rejectedInvalidation"
            )
        ) {
            try await service.createInstance(
                id: "instance",
                kind: "kind",
                configuration: makeConfiguration()
            )
        }
        let configurations = await service.currentConfigurations()
        #expect(configurations.isEmpty)
        await service.shutdown()
    }

    private func makeServiceAndHost<Source: TimelineProvidingSource>(
        source: Source,
        clock: ManualWidgetClock
    ) throws -> (WidgetRuntimeService, RecordingHost) {
        let host = RecordingHost()
        let definition = RuntimeWidgetDefinition(kind: "kind") {
            _, _, _ in
            try await source.nextTimeline()
        }
        let registry = try RuntimeWidgetRegistry(definitions: [definition])
        return (
            WidgetRuntimeService(
                registry: registry,
                host: host,
                clock: clock,
                providerTimeout: .seconds(1)
            ),
            host
        )
    }

    private func makeDefinition(
        kind: String,
        timelines: [RuntimeTimeline]
    ) -> RuntimeWidgetDefinition {
        let source = TimelineSource(timelines: timelines)
        return RuntimeWidgetDefinition(kind: kind) { _, _, _ in
            try await source.nextTimeline()
        }
    }

    private func makeConfiguration() -> RuntimeWidgetInstanceConfiguration {
        RuntimeWidgetInstanceConfiguration(
            family: .systemSmall,
            isPreview: false,
            displaySize: CGSize(width: 160, height: 160),
            environment: WidgetEnvironmentSnapshot()
        )
    }

    private func makeTimeline(
        marker: String,
        date: Date = Date(timeIntervalSince1970: 0),
        policy: RuntimeTimelineReloadPolicy
    ) throws -> RuntimeTimeline {
        try RuntimeTimeline(
            entries: [makeEntry(marker: marker, date: date)],
            reloadPolicy: policy
        )
    }

    private func makeEntry(marker: String, date: Date) -> RuntimeTimelineEntry {
        let text = WidgetText(storage: .verbatim(marker))
        let node = WidgetNode(
            id: WidgetNodeID().appending(.role("marker")),
            kind: .text(text)
        )
        let document = WidgetDocument(
            root: node,
            environment: WidgetEnvironmentSnapshot()
        )
        return RuntimeTimelineEntry(date: date, document: document)
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<2_000 {
            if await condition() { return }
            await Task.yield()
        }
        throw TestFailure.conditionNotReached
    }
}

private protocol TimelineProvidingSource: Sendable {
    func nextTimeline() async throws -> RuntimeTimeline
}

private actor TimelineSource: TimelineProvidingSource {
    private var timelines: [RuntimeTimeline]
    private(set) var requestCount = 0

    init(timelines: [RuntimeTimeline]) {
        self.timelines = timelines
    }

    func nextTimeline() throws -> RuntimeTimeline {
        requestCount += 1
        guard !timelines.isEmpty else {
            throw WidgetRuntimeError.hostRejected(message: "No test timeline remains.")
        }
        return timelines.removeFirst()
    }
}

private actor SlowThenFastTimelineSource: TimelineProvidingSource {
    private let fastTimeline: RuntimeTimeline
    private(set) var requestCount = 0

    init(fastTimeline: RuntimeTimeline) {
        self.fastTimeline = fastTimeline
    }

    func nextTimeline() async throws -> RuntimeTimeline {
        requestCount += 1
        if requestCount == 1 {
            try await Task.sleep(for: .seconds(60))
        }
        return fastTimeline
    }
}

private actor RecordingHost: RuntimeWidgetHost {
    private struct InstanceState {
        var generation: UInt64
        var isRemoved: Bool
    }

    private var states: [String: InstanceState] = [:]
    private(set) var updates: [RuntimeWidgetUpdate] = []

    var markers: [String] {
        updates.compactMap { update in
            guard case .text(let text) = update.entry.document.root.kind,
                  case .verbatim(let marker) = text.storage else { return nil }
            return marker
        }
    }

    func invalidate(instanceID: String, generation: UInt64) {
        guard generation >= (states[instanceID]?.generation ?? 0) else { return }
        states[instanceID] = InstanceState(
            generation: generation,
            isRemoved: false
        )
    }

    func apply(_ update: RuntimeWidgetUpdate) {
        guard let state = states[update.instanceID],
              state.generation == update.generation,
              !state.isRemoved else { return }
        updates.append(update)
    }

    func remove(instanceID: String, generation: UInt64) {
        guard generation >= (states[instanceID]?.generation ?? 0) else { return }
        states[instanceID] = InstanceState(
            generation: generation,
            isRemoved: true
        )
    }
}

private actor ManualWidgetClock: WidgetRuntimeClock {
    private struct Sleeper {
        let date: Date
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var currentDate: Date
    private var nextID = 0
    private var sleepers: [Int: Sleeper] = [:]

    var pendingSleeperCount: Int {
        sleepers.count
    }

    init(now: Date) {
        currentDate = now
    }

    func now() -> Date {
        currentDate
    }

    func sleep(until date: Date) async throws {
        guard date > currentDate else { return }
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    sleepers[id] = Sleeper(
                        date: date,
                        continuation: continuation
                    )
                }
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func advance(to date: Date) {
        currentDate = date
        let ready = sleepers.filter { $0.value.date <= date }
        for (id, sleeper) in ready {
            sleepers[id] = nil
            sleeper.continuation.resume()
        }
    }

    private func cancel(id: Int) {
        guard let sleeper = sleepers.removeValue(forKey: id) else { return }
        sleeper.continuation.resume(throwing: CancellationError())
    }
}

private actor SuspendingHost: RuntimeWidgetHost {
    private struct InstanceState {
        var generation: UInt64
        var isRemoved: Bool
    }

    private var states: [String: InstanceState] = [:]
    private var applyContinuation: CheckedContinuation<Void, Never>?
    private(set) var committedUpdates: [RuntimeWidgetUpdate] = []

    var hasSuspendedApply: Bool {
        applyContinuation != nil
    }

    func invalidate(instanceID: String, generation: UInt64) {
        guard generation >= (states[instanceID]?.generation ?? 0) else { return }
        states[instanceID] = InstanceState(
            generation: generation,
            isRemoved: false
        )
    }

    func apply(_ update: RuntimeWidgetUpdate) async {
        await withCheckedContinuation { continuation in
            applyContinuation = continuation
        }
        guard let state = states[update.instanceID],
              state.generation == update.generation,
              !state.isRemoved else { return }
        committedUpdates.append(update)
    }

    func remove(instanceID: String, generation: UInt64) {
        guard generation >= (states[instanceID]?.generation ?? 0) else { return }
        states[instanceID] = InstanceState(
            generation: generation,
            isRemoved: true
        )
    }

    func releaseSuspendedApply() {
        let continuation = applyContinuation
        applyContinuation = nil
        continuation?.resume()
    }
}

private struct RejectingHost: RuntimeWidgetHost {
    func invalidate(instanceID: String, generation: UInt64) async throws {
        throw RejectingHostError.rejectedInvalidation
    }

    func apply(_ update: RuntimeWidgetUpdate) async throws {}

    func remove(instanceID: String, generation: UInt64) async throws {}
}

private enum RejectingHostError: Error {
    case rejectedInvalidation
}

private enum TestFailure: Error {
    case conditionNotReached
}

private final class RuntimeDiagnosticRecorder: Sendable {
    private let storage = Mutex<[WidgetRuntimeDiagnostic]>([])

    var values: [WidgetRuntimeDiagnostic] {
        storage.withLock { $0 }
    }

    func record(_ diagnostic: WidgetRuntimeDiagnostic) {
        storage.withLock { $0.append(diagnostic) }
    }
}
