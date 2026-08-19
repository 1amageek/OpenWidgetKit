import OpenFoundation

package enum TimelineValidator {
    package static func validate(
        entryDates: [Date],
        reloadPolicy: RuntimeTimelineReloadPolicy
    ) throws -> ValidatedTimeline {
        guard !entryDates.isEmpty else {
            throw TimelineRuntimeError.emptyTimeline
        }

        for (index, date) in entryDates.enumerated() {
            guard date.timeIntervalSince1970.isFinite else {
                throw TimelineRuntimeError.nonFiniteEntryDate(index: index)
            }
            if index > 0, entryDates[index - 1] > date {
                throw TimelineRuntimeError.entriesOutOfOrder(
                    previousIndex: index - 1,
                    index: index
                )
            }
        }

        if case .after(let date) = reloadPolicy,
           !date.timeIntervalSince1970.isFinite {
            throw TimelineRuntimeError.nonFiniteReloadDate
        }

        return ValidatedTimeline(
            entryDates: entryDates,
            reloadPolicy: reloadPolicy
        )
    }
}
