import OpenWidgetRuntime

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 1.0, *)
@available(tvOS, unavailable)
@resultBuilder
public struct WidgetBundleBuilder {
    public static func buildExpression<Content>(
        _ content: Content
    ) -> Content where Content: Widget {
        content
    }

    public static func buildBlock() -> some Widget {
        EmptyWidget()
    }

    public static func buildBlock<Content>(
        _ content: Content
    ) -> some Widget where Content: Widget {
        content
    }

    @_disfavoredOverload
    public static func buildBlock<each Content>(
        _ content: repeat each Content
    ) -> some Widget where repeat each Content: Widget {
        var lowerings: [any WidgetElementLowering] = []
        for element in repeat each content {
            lowerings.append(TypedWidgetElementLowering(content: element))
        }
        return TupleWidget(lowerings: lowerings)
    }
}

nonisolated private struct EmptyWidgetConfiguration: WidgetConfiguration {
    typealias Body = Never
}

nonisolated private struct EmptyWidget: Widget {
    typealias Body = EmptyWidgetConfiguration

    init() {}

    @MainActor
    var body: EmptyWidgetConfiguration {
        EmptyWidgetConfiguration()
    }
}

extension EmptyWidget: WidgetListLowering {
    @MainActor
    func makeRuntimeWidgetDefinitions() throws -> [RuntimeWidgetDefinition] {
        []
    }
}

nonisolated private protocol WidgetElementLowering {
    @MainActor
    func lower() throws -> [RuntimeWidgetDefinition]
}

nonisolated private struct TypedWidgetElementLowering<Content>: WidgetElementLowering
where Content: Widget {
    let content: Content

    @MainActor
    func lower() throws -> [RuntimeWidgetDefinition] {
        try lowerWidget(content)
    }
}

nonisolated private struct TupleWidget: Widget {
    typealias Body = EmptyWidgetConfiguration

    let lowerings: [any WidgetElementLowering]

    init() {
        lowerings = []
    }

    init(lowerings: [any WidgetElementLowering]) {
        self.lowerings = lowerings
    }

    @MainActor
    var body: EmptyWidgetConfiguration {
        EmptyWidgetConfiguration()
    }
}

extension TupleWidget: WidgetListLowering {
    @MainActor
    func makeRuntimeWidgetDefinitions() throws -> [RuntimeWidgetDefinition] {
        try lowerings.flatMap { try $0.lower() }
    }
}
