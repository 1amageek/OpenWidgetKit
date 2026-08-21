package struct RuntimeTimeline: Sendable {
    package let entries: [RuntimeTimelineEntry]
    package let reloadPolicy: RuntimeTimelineReloadPolicy

    package init(
        entries: [RuntimeTimelineEntry],
        reloadPolicy: RuntimeTimelineReloadPolicy
    ) throws {
        _ = try TimelineValidator.validate(
            entryDates: entries.map(\.date),
            reloadPolicy: reloadPolicy
        )
        self.entries = entries
        self.reloadPolicy = reloadPolicy
    }
}
