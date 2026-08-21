import OpenFoundation

package struct WidgetNode: Equatable, Sendable {
    package enum Kind: Equatable, Sendable {
        case empty
        case text(WidgetText)
        case image(WidgetImage)
        case color(WidgetColor)
        case verticalStack(
            alignment: WidgetHorizontalAlignment,
            spacing: CGFloat?
        )
        case horizontalStack(
            alignment: WidgetVerticalAlignment,
            spacing: CGFloat?
        )
        case group
        case spacer(minLength: CGFloat?)
        case divider
        case action(WidgetActionDescriptor)
        case modified(WidgetModifier)
        case background(
            alignment: WidgetAlignment,
            ignoredEdges: WidgetEdge?,
            foregroundCount: Int
        )
    }

    package let id: WidgetNodeID
    package let kind: Kind
    package let children: [WidgetNode]

    package init(
        id: WidgetNodeID,
        kind: Kind,
        children: [WidgetNode] = []
    ) {
        self.id = id
        self.kind = kind
        self.children = children
    }
}
