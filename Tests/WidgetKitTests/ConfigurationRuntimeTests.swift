@testable import OpenWidgetRuntime
@testable import SwiftUI
@testable import WidgetKit
import Synchronization
import Testing

@MainActor
@Suite(.serialized)
struct ConfigurationRuntimeTests {
    @Test
    func staticConfigurationLowersMetadataAndTimelineContent() async throws {
        let configuration = StaticConfiguration(
            kind: "weather",
            provider: ImmediateProvider()
        ) { entry in
            Text(verbatim: "value-\(entry.value)")
        }
        .configurationDisplayName("Weather")
        .description("Current conditions")
        .supportedFamilies([.systemSmall, .systemMedium])

        let definitions = try lowerWidgetConfiguration(configuration)
        let definition = try #require(definitions.first)
        #expect(definitions.count == 1)
        #expect(definition.kind == "weather")
        #expect(definition.supportedFamilies == [.systemSmall, .systemMedium])
        #expect(localizedKey(in: definition.displayName) == "Weather")
        #expect(
            localizedKey(in: definition.configurationDescription)
                == "Current conditions"
        )

        let timeline = try await definition.requestTimeline(
            context: makeContext(family: .systemMedium),
            timeout: .seconds(1),
            diagnostics: { _ in }
        )
        let entry = try #require(timeline.entries.first)
        #expect(timeline.entries.count == 1)
        #expect(timeline.reloadPolicy == .never)
        #expect(entry.document.environment.family == .systemMedium)
        #expect(textValues(in: entry.document.root) == ["value-7"])
    }

    @Test
    func duplicateProviderCompletionKeepsFirstTimelineAndReportsDiagnostic() async throws {
        let diagnostics = DiagnosticRecorder()
        let definition = try makeDefinition(
            kind: "duplicate",
            provider: DuplicateProvider()
        )

        let timeline = try await definition.requestTimeline(
            context: makeContext(),
            timeout: .seconds(1),
            diagnostics: diagnostics.record
        )

        #expect(textValues(in: timeline.entries[0].document.root) == ["value-1"])
        #expect(
            diagnostics.values == [
                .duplicateProviderCompletion(kind: "duplicate")
            ]
        )
    }

    @Test
    func providerWithoutCompletionTimesOutExplicitly() async throws {
        let definition = try makeDefinition(
            kind: "timeout",
            provider: NeverCompletingProvider()
        )

        await #expect(
            throws: WidgetRuntimeError.providerTimedOut(kind: "timeout")
        ) {
            try await definition.requestTimeline(
                context: makeContext(),
                timeout: .milliseconds(10),
                diagnostics: { _ in }
            )
        }
    }

    @Test
    func nonPositiveProviderTimeoutFailsBeforeStartingProvider() async throws {
        let provider = CountingProvider()
        let definition = try makeDefinition(
            kind: "invalid-timeout",
            provider: provider
        )

        await #expect(throws: WidgetRuntimeError.invalidProviderTimeout) {
            try await definition.requestTimeline(
                context: makeContext(),
                timeout: .zero,
                diagnostics: { _ in }
            )
        }
        #expect(provider.requestCount == 0)
    }

    @Test
    func completionAfterTimeoutIsRejectedAsLate() async throws {
        let diagnostics = DiagnosticRecorder()
        let provider = ControlledProvider()
        let definition = try makeDefinition(kind: "late", provider: provider)

        await #expect(
            throws: WidgetRuntimeError.providerTimedOut(kind: "late")
        ) {
            try await definition.requestTimeline(
                context: makeContext(),
                timeout: .milliseconds(10),
                diagnostics: diagnostics.record
            )
        }
        provider.complete(value: 9)
        try await waitUntil {
            diagnostics.values.contains(
                .lateProviderCompletion(kind: "late")
            )
        }
    }

    @Test
    func widgetBundleLowersEveryDefinitionAndRegistryRejectsDuplicates() throws {
        let definitions = try lowerWidgetBundle(TestBundle())
        #expect(definitions.map(\.kind) == ["first", "second"])
        _ = try RuntimeWidgetRegistry(definitions: definitions)

        let duplicateDefinitions = try lowerWidgetBundle(DuplicateBundle())
        #expect(throws: WidgetRuntimeError.duplicateKind("first")) {
            try RuntimeWidgetRegistry(definitions: duplicateDefinitions)
        }
    }

    @Test
    func compositionBootstrapReceivesTheLoweredImmutableRegistry() throws {
        let bootstrap = RecordingBootstrap()
        WidgetRuntimeComposition.installBootstrap(bootstrap)
        defer { WidgetRuntimeComposition.uninstall() }
        let definitions = try lowerWidgetBundle(TestBundle())

        try WidgetRuntimeComposition.run(definitions: definitions)

        #expect(bootstrap.kinds == ["first", "second"])
    }

    @Test
    func missingBootstrapAndUnsupportedConfigurationFailExplicitly() {
        WidgetRuntimeComposition.uninstall()
        #expect(throws: WidgetRuntimeError.hostUnavailable) {
            try WidgetRuntimeComposition.run(definitions: [])
        }
        #expect(
            throws: WidgetRuntimeError.unsupportedWidgetConfiguration(
                typeName: String(reflecting: UnsupportedConfiguration.self)
            )
        ) {
            try lowerWidgetConfiguration(UnsupportedConfiguration())
        }
    }

    @Test
    func widgetCenterForwardsControlOperationsAndMapsConfigurationInfo() async throws {
        let control = RecordingControl()
        WidgetRuntimeComposition.installControl(control)
        defer { WidgetRuntimeComposition.uninstall() }

        WidgetCenter.shared.reloadTimelines(ofKind: "weather")
        WidgetCenter.shared.reloadAllTimelines()
        let values = try await currentConfigurations()

        #expect(control.reloadedKinds == ["weather"])
        #expect(control.reloadAllCount == 1)
        #expect(values.map(\.kind) == ["weather"])
        #expect(values.map(\.family) == [.systemMedium])
        #expect(WidgetCenter.UserInfoKey.kind == "WGWidgetUserInfoKeyKind")
        #expect(WidgetCenter.UserInfoKey.family == "WGWidgetUserInfoKeyFamily")
        #expect(WidgetCenter.UserInfoKey.activityID == "WGWidgetUserInfoKeyActivityID")
    }

    private func makeDefinition<Provider>(
        kind: String,
        provider: Provider
    ) throws -> RuntimeWidgetDefinition where Provider: TestTimelineProvider {
        let configuration = StaticConfiguration(kind: kind, provider: provider) { entry in
            Text(verbatim: "value-\(entry.value)")
        }
        let definitions = try configuration.makeRuntimeWidgetDefinitions()
        return try #require(definitions.first)
    }

    private func makeContext(
        family: RuntimeWidgetFamily = .systemSmall
    ) -> RuntimeProviderContext {
        RuntimeProviderContext(
            family: family,
            isPreview: false,
            displaySize: CGSize(width: 160, height: 160),
            environment: WidgetEnvironmentSnapshot(),
            identityStore: WidgetIdentityStore()
        )
    }

    private func textValues(in node: WidgetNode) -> [String] {
        let ownValue: [String]
        if case .text(let text) = node.kind,
           case .verbatim(let value) = text.storage {
            ownValue = [value]
        } else {
            ownValue = []
        }
        return ownValue + node.children.flatMap(textValues(in:))
    }

    private func localizedKey(in text: WidgetText?) -> String? {
        guard let text,
              case .localized(let key, _, _, _, _) = text.storage else {
            return nil
        }
        return key
    }

    private func currentConfigurations() async throws -> [WidgetInfo] {
        try await withCheckedThrowingContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                continuation.resume(with: result)
            }
        }
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () -> Bool
    ) async throws {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        throw ConfigurationTestFailure.conditionNotReached
    }
}

