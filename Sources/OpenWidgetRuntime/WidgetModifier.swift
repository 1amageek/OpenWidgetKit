package enum WidgetModifier: Equatable, Sendable {
    case padding(edges: WidgetEdge, insets: WidgetInsets?)
    case frame(WidgetFrame)
    case font(WidgetFont?)
    case foregroundColor(WidgetColor?)
    case lineLimit(Int?)
}
