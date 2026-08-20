package struct WidgetNodeID: Hashable, Sendable {
    package enum Component: Hashable, Sendable {
        case structural(Int)
        case keyed(UInt64)
        case role(String)
    }

    package let components: [Component]

    package init(components: [Component] = []) {
        self.components = components
    }

    package func appending(_ component: Component) -> WidgetNodeID {
        WidgetNodeID(components: components + [component])
    }
}
