import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct ForEach<Data, ID, Content>
where Data: RandomAccessCollection, ID: Hashable {
    public var data: Data
    public var content: (Data.Element) -> Content

    private let identifier: KeyPath<Data.Element, ID>

    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ContentBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.identifier = id
        self.content = content
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension ForEach where ID == Data.Element.ID, Data.Element: Identifiable {
    public init(
        _ data: Data,
        @ContentBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.init(data, id: \.id, content: content)
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension ForEach: View where Content: View {
    public typealias Body = Never
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension ForEach: WidgetNodeConvertible where Content: View {
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        var seen: Set<ID> = []
        var result: [WidgetNode] = []

        for element in data {
            let value = element[keyPath: identifier]
            guard seen.insert(value).inserted else {
                throw WidgetSemanticError.duplicateStableID(
                    typeName: String(reflecting: ID.self)
                )
            }
            let identifier = context.identityStore.identifier(
                for: value,
                namespace: context.path
            )
            let nodes = try context.withPath(.keyed(identifier)) {
                try lowerWidgetView(content(element), in: &$0)
            }
            result.append(contentsOf: nodes)
        }

        return result
    }
}
