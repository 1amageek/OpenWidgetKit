import OpenFoundation

package actor WidgetRuntimeService {
    private struct Instance {
        let kind: String
        let definition: RuntimeWidgetDefinition
        let identityStore: WidgetIdentityStore
        var configuration: RuntimeWidgetInstanceConfiguration
        var generation: UInt64
        var task: Task<Void, Never>?
    }

    private enum ScheduledEvent {
        case entry(RuntimeTimelineEntry, sequence: Int)
        case reload(Date, sequence: Int)

        var date: Date {
            switch self {
            case .entry(let entry, _): entry.date
            case .reload(let date, _): date
            }
        }

        var priority: Int {
            switch self {
            case .entry: 0
            case .reload: 1
            }
        }

        var sequence: Int {
            switch self {
            case .entry(_, let sequence), .reload(_, let sequence):
                sequence
            }
        }
    }

    private let registry: RuntimeWidgetRegistry
    private let host: any RuntimeWidgetHost
    private let clock: any WidgetRuntimeClock
    private let providerTimeout: Duration
    private let diagnostics: WidgetRuntimeDiagnosticSink
    private var instances: [String: Instance] = [:]
    private var isShutdown = false

    package init(
        registry: RuntimeWidgetRegistry,
        host: any RuntimeWidgetHost,
        clock: any WidgetRuntimeClock = SystemWidgetRuntimeClock(),
        providerTimeout: Duration = .seconds(30),
        diagnostics: @escaping WidgetRuntimeDiagnosticSink = { _ in }
    ) {
        self.registry = registry
        self.host = host
        self.clock = clock
        self.providerTimeout = providerTimeout
        self.diagnostics = diagnostics
    }

    package func createInstance(
        id: String,
        kind: String,
        configuration: RuntimeWidgetInstanceConfiguration
    ) async throws {
        guard !isShutdown else {
            throw WidgetRuntimeError.hostUnavailable
        }
        guard instances[id] == nil else {
            throw WidgetRuntimeError.hostRejected(
                message: "Widget instance '\(id)' already exists."
            )
        }
        guard let definition = await registry.definition(for: kind) else {
            throw WidgetRuntimeError.unknownKind(kind)
        }
        try await validate(configuration, for: definition)
        let identityStore = await WidgetIdentityStore()
        instances[id] = Instance(
            kind: kind,
            definition: definition,
            identityStore: identityStore,
            configuration: configuration,
            generation: 0,
            task: nil
        )
        do {
            try await startRequest(for: id)
        } catch {
            if var failedInstance = instances.removeValue(forKey: id) {
                failedInstance.generation &+= 1
                do {
                    try await host.remove(
                        instanceID: id,
                        generation: failedInstance.generation
                    )
                } catch {
                    recordHostFailure(error, instanceID: id)
                }
            }
            throw error
        }
    }

    package func updateContext(
        for id: String,
        configuration: RuntimeWidgetInstanceConfiguration
    ) async throws {
        guard let instance = instances[id] else {
            throw WidgetRuntimeError.unknownInstance(id)
        }
        try await validate(configuration, for: instance.definition)
        instances[id]?.configuration = configuration
        try await startRequest(for: id)
    }

    package func reload(instanceID: String) async {
        guard instances[instanceID] != nil else { return }
        do {
            try await startRequest(for: instanceID)
        } catch {
            recordHostFailure(error, instanceID: instanceID)
        }
    }

    package func reload(kind: String) async {
        let matching = instances.compactMap { id, instance in
            instance.kind == kind ? id : nil
        }
        guard !matching.isEmpty else {
            diagnostics(.reloadRequestedForUnknownKind(kind))
            return
        }
        for id in matching {
            do {
                try await startRequest(for: id)
            } catch {
                recordHostFailure(error, instanceID: id)
            }
        }
    }

    package func reloadAll() async {
        for id in Array(instances.keys) {
            do {
                try await startRequest(for: id)
            } catch {
                recordHostFailure(error, instanceID: id)
            }
        }
    }

    package func deleteInstance(id: String) async {
        guard var instance = instances.removeValue(forKey: id) else { return }
        instance.generation &+= 1
        instance.task?.cancel()
        do {
            try await host.remove(
                instanceID: id,
                generation: instance.generation
            )
        } catch {
            recordHostFailure(error, instanceID: id)
        }
    }

    package func currentConfigurations() -> [RuntimeWidgetInfo] {
        instances.map { id, instance in
            RuntimeWidgetInfo(
                instanceID: id,
                kind: instance.kind,
                family: instance.configuration.family
            )
        }
        .sorted { lhs, rhs in lhs.instanceID < rhs.instanceID }
    }

    package func shutdown() async {
        guard !isShutdown else { return }
        isShutdown = true
        let removedInstances = instances
        instances.removeAll(keepingCapacity: false)
        for instance in removedInstances.values {
            instance.task?.cancel()
        }
        for (id, var instance) in removedInstances {
            instance.generation &+= 1
            do {
                try await host.remove(
                    instanceID: id,
                    generation: instance.generation
                )
            } catch {
                recordHostFailure(error, instanceID: id)
            }
        }
    }

    private func startRequest(for id: String) async throws {
        guard !isShutdown, var instance = instances[id] else { return }
        instance.task?.cancel()
        instance.generation &+= 1
        let generation = instance.generation
        let definition = instance.definition
        let configuration = instance.configuration
        let identityStore = instance.identityStore
        let timeout = providerTimeout
        let diagnostics = diagnostics
        instance.task = nil
        instances[id] = instance
        do {
            try await host.invalidate(instanceID: id, generation: generation)
        } catch let error as WidgetRuntimeError {
            throw error
        } catch {
            throw WidgetRuntimeError.hostRejected(
                message: String(describing: error)
            )
        }
        guard isCurrent(instanceID: id, generation: generation) else { return }
        instance.task = Task { [self] in
            do {
                var environment = configuration.environment
                environment.family = configuration.family
                let context = RuntimeProviderContext(
                    family: configuration.family,
                    isPreview: configuration.isPreview,
                    displaySize: configuration.displaySize,
                    environment: environment,
                    identityStore: identityStore
                )
                let timeline = try await definition.requestTimeline(
                    context: context,
                    timeout: timeout,
                    diagnostics: diagnostics
                )
                try Task.checkCancellation()
                await consume(
                    timeline,
                    instanceID: id,
                    generation: generation
                )
            } catch is CancellationError {
                return
            } catch let error as WidgetRuntimeError {
                recordFailure(error, instanceID: id, generation: generation)
            } catch {
                recordFailure(
                    .hostRejected(message: String(describing: error)),
                    instanceID: id,
                    generation: generation
                )
            }
        }
        instances[id] = instance
    }

    private func consume(
        _ timeline: RuntimeTimeline,
        instanceID: String,
        generation: UInt64
    ) async {
        var events = timeline.entries.enumerated().map {
            ScheduledEvent.entry($0.element, sequence: $0.offset)
        }
        switch timeline.reloadPolicy {
        case .atEnd:
            if let date = timeline.entries.last?.date {
                events.append(
                    .reload(date, sequence: timeline.entries.count)
                )
            }
        case .after(let date):
            events.append(
                .reload(date, sequence: timeline.entries.count)
            )
        case .never:
            break
        }
        events.sort { lhs, rhs in
            guard lhs.date == rhs.date else { return lhs.date < rhs.date }
            guard lhs.priority == rhs.priority else {
                return lhs.priority < rhs.priority
            }
            return lhs.sequence < rhs.sequence
        }

        let now = await clock.now()
        var pendingPastEntry: RuntimeTimelineEntry?
        for event in events {
            guard isCurrent(instanceID: instanceID, generation: generation) else {
                diagnostics(
                    .staleGeneration(
                        instanceID: instanceID,
                        generation: generation
                    )
                )
                return
            }

            if event.date <= now {
                switch event {
                case .entry(let entry, _):
                    pendingPastEntry = entry
                    continue
                case .reload:
                    if let pendingPastEntry {
                        await apply(
                            pendingPastEntry,
                            instanceID: instanceID,
                            generation: generation
                        )
                    }
                    diagnostics(
                        .nonAdvancingReload(
                            instanceID: instanceID,
                            scheduledDate: event.date,
                            currentDate: now
                        )
                    )
                    return
                }
            }

            if let pendingPastEntry {
                await apply(
                    pendingPastEntry,
                    instanceID: instanceID,
                    generation: generation
                )
            }
            pendingPastEntry = nil

            do {
                try await clock.sleep(until: event.date)
                try Task.checkCancellation()
            } catch {
                return
            }
            guard isCurrent(instanceID: instanceID, generation: generation) else {
                return
            }
            switch event {
            case .entry(let entry, _):
                await apply(entry, instanceID: instanceID, generation: generation)
            case .reload:
                do {
                    try await startRequest(for: instanceID)
                } catch {
                    recordHostFailure(error, instanceID: instanceID)
                }
                return
            }
        }

        if let pendingPastEntry {
            await apply(
                pendingPastEntry,
                instanceID: instanceID,
                generation: generation
            )
        }
    }

    private func apply(
        _ entry: RuntimeTimelineEntry,
        instanceID: String,
        generation: UInt64
    ) async {
        guard let instance = instances[instanceID],
              instance.generation == generation else { return }
        let update = RuntimeWidgetUpdate(
            instanceID: instanceID,
            kind: instance.kind,
            family: instance.configuration.family,
            generation: generation,
            entry: entry
        )
        do {
            try await host.apply(update)
        } catch {
            diagnostics(
                .hostUpdateFailed(
                    instanceID: instanceID,
                    message: String(describing: error)
                )
            )
        }
    }

    private func isCurrent(instanceID: String, generation: UInt64) -> Bool {
        guard !isShutdown, let instance = instances[instanceID] else { return false }
        return instance.generation == generation
    }

    private func validate(
        _ configuration: RuntimeWidgetInstanceConfiguration,
        for definition: RuntimeWidgetDefinition
    ) async throws {
        guard configuration.displaySize.width.isFinite,
              configuration.displaySize.height.isFinite,
              configuration.displaySize.width > 0,
              configuration.displaySize.height > 0 else {
            throw WidgetRuntimeError.invalidDisplaySize
        }
        guard definition.supportedFamilies.contains(configuration.family) else {
            throw WidgetRuntimeError.unsupportedFamily(
                kind: definition.kind,
                family: configuration.family
            )
        }
    }

    private func recordFailure(
        _ error: WidgetRuntimeError,
        instanceID: String,
        generation: UInt64
    ) {
        guard isCurrent(instanceID: instanceID, generation: generation) else { return }
        diagnostics(
            .hostUpdateFailed(
                instanceID: instanceID,
                message: String(describing: error)
            )
        )
    }

    private func recordHostFailure(_ error: any Error, instanceID: String) {
        diagnostics(
            .hostUpdateFailed(
                instanceID: instanceID,
                message: String(describing: error)
            )
        )
    }
}
