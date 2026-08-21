@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public protocol PersistentlyIdentifiable {
    static var persistentIdentifier: String { get }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
extension PersistentlyIdentifiable {
    public static var persistentIdentifier: String {
        String(reflecting: Self.self)
    }
}
