@MainActor
package struct RuntimeWidgetDefinition: Sendable {
    package typealias TimelineRequest = @MainActor @Sendable (
        RuntimeProviderContext,
        Duration,
        @escaping WidgetRuntimeDiagnosticSink
    ) async throws -> RuntimeTimeline

    package let kind: String
    package let supportedFamilies: [RuntimeWidgetFamily]
    package let displayName: WidgetText?
    package let configurationDescription: WidgetText?
    private let timelineRequest: TimelineRequest

    package init(
        kind: String,
        supportedFamilies: [RuntimeWidgetFamily] = RuntimeWidgetFamily.allCases,
        displayName: WidgetText? = nil,
        configurationDescription: WidgetText? = nil,
        timelineRequest: @escaping TimelineRequest
    ) {
        self.kind = kind
        self.supportedFamilies = supportedFamilies
        self.displayName = displayName
        self.configurationDescription = configurationDescription
        self.timelineRequest = timelineRequest
    }

    package func requestTimeline(
        context: RuntimeProviderContext,
        timeout: Duration,
        diagnostics: @escaping WidgetRuntimeDiagnosticSink
    ) async throws -> RuntimeTimeline {
        try await timelineRequest(context, timeout, diagnostics)
    }

    package func withSupportedFamilies(
        _ supportedFamilies: [RuntimeWidgetFamily]
    ) -> RuntimeWidgetDefinition {
        RuntimeWidgetDefinition(
            kind: kind,
            supportedFamilies: supportedFamilies,
            displayName: displayName,
            configurationDescription: configurationDescription,
            timelineRequest: timelineRequest
        )
    }

    package func withDisplayName(_ displayName: WidgetText) -> RuntimeWidgetDefinition {
        RuntimeWidgetDefinition(
            kind: kind,
            supportedFamilies: supportedFamilies,
            displayName: displayName,
            configurationDescription: configurationDescription,
            timelineRequest: timelineRequest
        )
    }

    package func withConfigurationDescription(
        _ configurationDescription: WidgetText
    ) -> RuntimeWidgetDefinition {
        RuntimeWidgetDefinition(
            kind: kind,
            supportedFamilies: supportedFamilies,
            displayName: displayName,
            configurationDescription: configurationDescription,
            timelineRequest: timelineRequest
        )
    }
}
