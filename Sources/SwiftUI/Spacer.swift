import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct Spacer {
    public var minLength: CGFloat?

    public init(minLength: CGFloat? = nil) {
        self.minLength = minLength
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Spacer: View {
    public typealias Body = Never
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Spacer: WidgetNodeConvertible {
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        if let minLength, !minLength.isFinite {
            throw WidgetSemanticError.nonFiniteLayoutValue(field: "Spacer.minLength")
        }
        return [WidgetNode(id: context.path, kind: .spacer(minLength: minLength))]
    }
}
