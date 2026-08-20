import SwiftUI
import WidgetKit

private struct WindowsProviderEntry: TimelineEntry {
    let date: Date
    let title: String
}

private struct WindowsProviderTimeline: TimelineProvider {
    func placeholder(in context: Context) -> WindowsProviderEntry {
        WindowsProviderEntry(
            date: Date(timeIntervalSince1970: 0),
            title: "OpenWidgetKit"
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (WindowsProviderEntry) -> Void
    ) {
        completion(placeholder(in: context))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<WindowsProviderEntry>) -> Void
    ) {
        completion(
            Timeline(
                entries: [placeholder(in: context)],
                policy: .never
            )
        )
    }
}

@main
private struct WindowsProviderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "openwidgetkit.windows.fixture",
            provider: WindowsProviderTimeline()
        ) { entry in
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title).font(.headline)
                Text(verbatim: "Swift WidgetKit on Windows")
                    .foregroundColor(.secondary)
            }
        }
        .configurationDisplayName("OpenWidgetKit Fixture")
        .description("Static provider validation fixture")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
