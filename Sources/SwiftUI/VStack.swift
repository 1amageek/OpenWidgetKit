import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
nonisolated public struct VStack<Content>: View where Content: View {
    public typealias Body = Never

    private let alignment: HorizontalAlignment
    private let spacing: CGFloat?
    private let content: Content

    nonisolated public init(
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ContentBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension VStack: WidgetNodeConvertible {
    @MainActor
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        if let spacing, !spacing.isFinite {
            throw WidgetSemanticError.nonFiniteLayoutValue(field: "VStack.spacing")
        }
        let id = context.path
        let children = try context.withPath(.role("content")) {
            try lowerWidgetView(content, in: &$0)
        }
        return [
            WidgetNode(
                id: id,
                kind: .verticalStack(
                    alignment: alignment.widgetValue,
                    spacing: spacing
                ),
                children: children
            )
        ]
    }
}
