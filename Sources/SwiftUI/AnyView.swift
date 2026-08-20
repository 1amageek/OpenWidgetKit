import OpenWidgetRuntime

nonisolated package protocol AnyViewLowering {
    @MainActor
    func lower(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode]
}

nonisolated package struct TypedAnyViewLowering<Content>: AnyViewLowering
where Content: View {
    package let content: Content

    nonisolated package init(content: Content) {
        self.content = content
    }

    @MainActor
    package func lower(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        try lowerWidgetView(content, in: &context)
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
nonisolated public struct AnyView: View {
    public typealias Body = Never

    private let lowering: any AnyViewLowering

    nonisolated public init<Content>(_ content: Content) where Content: View {
        lowering = TypedAnyViewLowering(content: content)
    }

    nonisolated public init<Content>(erasing content: Content) where Content: View {
        self.init(content)
    }

    nonisolated public init?(_fromValue value: Any) {
        guard let content = value as? any View else { return nil }
        self.init(content)
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension AnyView: WidgetNodeConvertible {
    @MainActor
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        try lowering.lower(in: &context)
    }
}