private struct TestEntry: TimelineEntry, Sendable {
    let date: Date
    let value: Int
}

private protocol TestTimelineProvider: TimelineProvider where Entry == TestEntry {}

private extension TestTimelineProvider {
    func placeholder(in context: Context) -> TestEntry {
        TestEntry(date: Date(timeIntervalSince1970: 0), value: 0)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (TestEntry) -> Void
    ) {
        completion(placeholder(in: context))
    }

    func timeline(value: Int) -> Timeline<TestEntry> {
        Timeline(
            entries: [
                TestEntry(
                    date: Date(timeIntervalSince1970: TimeInterval(value)),
                    value: value
                )
            ],
            policy: .never
        )
    }
}

private struct ImmediateProvider: TestTimelineProvider {
    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<TestEntry>) -> Void
    ) {
        completion(timeline(value: 7))
    }
}

private struct DuplicateProvider: TestTimelineProvider {
    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<TestEntry>) -> Void
    ) {
        completion(timeline(value: 1))
        completion(timeline(value: 2))
    }
}

private struct NeverCompletingProvider: TestTimelineProvider {
    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<TestEntry>) -> Void
    ) {}
}

private final class ControlledProvider: TestTimelineProvider, Sendable {
    private let completion = Mutex<(
        @Sendable (Timeline<TestEntry>) -> Void
    )?>(nil)

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<TestEntry>) -> Void
    ) {
        self.completion.withLock { $0 = completion }
    }

    func complete(value: Int) {
        let callback = completion.withLock { $0 }
        callback?(timeline(value: value))
    }
}

