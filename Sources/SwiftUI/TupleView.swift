import OpenWidgetRuntime

nonisolated package protocol TupleViewLowering {
    @MainActor
    func lower(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode]
}

nonisolated package struct UnsupportedTupleViewLowering<Value>: TupleViewLowering {
    package init() {}

    @MainActor
    package func lower(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        throw WidgetSemanticError.unsupportedView(
            typeName: String(reflecting: TupleView<Value>.self)
        )
    }
}

nonisolated package protocol TupleViewElementLowering {
    @MainActor
    func lower(
        at index: Int,
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode]
}

nonisolated package struct TypedTupleViewElementLowering<Content>: TupleViewElementLowering
where Content: View {
    package let content: Content

    nonisolated package init(content: Content) {
        self.content = content
    }

    @MainActor
    package func lower(
        at index: Int,
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        try context.withPath(.structural(index)) {
            try lowerWidgetView(content, in: &$0)
        }
    }
}

nonisolated package struct CompositeTupleViewLowering: TupleViewLowering {
    package let elements: [any TupleViewElementLowering]

    nonisolated package init(elements: [any TupleViewElementLowering]) {
        self.elements = elements
    }

    @MainActor
    package func lower(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        var result: [WidgetNode] = []
        for (index, element) in elements.enumerated() {
            result.append(contentsOf: try element.lower(at: index, in: &context))
        }
        return result
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
nonisolated public struct TupleView<Value>: View {
    public typealias Body = Never

    public var value: Value
    private let lowering: any TupleViewLowering

    nonisolated public init(_ value: Value) {
        self.value = value
        lowering = UnsupportedTupleViewLowering<Value>()
    }

    package init(
        _ value: Value,
        lowering: any TupleViewLowering
    ) {
        self.value = value
        self.lowering = lowering
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension TupleView: WidgetNodeConvertible {
    @MainActor
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        try lowering.lower(in: &context)
    }
}
