@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public protocol IntentResult: Sendable {
    associatedtype Value = Never
    associatedtype Snippet = Never
    associatedtype Dialog = Never
    associatedtype OpensAppIntent = Never

    var value: Value? { get }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
extension IntentResult where Self == IntentResultContainer<Never, Never, Never, Never> {
    public static func result() -> Self {
        Self()
    }
}
