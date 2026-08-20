import SwiftUI
import WidgetKit

@available(macOS 11.0, iOS 14.0, watchOS 9.0, *)
private struct BundleEntry: TimelineEntry {
    let date: Date
}

@available(macOS 11.0, iOS 14.0, watchOS 9.0, *)
private struct BundleProvider: TimelineProvider {
    func placeholder(in context: Context) -> BundleEntry {
        BundleEntry(date: Date(timeIntervalSince1970: 0))
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (BundleEntry) -> Void
    ) {
        completion(placeholder(in: context))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<BundleEntry>) -> Void
    ) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}

@available(macOS 11.0, iOS 14.0, watchOS 9.0, *)
private struct BundledWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "openwidgetkit.m1.bundle",
            provider: BundleProvider()
        ) { _ in
            Text("Bundle")
        }
    }
}

@available(macOS 11.0, iOS 14.0, watchOS 9.0, *)
@main
private struct CanonicalWidgetBundle: WidgetBundle {
    var body: some Widget {
        BundledWidget()
    }
}
