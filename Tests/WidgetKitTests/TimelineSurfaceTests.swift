@testable import WidgetKit
import OpenWidgetRuntime
import Testing

@Suite
struct TimelineSurfaceTests {
    private struct Entry: TimelineEntry {
        let date: Date
        let value: Int
    }

    private struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry {
            Entry(date: Date(timeIntervalSince1970: 0), value: 0)
        }

        func getSnapshot(
            in context: Context,
            completion: @escaping @Sendable (Entry) -> Void
        ) {
            completion(placeholder(in: context))
        }

        func getTimeline(
            in context: Context,
            completion: @escaping @Sendable (Timeline<Entry>) -> Void
        ) {
            completion(Timeline(entries: [placeholder(in: context)], policy: .never))
        }
    }

    @Test
    func storesEntriesAndReloadPolicy() throws {
        let entry = Entry(date: Date(timeIntervalSince1970: 42), value: 7)
        let timeline = Timeline(entries: [entry], policy: .never)

        #expect(timeline.entries.map(\.value) == [7])
        #expect(timeline.policy == .never)
        #expect(try timeline.validatedRuntimeValue().entryDates == [entry.date])
    }

    @Test
    func preservesAfterDate() throws {
        let reloadDate = Date(timeIntervalSince1970: 100)
        let timeline = Timeline(
            entries: [Entry(date: Date(timeIntervalSince1970: 1), value: 0)],
            policy: .after(reloadDate)
        )

        #expect(try timeline.validatedRuntimeValue().reloadPolicy == .after(reloadDate))
    }

    @Test
    func entryUsesNilRelevanceByDefault() {
        let entry = Entry(date: Date(timeIntervalSince1970: 1), value: 0)

        #expect(entry.relevance == nil)
    }

    @Test
    func relevancePreservesScoreAndDuration() {
        let relevance = TimelineEntryRelevance(score: 5, duration: 60)

        #expect(relevance.score == 5)
        #expect(relevance.duration == 60)
    }

    @Test
    func contextUsesFoundationGeometryIdentity() {
        let context = TimelineProviderContext(
            family: .systemMedium,
            isPreview: true,
            displaySize: CGSize(width: 320, height: 160)
        )

        #expect(context.family == .systemMedium)
        #expect(context.isPreview)
        #expect(context.displaySize.width == 320)
    }

    @Test
    func environmentVariantsMatchAppleKeyPathCallShape() {
        var environment = EnvironmentValues()
        environment.fixtureValue = 7
        let variants = TimelineProviderContext.EnvironmentVariants(
            values: [environment]
        )

        #expect(variants[keyPath: \.fixtureValue] == [7])
        #expect(variants.fixtureValue == [7])
    }

    @Test
    func providerUsesCallbackSurface() {
        let context = TimelineProviderContext(
            family: .systemSmall,
            isPreview: false,
            displaySize: CGSize(width: 160, height: 160)
        )

        #expect(Provider().placeholder(in: context).date.timeIntervalSince1970 == 0)
    }
}

private extension EnvironmentValues {
    var fixtureValue: Int {
        get { 7 }
        set {}
    }
}
