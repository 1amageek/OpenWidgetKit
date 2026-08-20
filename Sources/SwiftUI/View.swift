@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
@preconcurrency
@MainActor
public protocol View {
    associatedtype Body: View

    @ViewBuilder
    @MainActor
    @preconcurrency
    var body: Body { get }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension View where Body == Never {
    public var body: Never {
        preconditionFailure("A primitive View has no body.")
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Never: View {
    public typealias Body = Never

    public var body: Never {
        self
    }
}
