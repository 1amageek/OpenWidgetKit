import SwiftUI
import WidgetKit

@available(macOS 11.0, iOS 14.0, watchOS 9.0, *)
private struct CanonicalStaticEntry: TimelineEntry {
    let date: Date
    let title: String
}

@available(macOS 11.0, iOS 14.0, watchOS 9.0, *)
private struct CanonicalStaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> CanonicalStaticEntry {
        CanonicalStaticEntry(date: Date(timeIntervalSince1970: 0), title: "Placeholder")
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (CanonicalStaticEntry) -> Void
    ) {
        completion(placeholder(in: context))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<CanonicalStaticEntry>) -> Void
    ) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .atEnd))
    }
}

@available(macOS 11.0, iOS 14.0, watchOS 9.0, *)
@main
private struct CanonicalStaticWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "openwidgetkit.m1.static",
            provider: CanonicalStaticProvider()
        ) { entry in
            Text(entry.title)
        }
    }
}
