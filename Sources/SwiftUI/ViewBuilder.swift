import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
@resultBuilder
public struct ViewBuilder {
    public static func buildBlock() -> EmptyContent {
        EmptyContent()
    }

    public static func buildBlock<Content>(_ content: Content) -> Content {
        content
    }

    @_disfavoredOverload
    public static func buildBlock<each Content>(
        _ content: repeat each Content
    ) -> TupleView<(repeat each Content)> where repeat each Content: View {
        var lowerings: [any TupleViewElementLowering] = []
        for element in repeat each content {
            lowerings.append(TypedTupleViewElementLowering(content: element))
        }
        return TupleView(
            (repeat each content),
            lowering: CompositeTupleViewLowering(elements: lowerings)
        )
    }

    public static func buildIf<Content>(_ content: Content?) -> Content? {
        content
    }

    public static func buildEither<TrueContent, FalseContent>(
        first: TrueContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        _ConditionalContent(_storage: .trueContent(first))
    }

    public static func buildEither<TrueContent, FalseContent>(
        second: FalseContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        _ConditionalContent(_storage: .falseContent(second))
    }

    @available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
    public static func buildLimitedAvailability<Content>(
        _ content: Content
    ) -> AnyView where Content: View {
        AnyView(content)
    }

}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public typealias ContentBuilder = ViewBuilder

@available(*, unavailable)
extension ViewBuilder: Sendable {}
