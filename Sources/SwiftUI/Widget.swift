import OpenWidgetRuntime

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 1.0, *)
@available(tvOS, unavailable)
@preconcurrency
@MainActor
public protocol Widget {
    associatedtype Body: WidgetConfiguration

    @MainActor
    @preconcurrency
    init()

    @MainActor
    @preconcurrency
    var body: Body { get }
}

nonisolated package protocol WidgetListLowering {
    @MainActor
    func makeRuntimeWidgetDefinitions() throws -> [RuntimeWidgetDefinition]
}

@MainActor
package func lowerWidget<Content: Widget>(
    _ widget: Content
) throws -> [RuntimeWidgetDefinition] {
    if let lowering = widget as? any WidgetListLowering {
        return try lowering.makeRuntimeWidgetDefinitions()
    }
    return try lowerWidgetConfiguration(widget.body)
}
