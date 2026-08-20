import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct Group<Content> {
    public typealias Body = Never

    package let content: Content

    nonisolated public init(@ContentBuilder content: () -> Content) {
        self.content = content()
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Group: View where Content: View {}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Group: WidgetNodeConvertible where Content: View {
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        let id = context.path
        let children = try context.withPath(.role("content")) {
            try lowerWidgetView(content, in: &$0)
        }
        return [WidgetNode(id: id, kind: .group, children: children)]
    }
}
