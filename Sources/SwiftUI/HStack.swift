import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
nonisolated public struct HStack<Content>: View where Content: View {
    public typealias Body = Never

    private let alignment: VerticalAlignment
    private let spacing: CGFloat?
    private let content: Content

    nonisolated public init(
        alignment: VerticalAlignment = .center,
        spacing: CGFloat? = nil,
        @ContentBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension HStack: WidgetNodeConvertible {
    @MainActor
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        if let spacing, !spacing.isFinite {
            throw WidgetSemanticError.nonFiniteLayoutValue(field: "HStack.spacing")
        }
        let id = context.path
        let children = try context.withPath(.role("content")) {
            try lowerWidgetView(content, in: &$0)
        }
        return [
            WidgetNode(
                id: id,
                kind: .horizontalStack(
                    alignment: alignment.widgetValue,
                    spacing: spacing
                ),
                children: children
            )
        ]
    }
}
