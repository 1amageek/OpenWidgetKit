package struct WidgetEdge: OptionSet, Equatable, Sendable {
    package let rawValue: Int8

    package init(rawValue: Int8) {
        self.rawValue = rawValue
    }

    package static let top = WidgetEdge(rawValue: 1 << 0)
    package static let leading = WidgetEdge(rawValue: 1 << 1)
    package static let bottom = WidgetEdge(rawValue: 1 << 2)
    package static let trailing = WidgetEdge(rawValue: 1 << 3)
    package static let all: WidgetEdge = [.top, .leading, .bottom, .trailing]
    package static let horizontal: WidgetEdge = [.leading, .trailing]
    package static let vertical: WidgetEdge = [.top, .bottom]
}
