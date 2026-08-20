import OpenWidgetRuntime

enum WidgetEnvironmentContext {
    @TaskLocal
    static var snapshot = WidgetEnvironmentSnapshot()
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
@propertyWrapper
public struct Environment<Value>: DynamicProperty {
    private let keyPath: KeyPath<EnvironmentValues, Value>

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.keyPath = keyPath
    }

    public var wrappedValue: Value {
        EnvironmentValues(snapshot: WidgetEnvironmentContext.snapshot)[keyPath: keyPath]
    }
}