private final class CountingProvider: TestTimelineProvider, Sendable {
    private let count = Mutex(0)

    var requestCount: Int {
        count.withLock { $0 }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<TestEntry>) -> Void
    ) {
        count.withLock { $0 += 1 }
        completion(timeline(value: 1))
    }
}

private struct FirstWidget: Widget {
    init() {}

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "first", provider: ImmediateProvider()) { entry in
            Text(verbatim: "\(entry.value)")
        }
    }
}

private struct SecondWidget: Widget {
    init() {}

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "second", provider: ImmediateProvider()) { entry in
            Text(verbatim: "\(entry.value)")
        }
    }
}

private struct TestBundle: WidgetBundle {
    init() {}

    var body: some Widget {
        FirstWidget()
        SecondWidget()
    }
}

private struct DuplicateBundle: WidgetBundle {
    init() {}

    var body: some Widget {
        FirstWidget()
        FirstWidget()
    }
}

private struct UnsupportedConfiguration: WidgetConfiguration {
    typealias Body = Never
}

private final class DiagnosticRecorder: Sendable {
    private let storage = Mutex<[WidgetRuntimeDiagnostic]>([])

    var values: [WidgetRuntimeDiagnostic] {
        storage.withLock { $0 }
    }

    func record(_ diagnostic: WidgetRuntimeDiagnostic) {
        storage.withLock { $0.append(diagnostic) }
    }
}

private final class RecordingControl: WidgetRuntimeControl, Sendable {
    private struct State: Sendable {
        var reloadedKinds: [String] = []
        var reloadAllCount = 0
    }

    private let state = Mutex(State())

    var reloadedKinds: [String] {
        state.withLock { $0.reloadedKinds }
    }

    var reloadAllCount: Int {
        state.withLock { $0.reloadAllCount }
    }

    func reloadTimelines(ofKind kind: String) {
        state.withLock { $0.reloadedKinds.append(kind) }
    }

    func reloadAllTimelines() {
        state.withLock { $0.reloadAllCount += 1 }
    }

    func getCurrentConfigurations(
        _ completion: @escaping @Sendable (
            Result<[RuntimeWidgetInfo], WidgetRuntimeError>
        ) -> Void
    ) {
        completion(
            .success([
                RuntimeWidgetInfo(
                    instanceID: "instance",
                    kind: "weather",
                    family: .systemMedium
                )
            ])
        )
    }
}

@MainActor
private final class RecordingBootstrap: WidgetRuntimeBootstrap, Sendable {
    private(set) var kinds: [String] = []

    func run(registry: RuntimeWidgetRegistry) {
        kinds = registry.definitions.map(\.kind)
    }
}

private enum ConfigurationTestFailure: Error {
    case conditionNotReached
}
