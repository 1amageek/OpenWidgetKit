import OpenWidgetRuntime

nonisolated struct BackgroundWidgetView<Content, Background>: View
where Content: View, Background: View {
    typealias Body = Never

    let content: Content
    let background: Background
    let alignment: Alignment
}

extension BackgroundWidgetView: WidgetNodeConvertible {
    @MainActor
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        let id = context.path
        let foregroundNodes = try context.withPath(.role("foreground")) {
            try lowerWidgetView(content, in: &$0)
        }
        let backgroundNodes = try context.withPath(.role("background")) {
            try lowerWidgetView(background, in: &$0)
        }
        return [
            WidgetNode(
                id: id,
                kind: .background(
                    alignment: alignment.widgetValue,
                    ignoredEdges: nil
                ),
                children: foregroundNodes + backgroundNodes
            )
        ]
    }
}

nonisolated struct BackgroundStyleWidgetView<Content, Style>: View
where Content: View, Style: ShapeStyle {
    typealias Body = Never

    let content: Content
    let style: Style
    let ignoredEdges: Edge.Set
}

extension BackgroundStyleWidgetView: WidgetNodeConvertible {
    @MainActor
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        guard let color = style as? Color else {
            throw WidgetSemanticError.unsupportedView(
                typeName: String(reflecting: Style.self)
            )
        }
        let id = context.path
        let foregroundNodes = try context.withPath(.role("foreground")) {
            try lowerWidgetView(content, in: &$0)
        }
        let backgroundNodes = try context.withPath(.role("background")) {
            try lowerWidgetView(color, in: &$0)
        }
        return [
            WidgetNode(
                id: id,
                kind: .background(
                    alignment: Alignment.center.widgetValue,
                    ignoredEdges: ignoredEdges.widgetValue
                ),
                children: foregroundNodes + backgroundNodes
            )
        ]
    }
}
