import OpenWidgetRuntime

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 1.0, *)
@available(tvOS, unavailable)
@preconcurrency
@MainActor
public protocol WidgetBundle {
    associatedtype Body: Widget

    @MainActor
    @preconcurrency
    init()

    @WidgetBundleBuilder
    @MainActor
    @preconcurrency
    var body: Body { get }
}

@MainActor
package func lowerWidgetBundle<Bundle: WidgetBundle>(
    _ bundle: Bundle
) throws -> [RuntimeWidgetDefinition] {
    try lowerWidget(bundle.body)
}
