import SwiftUI
import WidgetKit

private struct FixtureWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
}

private struct FixtureWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FixtureWidgetEntry {
        FixtureWidgetEntry(
            date: Date(timeIntervalSince1970: 0),
            title: "Placeholder"
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (FixtureWidgetEntry) -> Void
    ) {
        completion(placeholder(in: context))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<FixtureWidgetEntry>) -> Void
    ) {
        completion(
            Timeline(
                entries: [placeholder(in: context)],
                policy: .never
            )
        )
    }
}

private struct FixtureStaticWidget: Widget {
    var body: some WidgetConfiguration {
#if os(watchOS)
        StaticConfiguration(
            kind: "openwidgetkit.fixture.static",
            provider: FixtureWidgetProvider()
        ) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                Image(systemName: "star")
            }
        }
        .configurationDisplayName("Fixture")
        .description(Text(verbatim: "Fixture description"))
#else
        StaticConfiguration(
            kind: "openwidgetkit.fixture.static",
            provider: FixtureWidgetProvider()
        ) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                Image(systemName: "star")
            }
        }
        .configurationDisplayName("Fixture")
        .description(Text(verbatim: "Fixture description"))
        .supportedFamilies([.systemSmall, .systemMedium])
#endif
    }
}

private struct FixtureSecondaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "openwidgetkit.fixture.secondary",
            provider: FixtureWidgetProvider()
        ) { entry in
            Text(entry.title)
        }
    }
}

private struct FixtureWidgetBundle: WidgetBundle {
    var body: some Widget {
        FixtureStaticWidget()
        FixtureSecondaryWidget()
    }
}

public func compileM2M3Surface() {
    let _: any Widget.Type = FixtureStaticWidget.self
    let _: any WidgetBundle.Type = FixtureWidgetBundle.self
    let center = WidgetCenter.shared
    center.reloadTimelines(ofKind: "openwidgetkit.fixture.static")
    center.reloadAllTimelines()
    center.getCurrentConfigurations { _ in }
    requireDynamicProperty(Environment<ColorScheme>.self)
}

private func requireDynamicProperty<Value: DynamicProperty>(_: Value.Type) {}
