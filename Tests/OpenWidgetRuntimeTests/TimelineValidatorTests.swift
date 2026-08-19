@testable import OpenWidgetRuntime
import OpenFoundation
import Testing

@Suite
struct TimelineValidatorTests {
    @Test
    func acceptsNondecreasingFiniteDates() throws {
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 100)

        let validated = try TimelineValidator.validate(
            entryDates: [first, second],
            reloadPolicy: .atEnd
        )

        #expect(validated.entryDates == [first, second])
        #expect(validated.reloadPolicy == .atEnd)
    }

    @Test
    func rejectsEmptyTimeline() {
        #expect(throws: TimelineRuntimeError.emptyTimeline) {
            try TimelineValidator.validate(entryDates: [], reloadPolicy: .never)
        }
    }

    @Test
    func rejectsNonFiniteEntryDate() {
        #expect(throws: TimelineRuntimeError.nonFiniteEntryDate(index: 1)) {
            try TimelineValidator.validate(
                entryDates: [
                    Date(timeIntervalSince1970: 1),
                    Date(timeIntervalSince1970: .infinity)
                ],
                reloadPolicy: .atEnd
            )
        }
    }

    @Test
    func rejectsOutOfOrderEntries() {
        #expect(throws: TimelineRuntimeError.entriesOutOfOrder(previousIndex: 0, index: 1)) {
            try TimelineValidator.validate(
                entryDates: [
                    Date(timeIntervalSince1970: 2),
                    Date(timeIntervalSince1970: 1)
                ],
                reloadPolicy: .atEnd
            )
        }
    }

    @Test
    func rejectsNonFiniteReloadDate() {
        #expect(throws: TimelineRuntimeError.nonFiniteReloadDate) {
            try TimelineValidator.validate(
                entryDates: [Date(timeIntervalSince1970: 1)],
                reloadPolicy: .after(Date(timeIntervalSince1970: .nan))
            )
        }
    }
}
