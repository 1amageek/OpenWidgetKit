import SwiftUI
import WidgetKit

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
public struct InitialTimelineFixtureEntry: TimelineEntry {
    public let date: Date
    public let relevance: TimelineEntryRelevance?

    public init(date: Date, relevance: TimelineEntryRelevance? = nil) {
        self.date = date
        self.relevance = relevance
    }
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
public struct InitialTimelineFixtureProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> InitialTimelineFixtureEntry {
        InitialTimelineFixtureEntry(date: Date(timeIntervalSince1970: 0))
    }

    public func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (InitialTimelineFixtureEntry) -> Void
    ) {
        completion(placeholder(in: context))
    }

    public func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<InitialTimelineFixtureEntry>) -> Void
    ) {
        completion(
            Timeline(
                entries: [placeholder(in: context)],
                policy: .never
            )
        )
    }
}

@available(iOS 14.0, macOS 11.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public func verifyInitialTimelineSurface(
    context: TimelineProviderContext,
    date: Date,
    scalar: CGFloat,
    point: CGPoint,
    size: CGSize,
    rect: CGRect
) -> Timeline<InitialTimelineFixtureEntry> {
    let relevance = TimelineEntryRelevance(score: Float(scalar), duration: 60)
    let entry = InitialTimelineFixtureEntry(date: date, relevance: relevance)
    let policies: [TimelineReloadPolicy] = [
        .atEnd,
        .after(date),
        .never
    ]
    let families: [WidgetFamily] = [
        .systemSmall,
        .systemMedium,
        .systemLarge
    ]
    let geometry = CGRect(origin: point, size: size)

    _ = context.environmentVariants
    _ = context.family
    _ = context.isPreview
    _ = context.displaySize
    _ = rect
    _ = geometry
    _ = families

    return Timeline(entries: [entry], policy: policies[2])
}
