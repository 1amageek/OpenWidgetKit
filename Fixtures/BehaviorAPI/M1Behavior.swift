import WidgetKit

@available(macOS 11.0, iOS 14.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
private struct BehaviorEntry: TimelineEntry {
    let date: Date
}

@available(macOS 11.0, iOS 14.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@main
private struct M1Behavior {
    static func main() throws {
        let families: [WidgetFamily] = [
            .systemSmall,
            .systemMedium,
            .systemLarge
        ]

        for family in families {
            print(
                "family:\(family.rawValue):\(family.description):\(family.debugDescription)"
            )
        }
        print("family-set-count:\(Set(families).count)")

        let reloadDate = Date(timeIntervalSince1970: 42)
        let policies: [TimelineReloadPolicy] = [
            .atEnd,
            .never,
            .after(reloadDate)
        ]
        print(
            "policy:\(policies[0] == .atEnd):\(policies[0] == .never):\(policies[1] == .never):\(policies[2] == .after(reloadDate)):\(policies[2] == .after(Date(timeIntervalSince1970: 43)))"
        )

        let timeline = Timeline(
            entries: [BehaviorEntry(date: reloadDate)],
            policy: policies[2]
        )
        print(
            "timeline:\(timeline.entries.count):\(timeline.entries[0].date.timeIntervalSince1970):\(timeline.policy == .after(reloadDate))"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let relevance = TimelineEntryRelevance(score: 5, duration: 60)
        let encodedRelevance = try encoder.encode(relevance)
        print("relevance:\(String(decoding: encodedRelevance, as: UTF8.self))")
        print("relevance-default-duration:\(TimelineEntryRelevance(score: 1).duration)")
    }
}
