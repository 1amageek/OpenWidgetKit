import OpenFoundation

package struct ValidatedTimeline: Equatable, Sendable {
    package let entryDates: [Date]
    package let reloadPolicy: RuntimeTimelineReloadPolicy

    package init(
        entryDates: [Date],
        reloadPolicy: RuntimeTimelineReloadPolicy
    ) {
        self.entryDates = entryDates
        self.reloadPolicy = reloadPolicy
    }
}
