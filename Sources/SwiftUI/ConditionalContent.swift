import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct _ConditionalContent<TrueContent, FalseContent> {
    public enum Storage {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }

    public let storage: Storage

    public init(_storage: Storage) {
        storage = _storage
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension _ConditionalContent: View where TrueContent: View, FalseContent: View {
    public typealias Body = Never
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension _ConditionalContent: WidgetNodeConvertible
where TrueContent: View, FalseContent: View {
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        switch storage {
        case .trueContent(let content):
            return try context.withPath(.role("true")) {
                try lowerWidgetView(content, in: &$0)
            }
        case .falseContent(let content):
            return try context.withPath(.role("false")) {
                try lowerWidgetView(content, in: &$0)
            }
        }
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Optional: View where Wrapped: View {
    public typealias Body = Never
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Optional: WidgetNodeConvertible where Wrapped: View {
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        guard let content = self else { return [] }
        return try context.withPath(.role("some")) {
            try lowerWidgetView(content, in: &$0)
        }
    }
}
