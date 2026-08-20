import OpenWidgetRuntime

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
public struct Timeline<EntryType> where EntryType: TimelineEntry {
    public let entries: [EntryType]
    public let policy: TimelineReloadPolicy

    public init(entries: [EntryType], policy: TimelineReloadPolicy) {
        self.entries = entries
        self.policy = policy
    }

    package func validatedRuntimeValue() throws -> ValidatedTimeline {
        try TimelineValidator.validate(
            entryDates: entries.map(\.date),
            reloadPolicy: policy.runtimeValue
        )
    }
}
