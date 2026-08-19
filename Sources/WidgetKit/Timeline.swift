import OpenWidgetRuntime

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
