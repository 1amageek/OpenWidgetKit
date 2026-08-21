import OpenWidgetRuntime
import Synchronization
import SwiftUI

// TimelineProvider does not require Entry to be Sendable, but its @Sendable
// completion may execute away from MainActor. This owner accepts the callback's
// one-shot value handoff and permits exactly one MainActor take. The provider
// must not mutate aliases after invoking its completion, which is the ownership
// contract of the callback API. The mutex protects the handoff itself.
private final class ProviderTimelineTransfer: Sendable {
    private struct Payload: @unchecked Sendable {
        var timeline: Any?
    }

    private let storage: Mutex<Payload>

    init(_ timeline: Any) {
        storage = Mutex(Payload(timeline: timeline))
    }

    func take<Entry>(as type: Timeline<Entry>.Type) -> Timeline<Entry>?
    where Entry: TimelineEntry {
        storage.withLock { payload in
            defer { payload.timeline = nil }
            return payload.timeline as? Timeline<Entry>
        }
    }
}

@MainActor
private final class ProviderTimelineConsumer: Sendable {
    private let operation: @MainActor (ProviderTimelineTransfer) -> Void

    init(operation: @escaping @MainActor (ProviderTimelineTransfer) -> Void) {
        self.operation = operation
    }

    nonisolated func consume(_ transfer: ProviderTimelineTransfer) {
        Task { @MainActor [self, transfer] in
            operation(transfer)
        }
    }
}

@MainActor
private protocol StaticConfigurationStorageProtocol: AnyObject, Sendable {
    func makeDefinition() throws -> RuntimeWidgetDefinition
}

@MainActor
private final class StaticConfigurationStorage<Provider, Content>:
    StaticConfigurationStorageProtocol
where Provider: TimelineProvider, Content: View {
    let kind: String
    let provider: Provider
    let content: (Provider.Entry) -> Content

    init(
        kind: String,
        provider: Provider,
        content: @escaping (Provider.Entry) -> Content
    ) {
        self.kind = kind
        self.provider = provider
        self.content = content
    }

    func makeDefinition() throws -> RuntimeWidgetDefinition {
        guard !kind.isEmpty else {
            throw WidgetRuntimeError.invalidWidgetKind
        }
        return RuntimeWidgetDefinition(kind: kind) { [self] context, timeout, diagnostics in
            try await requestTimeline(
                context: context,
                timeout: timeout,
                diagnostics: diagnostics
            )
        }
    }

    private func requestTimeline(
        context: RuntimeProviderContext,
        timeout: Duration,
        diagnostics: @escaping WidgetRuntimeDiagnosticSink
    ) async throws -> RuntimeTimeline {
        try await RuntimeProviderRequest<RuntimeTimeline>.perform(
            kind: kind,
            timeout: timeout,
            diagnostics: diagnostics
        ) { request in
            let providerContext = TimelineProviderContext(runtimeValue: context)
            let consumer = ProviderTimelineConsumer { [self, request] transfer in
                do {
                    guard let timeline = transfer.take(
                        as: Timeline<Provider.Entry>.self
                    ) else {
                        request.fail(.providerTimelineOwnershipConsumed)
                        return
                    }
                    request.succeed(
                        try makeRuntimeTimeline(
                            timeline,
                            context: context
                        )
                    )
                } catch let error as WidgetSemanticError {
                    request.fail(.semantic(error))
                } catch let error as TimelineRuntimeError {
                    request.fail(.invalidTimeline(error))
                } catch let error as WidgetRuntimeError {
                    request.fail(error)
                } catch {
                    request.fail(.providerFailed)
                }
            }
            provider.getTimeline(in: providerContext) { timeline in
                guard request.claimProviderCallback() == .accepted else { return }
                consumer.consume(ProviderTimelineTransfer(timeline))
            }
        }
    }

    private func makeRuntimeTimeline(
        _ timeline: Timeline<Provider.Entry>,
        context: RuntimeProviderContext
    ) throws -> RuntimeTimeline {
        _ = try timeline.validatedRuntimeValue()
        return try context.identityStore.withEvaluation {
            let entries = try timeline.entries.map { entry in
                let documents = try context.environmentVariants.map { snapshot in
                    var environment = EnvironmentValues(snapshot: snapshot)
                    environment.widgetFamily = context.family
                    return try makeWidgetDocument(
                        content(entry),
                        environment: environment,
                        identityStore: context.identityStore
                    )
                }
                guard let document = documents.first else {
                    throw WidgetRuntimeError.missingEnvironmentVariants
                }
                return RuntimeTimelineEntry(
                    date: entry.date,
                    document: document,
                    additionalDocuments: Array(documents.dropFirst())
                )
            }
            return try RuntimeTimeline(
                entries: entries,
                reloadPolicy: timeline.policy.runtimeValue
            )
        }
    }
}

@MainActor
private struct StaticConfigurationBody: WidgetConfiguration {
    typealias Body = Never

    let storage: any StaticConfigurationStorageProtocol
}

extension StaticConfigurationBody: WidgetConfigurationLowering {
    func makeRuntimeWidgetDefinitions() throws -> [RuntimeWidgetDefinition] {
        [try storage.makeDefinition()]
    }
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@preconcurrency
@MainActor
public struct StaticConfiguration<Content>: WidgetConfiguration where Content: View {
    private let storage: any StaticConfigurationStorageProtocol

    @MainActor
    @preconcurrency
    public var body: some WidgetConfiguration {
        StaticConfigurationBody(storage: storage)
    }

    @MainActor
    @preconcurrency
    public init<Provider>(
        kind: String,
        provider: Provider,
        @ViewBuilder content: @escaping (Provider.Entry) -> Content
    ) where Provider: TimelineProvider {
        storage = StaticConfigurationStorage(
            kind: kind,
            provider: provider,
            content: content
        )
    }
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
extension StaticConfiguration: WidgetConfigurationLowering {
    package func makeRuntimeWidgetDefinitions() throws -> [RuntimeWidgetDefinition] {
        [try storage.makeDefinition()]
    }
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
extension StaticConfiguration: Sendable {}

private extension TimelineProviderContext {
    init(runtimeValue: RuntimeProviderContext) {
        self.init(
            family: WidgetFamily(runtimeValue: runtimeValue.family),
            isPreview: runtimeValue.isPreview,
            displaySize: runtimeValue.displaySize,
            environmentVariants: EnvironmentVariants(
                values: runtimeValue.environmentVariants.map(
                    EnvironmentValues.init(snapshot:)
                )
            )
        )
    }
}
